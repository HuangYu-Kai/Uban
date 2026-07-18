import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';

import '../../services/api_service.dart';
import '../../services/signaling.dart';

enum AgentState { idle, listening, thinking, speaking }

class ZenPondScreen extends StatefulWidget {
  final Function(bool isVisible)? onOverlayStateChanged;
  const ZenPondScreen({super.key, this.onOverlayStateChanged});

  @override
  State<ZenPondScreen> createState() => ZenPondScreenState();
}

class ZenPondScreenState extends State<ZenPondScreen> with TickerProviderStateMixin {
  // 核心語音服務
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 狀態管理
  AgentState _agentState = AgentState.idle;
  bool _speechEnabled = false;
  String _userWords = "";
  String _aiWords = "您好！我是您的語音陪伴小幫手。今天心情好嗎？隨時點擊圓球對我說說話吧！";
  int _userId = 1;
  String _language = 'mandarin'; // 'mandarin' 或 'taiwanese'
  String? _mandarinLocaleId;
  String? _taiwaneseLocaleId;

  // 動畫控制器
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _initServices();
    _bindSocketCallbacks();

    // 監聽歷史語音播放狀態
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted && _agentState == AgentState.speaking) {
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          _updateState(AgentState.idle);
        }
      }
    });
  }

  @override
  void dispose() {
    _speechToText.stop();
    _flutterTts.stop();
    _audioPlayer.dispose();
    _rotationController.dispose();
    Signaling().onNewPondLeaf = null;
    super.dispose();
  }

  // 初始化 STT, TTS 與使用者資訊
  Future<void> _initServices() async {
    // 獲取使用者 ID 與語音偏好
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userId = prefs.getInt('caregiver_id') ?? 1;
        _language = prefs.getString('voice_language') ?? 'mandarin';
        if (_language == 'taiwanese') {
          _aiWords = "您好！我是一直陪伴您的語音小幫手。今天心情好無？隨時點圓球對我講說話喔！";
        } else {
          _aiWords = "您好！我是您的語音陪伴小幫手。今天心情好嗎？隨時點擊圓球對我說說話吧！";
        }
      });
    } catch (e) {
      debugPrint("Error loading SharedPreferences: $e");
    }

    // 初始化 TTS
    try {
      await _flutterTts.setLanguage("zh-TW");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.42); // 偏慢，讓長輩聽得更清楚
      // 當語音播放完畢時，回到 idle 狀態
      _flutterTts.setCompletionHandler(() {
        if (mounted && _agentState == AgentState.speaking && _language == 'mandarin') {
          _updateState(AgentState.idle);
        }
      });
    } catch (e) {
      debugPrint("Error initializing TTS: $e");
    }

    // 初始化 STT
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _speechEnabled = await _speechToText.initialize(
          onStatus: (status) {
            debugPrint("STT Status: $status");
            if (status == "done" || status == "notListening") {
              if (_agentState == AgentState.listening) {
                // 自動斷句或結束時，若有收到字則送出，否則重置回 idle
                if (_userWords.trim().isNotEmpty) {
                  _processUserVoiceMessage(_userWords);
                } else {
                  _updateState(AgentState.idle);
                }
              }
            }
          },
          onError: (errorNotification) {
            debugPrint("STT Error: $errorNotification");
            if (mounted) {
              _updateState(AgentState.idle);
            }
          },
        );

        if (_speechEnabled) {
          final locales = await _speechToText.locales();
          for (var loc in locales) {
            final idLower = loc.localeId.toLowerCase();
            if (idLower == 'zh-tw' || idLower == 'zh_tw') {
              _mandarinLocaleId = loc.localeId;
            } else if (idLower.contains('nan') || idLower.contains('min') || idLower.contains('tw')) {
              if (idLower.contains('nan') || idLower.contains('min')) {
                _taiwaneseLocaleId = loc.localeId;
              }
            }
          }
          _mandarinLocaleId ??= 'zh_TW';
          _taiwaneseLocaleId ??= 'zh_TW'; // Fallback
          debugPrint("STT Locales: Mandarin=$_mandarinLocaleId, Taiwanese=$_taiwaneseLocaleId");
        }
      }
    } catch (e) {
      debugPrint("Error initializing STT: $e");
    }
  }

  // 綁定 Socket.IO 推播留言
  void _bindSocketCallbacks() {
    Signaling().onNewPondLeaf = (String text, String type) {
      if (!mounted) return;
      
      // 清理 Markdown 圖片與影片等技術標籤
      String cleanText = text
          .replaceAll(RegExp(r'!\[.*?\]\((.*?)\)'), '')
          .replaceAll(RegExp(r'\[VIDEO_ID:([^\]]+)\]'), '')
          .trim();
      
      if (cleanText.isEmpty) {
        cleanText = "收到一則新訊息";
      }

      addNotification("子女傳來留言：$cleanText");
    };
  }

  // 外部通知接入口 (由 elder_home_screen.dart 呼叫)
  void addNotification(String message) {
    if (!mounted) return;
    _flutterTts.stop();
    _audioPlayer.stop();
    setState(() {
      _userWords = "";
      _aiWords = message;
    });
    _updateState(AgentState.speaking);
    _speak(message);
  }

  // 更新 Agent 狀態並觸發 Overlay 變化通知
  void _updateState(AgentState newState) {
    if (!mounted) return;
    setState(() {
      _agentState = newState;
    });

    // 當非 idle 狀態時，通知首頁隱藏底部導航列，避免重疊
    final isOverlayActive = newState != AgentState.idle;
    widget.onOverlayStateChanged?.call(isOverlayActive);

    // 處理特殊狀態動畫
    if (newState == AgentState.thinking) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }
  }

  // 播放 TTS 語音
  Future<void> _speak(String text) async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
    
    // 清除語音中可能含有的特殊影片代碼，避免唸出來
    String cleanText = text.replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '').trim();
    
    // 優先調用後端高音質語音合成 (Edge / Yating)
    try {
      final response = await ApiService.synthesizeTts(
        text: cleanText, 
        emotion: 'neutral'
      );
      final isSuccess = response['success'] == true || response['status'] == 'success';
      if (!isSuccess) throw Exception('TTS 合成失敗');

      final audioBase64 = (response['audio'] ?? response['audio_base64'] ?? '').toString();
      if (audioBase64.isEmpty) throw Exception('音訊數據為空');

      String payload = audioBase64.trim();
      if (payload.startsWith('data:')) {
        final commaIndex = payload.indexOf(',');
        if (commaIndex >= 0 && commaIndex < payload.length - 1) {
          payload = payload.substring(commaIndex + 1);
        }
      }
      payload = payload.replaceAll(RegExp(r'\s+'), '');
      final missingPadding = payload.length % 4;
      if (missingPadding > 0) payload += '=' * (4 - missingPadding);
      final audioBytes = base64Decode(payload);

      await _audioPlayer.play(BytesSource(audioBytes));
    } catch (e) {
      debugPrint('Remote TTS failed: $e. Falling back to local TTS.');
      // 若遠端失敗，僅國語有辦法走本機 TTS 保底
      if (_language == 'mandarin') {
        await _flutterTts.speak(cleanText);
      } else {
        // 台語則嘗試以國語本機發音做最壞保底，或靜音
        await _flutterTts.speak(cleanText);
      }
    }
  }

  // 啟動錄音
  Future<void> _startListening() async {
    if (!_speechEnabled) {
      await _initServices();
    }

    await _flutterTts.stop();
    await _audioPlayer.stop();
    _speechToText.stop();

    setState(() {
      _userWords = "";
    });
    _updateState(AgentState.listening);

    final String targetLocale = _language == 'taiwanese' 
        ? (_taiwaneseLocaleId ?? 'zh_TW') 
        : (_mandarinLocaleId ?? 'zh_TW');

    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _userWords = result.recognizedWords;
        });
        if (result.finalResult && _userWords.trim().isNotEmpty) {
          _processUserVoiceMessage(_userWords);
        }
      },
      localeId: targetLocale,
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3), // 3 秒沒說話自動斷句
    );
  }

  // 停止錄音並處理
  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (_userWords.trim().isNotEmpty) {
      _processUserVoiceMessage(_userWords);
    } else {
      _updateState(AgentState.idle);
    }
  }

  // 送出訊息至 AI 後端
  Future<void> _processUserVoiceMessage(String text) async {
    _updateState(AgentState.thinking);
    await _flutterTts.stop();
    await _audioPlayer.stop();

    try {
      final result = await ApiService.aiChat(_userId, text);
      if (!mounted) return;

      if (result.containsKey('reply')) {
        final reply = result['reply'].toString();
        setState(() {
          _aiWords = reply;
        });
        _updateState(AgentState.speaking);
        _speak(reply);
      } else {
        throw Exception("Invalid response format");
      }
    } catch (e) {
      debugPrint("AI Chat Error: $e");
      if (mounted) {
        setState(() {
          _aiWords = "抱歉，我現在連不上伺服器。您可以等等再試一次嗎？";
        });
        _updateState(AgentState.speaking);
        _speak(_aiWords);
      }
    }
  }

  // 處理主要圓球的點擊事件
  void _handleOrbTap() {
    if (_agentState == AgentState.idle || _agentState == AgentState.speaking) {
      _startListening();
    } else if (_agentState == AgentState.listening) {
      _stopListening();
    }
  }

  // 依據不同狀態決定圓球的主色調
  Color _getOrbColor() {
    switch (_agentState) {
      case AgentState.listening:
        return const Color(0xFFE05252); // 紅色 (錄音中)
      case AgentState.thinking:
        return const Color(0xFF8E66F4); // 紫色 (思考中)
      case AgentState.speaking:
        return const Color(0xFF3B82F6); // 藍色 (說話中)
      case AgentState.idle:
        return const Color(0xFF59B294); // 莫蘭迪綠 (閒置狀態)
    }
  }

  // 依據狀態顯示圓球中央圖示
  IconData _getOrbIcon() {
    switch (_agentState) {
      case AgentState.listening:
        return Icons.keyboard_voice_rounded;
      case AgentState.thinking:
        return Icons.psychology_rounded;
      case AgentState.speaking:
        return Icons.volume_up_rounded;
      case AgentState.idle:
        return Icons.mic_rounded;
    }
  }

  // 狀態輔助說明文字
  String _getStatusText() {
    switch (_agentState) {
      case AgentState.listening:
        return "聆聽中...";
      case AgentState.thinking:
        return "動腦筋思考中...";
      case AgentState.speaking:
        return "說話中...";
      case AgentState.idle:
        return "點擊圓球開始聊聊";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEAF5F2), Color(0xFFF1EEF6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 頂部精緻控制列與溫馨標題
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "語音陪伴小幫手",
                        style: GoogleFonts.notoSansTc(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "隨時找我聊天，我一直都在",
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          color: const Color(0xFF7F8C8D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () async {
                      final nextLang = _language == 'mandarin' ? 'taiwanese' : 'mandarin';
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('voice_language', nextLang);
                      
                      setState(() {
                        _language = nextLang;
                        if (nextLang == 'taiwanese') {
                          _aiWords = "您好！我是一直陪伴您的語音小幫手。今天心情好無？隨時點圓球對我講說話喔！";
                        } else {
                          _aiWords = "您好！我是您的語音陪伴小幫手。今天心情好嗎？隨時點擊圓球對我說說話吧！";
                        }
                      });
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(nextLang == 'taiwanese' ? '已切換為：台語陪伴模式 🎤' : '已切換為：國語陪伴模式 🎤'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _language == 'taiwanese' ? const Color(0xFF59B294) : const Color(0xFF8E66F4),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.translate_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _language == 'taiwanese' ? '台語' : '國語',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 狀態說明標籤 (加大字體)
                  Text(
                    _getStatusText(),
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _getOrbColor(),
                    ),
                  ).animate(key: ValueKey(_agentState))
                   .fadeIn(duration: 300.ms)
                   .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),

                  const SizedBox(height: 30),

                  // 核心呼吸/波動大圓球
                  GestureDetector(
                    onTap: _handleOrbTap,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 狀態一：錄音中或播放中 -> 產生擴散動態聲波光圈 (用 flutter_animate 達到無卡頓動畫)
                          if (_agentState == AgentState.listening || _agentState == AgentState.speaking)
                            ...List.generate(2, (index) {
                              final delay = index * 750;
                              return Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getOrbColor().withValues(alpha: 0.15),
                                ),
                              ).animate(onPlay: (controller) => controller.repeat())
                               .scale(
                                 begin: const Offset(1.0, 1.0),
                                 end: const Offset(1.6, 1.6),
                                 duration: 1500.ms,
                                 delay: delay.ms,
                                 curve: Curves.easeOutCirc,
                               )
                               .fadeOut(duration: 1500.ms, delay: delay.ms);
                            }),

                          // 狀態二：思考中 -> 特殊旋轉外光圈
                          if (_agentState == AgentState.thinking)
                            RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 8,
                                  ),
                                  gradient: const SweepGradient(
                                    colors: [
                                      Color(0xFF8E66F4),
                                      Color(0xFFE05252),
                                      Color(0xFF59B294),
                                      Color(0xFF3B82F6),
                                      Color(0xFF8E66F4),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          // 實體發光大按鈕
                          Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getOrbColor(),
                              boxShadow: [
                                BoxShadow(
                                  color: _getOrbColor().withValues(alpha: 0.35),
                                  blurRadius: 25,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 10),
                                ),
                                const BoxShadow(
                                  color: Colors.white24,
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                  offset: Offset(0, -6),
                                )
                              ],
                            ),
                            child: Icon(
                              _getOrbIcon(),
                              color: Colors.white,
                              size: 80,
                            ),
                          ).animate(
                            onPlay: (controller) {
                              if (_agentState == AgentState.idle) {
                                controller.repeat(reverse: true);
                              }
                            }
                          )
                          // 閒置時的溫和呼吸動畫
                          .scale(
                            begin: const Offset(1.0, 1.0),
                            end: const Offset(1.06, 1.06),
                            duration: 1400.ms,
                            curve: Curves.easeInOutSine,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // 輔助指示提示
                  Text(
                    _agentState == AgentState.listening ? "說完話後，請稍等一下或再次點擊按鈕" : "點擊上方的圓球開始說話",
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      color: const Color(0xFF95A5A6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // 對話內容區：顯示極致放大的雙向氣泡
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 長輩說的內容
                  if (_userWords.isNotEmpty || _agentState == AgentState.listening)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F4EE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "您說：",
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF16A085),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _userWords.isEmpty ? "正在辨識語音..." : _userWords,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2C3E50),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // AI 的回覆內容
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F4FD),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "小幫手：",
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2980B9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _agentState == AgentState.thinking ? "正在動腦筋想一想..." : _aiWords,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 26, // 特大字體讓長輩看得舒服
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2C3E50),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
