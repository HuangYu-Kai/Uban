import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';

import 'controllers/zen_pond_controller.dart';
import 'widgets/pond_background.dart';
import 'widgets/interactive_ripples.dart';
import 'widgets/pond_decorations.dart';
import 'widgets/koi_fish_notification.dart';
import 'widgets/lotus_leaf_card.dart';
import 'widgets/falling_leaf_message.dart';
import 'widgets/leaf_message_card.dart';
import '../../widgets/youtube_bubble_player.dart';
import '../../services/api_service.dart';
import '../../services/signaling.dart';

// 【主螢幕元件】禪意池塘 - 整合落葉對話、原生 STT 語音 Overlay 與極致莫蘭迪背景

class ZenPondScreen extends StatefulWidget {
  final Function(bool isVisible)? onOverlayStateChanged;
  const ZenPondScreen({super.key, this.onOverlayStateChanged});

  @override
  State<ZenPondScreen> createState() => ZenPondScreenState();
}

class ZenPondScreenState extends State<ZenPondScreen> {
  final ZenPondController _controller = ZenPondController();

  @override
  void initState() {
    super.initState();
    // 進入時非同步載入本地持久化歷史落葉，若無則啟動首次迎賓排程
    _controller.loadLeaves();
    _controller.loadHistory();
    _controller.addListener(_onControllerChanged);

    // 掛載 Socket.IO 記憶落葉接收回調
    // 當後端排程或 API 推送 'new-pond-leaf' 事件時，自動加入黃色記憶葉並 TTS 播報
    Signaling().onNewPondLeaf = (String text, String type) {
      if (!mounted) return;
      
      // 解析 Markdown 圖片: ![alt](url)
      String? imageUrl;
      final imgRegExp = RegExp(r'!\[.*?\]\((.*?)\)');
      final imgMatch = imgRegExp.firstMatch(text);
      if (imgMatch != null) {
        imageUrl = imgMatch.group(1);
      }
      
      // 解析影片 ID: [VIDEO_ID:xxxx]
      String? videoId;
      final videoRegExp = RegExp(r'\[VIDEO_ID:([^\]]+)\]');
      final videoMatch = videoRegExp.firstMatch(text);
      if (videoMatch != null) {
        videoId = videoMatch.group(1);
      }
      
      // 清理文本中的技術標籤和 Markdown 語法，只留乾淨對話
      String cleanText = text
          .replaceAll(imgRegExp, '')
          .replaceAll(videoRegExp, '')
          .trim();
          
      if (cleanText.isEmpty) {
        cleanText = videoId != null ? '這是為您推薦的影片' : (imageUrl != null ? '為您分享了一張照片' : text);
      }

      _controller.addLeaf(
        text: cleanText,
        colorType: LeafColorType.yellow, // 黃色 = 長期記憶葉
        imageUrl: imageUrl,
        videoId: videoId,
        playTts: true,
      );

      // 將推播的新記憶落葉加入時光日記
      _controller.addHistory(
        sender: 'ai',
        text: cleanText,
        imageUrl: imageUrl,
        videoId: videoId,
      );
    };
  }

  void _onControllerChanged() {
    widget.onOverlayStateChanged?.call(_controller.isAnyOverlayVisible);
  }

  void addNotification(String message) {
    _controller.showNotification(message);
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    // 離開頁面時清除落葉回調，避免記憶體洩漏
    Signaling().onNewPondLeaf = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: const _ZenPondContent(),
    );
  }
}

class _ZenPondContent extends StatefulWidget {
  const _ZenPondContent();

  @override
  State<_ZenPondContent> createState() => _ZenPondContentState();
}

class _ZenPondContentState extends State<_ZenPondContent>
    with SingleTickerProviderStateMixin {
  // --- STT 語音錄音相關 ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isRecording = false;
  String _recognizedWords = '點擊麥克風開始說話...';


  // --- AI 思考狀態 ---
  bool _isAiThinking = false;
  String? _currentLocaleId;
  double _soundLevel = 0.0;

  // --- 麥克風呼吸擴散動畫 ---
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // --- 時光日記 (歷史對話) 新增變數 ---
  bool _isDiaryDialogOpen = false;
  final ScrollController _historyScrollController = ScrollController();
  final AudioPlayer _historyAudioPlayer = AudioPlayer();

  // --- 日記內嵌 STT 錄音狀態 ---
  bool _isDialogRecording = false;
  String _dialogRecognizedWords = '聆聽中，請說話...';

  @override
  void initState() {
    super.initState();
    _initSpeech();

    // 初始化麥克風呼吸動畫 (極致平滑的擴散光圈)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // 監聽歷史語音播放狀態，結束時重置播放按鈕狀態（透過 controller 通知 Dialog 刷新）
    _historyAudioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        final ctrl = Provider.of<ZenPondController>(context, listen: false);
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          ctrl.setTtsState(playingId: null, loading: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _historyAudioPlayer.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  // 原生語音錄音初始化
  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _speechEnabled = await _speechToText.initialize(
          debugLogging: true,
          onStatus: (sttStatus) {
            debugPrint('ZenPond STT status: $sttStatus');
            if ((sttStatus == 'done' || sttStatus == 'notListening') && _isRecording) {
              _stopListening();
            }
          },
          onError: (err) {
            debugPrint('ZenPond STT error: ${err.errorMsg}');
            if (mounted) {
              setState(() {
                _isRecording = false;
                _soundLevel = 0.0;
                _pulseController.stop();
                _pulseController.reset();
                
                // 客製化貼心引導文字
                if (err.errorMsg == 'error_no_match') {
                  _recognizedWords = '沒聽清楚，請點擊麥克風大聲一點再試一次 😊';
                } else if (err.errorMsg == 'error_speech_timeout') {
                  _recognizedWords = '好像沒有聽到您的聲音，請點擊麥克風再說一次喔 😊';
                } else if (err.errorMsg == 'error_network') {
                  _recognizedWords = '網路連線有點忙碌，請再試一次 😊';
                } else if (err.errorMsg == 'error_permission') {
                  _recognizedWords = '麥克風權限尚未開啟，請在系統設定中允許喔 😊';
                } else {
                  _recognizedWords = '語音識別遇到一點小狀況，請重試或用鍵盤打字喔 😊';
                }
              });
            }
          },
        );
        if (_speechEnabled) {
          try {
            final locales = await _speechToText.locales();
            for (var locale in locales) {
              if (locale.localeId == 'zh_TW' || locale.localeId == 'zh-TW') {
                _currentLocaleId = locale.localeId;
                break;
              }
            }
            if (_currentLocaleId == null && locales.isNotEmpty) {
              for (var locale in locales) {
                if (locale.localeId.startsWith('zh')) {
                  _currentLocaleId = locale.localeId;
                  break;
                }
              }
            }
            debugPrint('ZenPond Selected STT Locale: $_currentLocaleId');
          } catch (e) {
            debugPrint('Error getting locales: $e');
          }
        }
      } else {
        _speechEnabled = false;
      }
    } catch (e) {
      debugPrint('ZenPond STT Init failed: $e');
      _speechEnabled = false;
    }

    if (!_speechEnabled && mounted) {
      setState(() {
        _recognizedWords = '本機不支援語音識別，請點左下鍵盤聊天喔 😊';
      });
    }
  }

  // 開始錄音監聽
  void _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
    }
    if (_speechEnabled && !_isRecording) {
      setState(() {
        _recognizedWords = '聆聽中，請說話...';
        _isRecording = true;
        _soundLevel = 0.0;
      });
      _pulseController.repeat();
      try {
        await _speechToText.listen(
          onResult: (result) {
            if (mounted) {
              setState(() {
                _recognizedWords = result.recognizedWords.isNotEmpty 
                    ? result.recognizedWords 
                    : '聆聽中，請說話...';
              });
            }
          },
          listenFor: const Duration(seconds: 25),
          pauseFor: const Duration(seconds: 4),
          localeId: _currentLocaleId,
          partialResults: true,
          onSoundLevelChange: (level) {
            if (mounted) {
              setState(() {
                _soundLevel = level;
              });
            }
          },
        );
      } catch (e) {
        debugPrint('STT listen failed: $e');
        if (mounted) {
          setState(() {
            _isRecording = false;
            _soundLevel = 0.0;
            _pulseController.stop();
            _pulseController.reset();
            _recognizedWords = '錄音啟動失敗，請重試 😊';
          });
        }
      }
    } else if (!_speechEnabled) {
      // 語音不可用，自動切換至打字輸入，防禦模擬器不支援語音的痛點
      final controller = Provider.of<ZenPondController>(context, listen: false);
      _showTextInputDialog(controller);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('您的裝置不支援語音識別，已自動為您開啟文字輸入模式 😊'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // 停止錄製並發送 AI 對話
  void _stopListening() async {
    if (_isRecording) {
      // 1. 同步將錄音狀態設為 false，並停止呼吸波紋動畫，杜絕非同步重入的 Race Condition
      setState(() {
        _isRecording = false;
        _soundLevel = 0.0;
        _pulseController.stop();
        _pulseController.reset();
      });

      // 2. 隨後非同步地停止錄音
      await _speechToText.stop();

      final text = _recognizedWords.trim();
      if (text.isNotEmpty && text != '聆聽中，請說話...' && text != '點擊麥克風開始說話...' && text != '本機不支援語音識別，請點左下鍵盤聊天喔 😊') {
        _showHistoryDialog(); // 立即打開日記，展示對話流程與思考狀態
        _sendToAiChat(text);
      } else {
        setState(() {
          _recognizedWords = '沒聽清楚，請點擊麥克風再試一次 😊';
        });
      }
    }
  }

  // 發送訊息並觸發翠綠落葉及 edge-tts 播報
  Future<void> _sendToAiChat(String text) async {
    setState(() {
      _recognizedWords = text;
      _isAiThinking = true;
    });

    final controller = Provider.of<ZenPondController>(context, listen: false);
    controller.addHistory(sender: 'user', text: text);

    try {
      // 調用 API 後端 aiChat (User ID 固定為 1)
      final result = await ApiService.aiChat(1, text);

      if (mounted) {
        // 先判斷後端是否返回錯誤狀態
        if (result['status'] == 'error' || result['status'] == 'fail') {
          throw Exception(result['message'] ?? '服務器連線忙碌');
        }

        String? reply;
        if (result.containsKey('reply')) {
          reply = result['reply'];
        } else if (result.containsKey('data') && result['data'] is Map) {
          final data = result['data'] as Map<String, dynamic>;
          if (data.containsKey('reply')) {
            reply = data['reply'];
          }
        }

        if (reply != null) {
          // 解析 Markdown 圖片: ![alt](url)
          String? imageUrl;
          final imgRegExp = RegExp(r'!\[.*?\]\((.*?)\)');
          final imgMatch = imgRegExp.firstMatch(reply);
          if (imgMatch != null) {
            imageUrl = imgMatch.group(1);
          }
          
          // 解析影片 ID: [VIDEO_ID:xxxx]
          String? videoId;
          final videoRegExp = RegExp(r'\[VIDEO_ID:([^\]]+)\]');
          final videoMatch = videoRegExp.firstMatch(reply);
          if (videoMatch != null) {
            videoId = videoMatch.group(1);
          }
          
          // 清理文本中的技術標籤和 Markdown 語法，只留乾淨對話
          String cleanText = reply
              .replaceAll(imgRegExp, '')
              .replaceAll(videoRegExp, '')
              .trim();
              
          if (cleanText.isEmpty) {
            cleanText = videoId != null ? '這是為您推薦的影片' : (imageUrl != null ? '為您分享了一張照片' : reply);
          }

          // 1. 水面降落一片全新代表 AI 回覆的「碧綠落葉」，但不在水面彈出大木牌
          controller.addLeaf(
            text: cleanText,
            colorType: LeafColorType.green,
            imageUrl: imageUrl,
            videoId: videoId,
            playTts: false,
            isCardVisible: false,
          );

          // 2. 將 AI 回覆存入時光日記
          controller.addHistory(
            sender: 'ai',
            text: cleanText,
            imageUrl: imageUrl,
            videoId: videoId,
          );

          // 3. 成功後，自動平滑收起對話 Overlay
          controller.closeAiOverlay();

          // 4. 將思考狀態設為 false，使 ListView 提早重繪
          if (mounted) {
            setState(() {
              _isAiThinking = false;
            });
          }

          // 5. 自動彈出時光日記介面（若尚未打開）
          if (!_isDiaryDialogOpen) _showHistoryDialog();

          // 6. 自動朗讀最新的 AI 訊息
          final lastTimestamp = controller.history.isNotEmpty
              ? controller.history.last['timestamp']
              : DateTime.now().millisecondsSinceEpoch;
          final bubbleId = "${lastTimestamp}_ai";
          _playHistoryTts(bubbleId, cleanText, controller);
        } else {
          throw Exception('回覆欄位格式不正確');
        }
      }
    } catch (e) {
      debugPrint('ZenPond AI conversation error: $e');
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        setState(() {
          _recognizedWords = '對話出錯：$errorMsg 😊';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('對話失敗：$errorMsg'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiThinking = false;
        });
      }
    }
  }

  // 打字輸入對話框
  void _showTextInputDialog(ZenPondController controller) {
    final TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '與小幫手文字聊天',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: const Color(0xFF3E2723),
          ),
        ),
        content: TextField(
          controller: textController,
          style: GoogleFonts.notoSansTc(fontSize: 24),
          decoration: const InputDecoration(
            hintText: '請輸入您想問的事情...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              Navigator.pop(context);
              if (text.isNotEmpty) {
                _showHistoryDialog(); // 立即打開日記，展示對話流程
                _sendToAiChat(text);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8C6D58),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '送出',
              style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ZenPondController>();
    
    // 當對話 Overlay 關閉時，自動重置語音識別文字與思考狀態
    if (!controller.isAiOverlayVisible) {
      _recognizedWords = '點擊麥克風開始說話...';
      _soundLevel = 0.0;
      _isAiThinking = false;
    }
    
    // 莫蘭迪淺藍綠底色，SOS 模式時轉紅
    final Color bgColor = controller.isSOSMode 
        ? const Color(0xFFFFEAEA) 
        : const Color(0xFFE6F5EC); 

    return Scaffold(
      backgroundColor: bgColor,
      body: InteractiveRipples(
        onTap: controller.handleTap,
        isSOSMode: controller.isSOSMode,
        isEnabled: !controller.isAnyOverlayVisible,
        child: Stack(
          children: [
            // 第一層：緩慢水波背景
            const PondBackground(),
            
            // 第二層：邊緣石頭裝飾
            const PondDecorations(),
            
            // 提示文字 (無 SOS 時展示於正中央，增加大字號引導)
            if (!controller.isSOSMode && controller.leaves.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '點擊水面與我說話',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 26,
                        color: const Color(0xFF64748B).withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '(連續點擊 5 次可觸發求救)',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        color: const Color(0xFF94A3B8).withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              
            // SOS 警報提示
            if (controller.isSOSMode)
              Center(
                child: Text(
                  'SOS 求救已觸發！',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // 第三層：錦鯉通知 (Phase 2 原生多隻錦鯉)
            for (final item in controller.notifications)
              if (!item.isLotusVisible)
                KoiFishNotification(
                  key: ValueKey(item.id),
                  koiStyle: item.koiStyle,
                  onTap: () => controller.tapKoi(item),
                ),

            // 第三層半：三色對話落葉 (新增的 Phase 3 浮游落葉圖層)
            for (final leaf in controller.leaves)
              if (!leaf.isCardVisible)
                FallingLeafMessage(
                  key: ValueKey(leaf.id),
                  item: leaf,
                  onTap: () => controller.tapLeaf(leaf),
                ),

            // 第四層：祈福水燈卡片 (錦鯉卡)
            for (final item in controller.notifications)
              if (item.isLotusVisible)
                LotusLeafCard(
                  key: ValueKey(item.id),
                  message: item.message,
                  onDismiss: () => controller.dismissLotus(item),
                ),

            // 第五層：展開後的落葉大木牌卡片
            for (final leaf in controller.leaves)
              if (leaf.isCardVisible)
                LeafMessageCard(
                  key: ValueKey('card_${leaf.id}'),
                  id: leaf.id,
                  message: leaf.text,
                  imageUrl: leaf.imageUrl,
                  videoId: leaf.videoId,
                  onSwipeLeft: () {
                    // 左滑：開始聊天 -> 將話題送給 AI 並開啟時光日記
                    final topicText = leaf.text;
                    controller.dismissLeaf(leaf); // 消耗並移去落葉
                    _showHistoryDialog(); // 立即展開對話日記，向長輩呈現連貫感
                    _sendToAiChat('我想聊聊這個話題：$topicText');
                  },
                  onSwipeRight: () {
                    // 右滑：捨棄話題 -> 移去落葉並給予溫馨 SnackBar 提示
                    controller.dismissLeaf(leaf);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '已為您捨棄話題 😊',
                          style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),

            // 時光日記浮動書籍 (右上角，精緻手繪感 3D 閉合日記本，無文字/無按鈕感)
            if (!controller.isAiOverlayVisible)
              Positioned(
                right: 20,
                top: 100,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque, // 吸收事件，防止穿透到水面觸發 AI Overlay
                  onTap: () => _showHistoryDialog(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox(
                      width: 86,
                      height: 118,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 1. 書籤絲帶 (Bookmark Ribbon) - 從書頁底部垂下
                          Positioned(
                            left: 42,
                            bottom: 0,
                            width: 10,
                            height: 22,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFC62828), // 典雅深紅絲帶
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(2),
                                  bottomRight: Radius.circular(2),
                                  topLeft: Radius.circular(1),
                                  topRight: Radius.circular(1),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 2,
                                    offset: Offset(1, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 2. 整本書的主體 (封底與書頁層)
                          Positioned(
                            left: 0,
                            top: 0,
                            width: 80,
                            height: 102,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF3E2723), // 封底深褐皮革
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  bottomLeft: Radius.circular(6),
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 10,
                                    offset: const Offset(3, 5),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // 3. 內頁層 (Pages) - 暖白/奶油色，右下上收縮，露出紙張質感與層次
                                  Positioned(
                                    left: 10,
                                    top: 4,
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFFFDF0), // 溫暖紙張色
                                        borderRadius: BorderRadius.only(
                                          topRight: Radius.circular(5),
                                          bottomRight: Radius.circular(5),
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          // 畫出右側紙張層疊紋理 (Subtle Page Lines)
                                          Positioned(
                                            right: 2,
                                            top: 0,
                                            bottom: 0,
                                            width: 1,
                                            child: Container(color: const Color(0xFFE0D8C3)),
                                          ),
                                          Positioned(
                                            right: 4,
                                            top: 0,
                                            bottom: 0,
                                            width: 1,
                                            child: Container(color: const Color(0xFFE0D8C3)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // 4. 封面層 (Front Cover) - 比書頁稍寬、但露出右側書頁以呈 3D 閉合效果
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    right: 8, // 露出 8px 的書頁
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF5D4037), // 封面亮褐皮革色
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(6),
                                          bottomLeft: Radius.circular(6),
                                          topRight: Radius.circular(3),
                                          bottomRight: Radius.circular(3),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.2),
                                            blurRadius: 3,
                                            offset: const Offset(2, 0),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          // 書脊裝飾線 (Spine Ribs) - 經典皮革刻線與金箔質感
                                          Positioned(
                                            left: 0,
                                            top: 0,
                                            bottom: 0,
                                            width: 12,
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF4E342E), // 更深書脊皮色
                                                borderRadius: BorderRadius.only(
                                                  topLeft: Radius.circular(6),
                                                  bottomLeft: Radius.circular(6),
                                                ),
                                              ),
                                              child: Stack(
                                                children: [
                                                  // 書脊橫向金線
                                                  Positioned(left: 2, right: 2, top: 15, height: 1.5, child: Container(color: const Color(0xFFD4AF37).withOpacity(0.8))),
                                                  Positioned(left: 2, right: 2, top: 48, height: 1.5, child: Container(color: const Color(0xFFD4AF37).withOpacity(0.8))),
                                                  Positioned(left: 2, right: 2, top: 80, height: 1.5, child: Container(color: const Color(0xFFD4AF37).withOpacity(0.8))),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // 書脊金色封邊垂直線
                                          Positioned(
                                            left: 12,
                                            top: 0,
                                            bottom: 0,
                                            width: 1.2,
                                            child: Container(color: const Color(0xFFD4AF37).withOpacity(0.7)),
                                          ),

                                          // 封面中央燙金「禪意雙葉」徽章 (取代任何文字)
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 12),
                                              child: Icon(
                                                Icons.spa_rounded, // 溫馨禪意草葉
                                                color: const Color(0xFFD4AF37).withOpacity(0.9),
                                                size: 26,
                                              ),
                                            ),
                                          ),

                                          // 5. 金屬皮帶鎖扣 (Clasp Strap) - 橫跨封面至書頁，呈現鎖扣感
                                          Positioned(
                                            right: -6,
                                            top: 42,
                                            width: 22,
                                            height: 18,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF3E2723), // 鎖扣皮帶
                                                borderRadius: const BorderRadius.only(
                                                  topRight: Radius.circular(4),
                                                  bottomRight: Radius.circular(4),
                                                  topLeft: Radius.circular(2),
                                                  bottomLeft: Radius.circular(2),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.15),
                                                    blurRadius: 2,
                                                    offset: const Offset(1, 1),
                                                  ),
                                                ],
                                              ),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  margin: const EdgeInsets.only(left: 4),
                                                  width: 8,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFD4AF37), // 亮金扣環
                                                    borderRadius: BorderRadius.circular(1.5),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            Positioned(
              left: 20,
              top: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [6, 12, 17, 22].map((hour) {
                        final labels = {6: '晨', 12: '晝', 17: '昏', 22: '夜'};
                        final isSelected = controller.mockHour == hour;
                        return InkWell(
                          onTap: () => controller.setMockTime(hour),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.teal.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              labels[hour]!, 
                              style: TextStyle(
                                color: isSelected ? Colors.teal : Colors.grey[600],
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              )
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      controller.showNotification('爺爺！今天天氣很好，下午記得去公園散步走走喔！\n愛您的女兒 秀珠 ❤️');
                    },
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('模擬家人傳訊息'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.8),
                      foregroundColor: Colors.teal,
                      elevation: 4,
                    ),
                  ),
                ],
              ),
            ),

            // 第七層：極致優雅的【語音聆聽毛玻璃對話 Overlay】(Phase 3 核心互動)
            if (controller.isAiOverlayVisible)
              Positioned.fill(
                child: GestureDetector(
                  // 點擊 Overlay 背景空白處即可快速關閉對話
                  onTap: () {
                    if (!_isAiThinking && !_isRecording) {
                      controller.closeAiOverlay();
                    }
                  },
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: const Color(0xFFFCFBF7).withOpacity(0.75), // 暖心象牙白宣紙毛玻璃
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 頂部小幫手標題
                              Padding(
                                padding: const EdgeInsets.only(top: 40),
                                child: Column(
                                  children: [
                                    Text(
                                      '貼心小幫手',
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF3E2723),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '正在傾聽您的心聲...',
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 18,
                                        color: const Color(0xFF8C6D58),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 中間：大字體語音識別內容 (同時呈現識別文字與 AI 思考狀態，避免文字消失)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _recognizedWords,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 30,
                                        height: 1.5,
                                        fontWeight: FontWeight.bold,
                                        color: _isRecording
                                            ? const Color(0xFFD84315) // 錄音中深橘色醒目提示
                                            : const Color(0xFF3E2723),
                                      ),
                                    ),
                                    if (_isAiThinking) ...[
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Color(0xFF8C6D58),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            '正在認真思考中...',
                                            style: GoogleFonts.notoSansTc(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF8C6D58),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // 底部：超大麥克風按鈕與輔助鍵盤
                              Padding(
                                padding: const EdgeInsets.only(bottom: 50),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // 1. 打字鍵盤按鈕 (備用文字輸入通道)
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Colors.white,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.keyboard,
                                          color: Color(0xFF8C6D58),
                                          size: 34,
                                        ),
                                        onPressed: _isAiThinking
                                            ? null
                                            : () => _showTextInputDialog(controller),
                                      ),
                                    ),

                                    // 2. 超大麥克風按鈕 (長按/單擊對話錄音)
                                    GestureDetector(
                                      onTap: () {
                                        if (_isAiThinking) return;
                                        if (_isRecording) {
                                          _stopListening();
                                        } else {
                                          _startListening();
                                        }
                                      },
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // 擴散脈衝呼吸波紋
                                          if (_isRecording)
                                            AnimatedBuilder(
                                              animation: _pulseAnimation,
                                              builder: (context, child) {
                                                final levelScale = (_soundLevel > 0) ? (_soundLevel / 6.0) : 0.0;
                                                final scale = _pulseAnimation.value + levelScale.clamp(0.0, 0.8);
                                                return Transform.scale(
                                                  scale: scale,
                                                  child: Container(
                                                    width: 120,
                                                    height: 120,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: const Color(0xFFFFB74D).withOpacity(
                                                        (1.0 - _pulseController.value).clamp(0.0, 1.0),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          // 麥克風實體圓圈
                                          Container(
                                            width: 110,
                                            height: 110,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _isRecording
                                                  ? const Color(0xFFD84315)
                                                  : const Color(0xFF8C6D58),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.15),
                                                  blurRadius: 15,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              _isRecording ? Icons.mic : Icons.mic_none,
                                              color: Colors.white,
                                              size: 55,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // 3. 關閉按鈕
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Colors.white,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.redAccent,
                                          size: 34,
                                        ),
                                        onPressed: _isAiThinking
                                            ? null
                                            : () => controller.closeAiOverlay(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- 時光日記 (歷史紀錄) 彈出 Dialog 相關 ---
  void _showHistoryDialog() {
    if (_isDiaryDialogOpen) {
      // 已經開啟了，滾動到底部以顯示最新對話
      _scrollToBottom();
      return;
    }
    _isDiaryDialogOpen = true;

    final controllerInstance = Provider.of<ZenPondController>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return ChangeNotifierProvider.value(
          value: controllerInstance,
          child: Consumer<ZenPondController>(
            builder: (context, controller, child) {
              return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFBF7), // 宣紙白暖色背景
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 頂部 Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.history_edu_rounded,
                                color: Color(0xFF8C6D58),
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '時光日記',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF3E2723),
                                ),
                              ),
                            ],
                          ),
                          // 清空歷史按鈕
                          TextButton.icon(
                            onPressed: () {
                              _showClearConfirmDialog(controller);
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                            label: Text(
                              '清空日記',
                              style: GoogleFonts.notoSansTc(color: Colors.redAccent, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFEFEBE9)),

                    // 中間對話歷史列表
                    Expanded(
                      child: controller.history.isEmpty
                          ? Center(
                              child: Text(
                                '目前還沒有日記喔，跟小幫手聊聊天吧 😊',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 20,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                // 每次對話變更或重繪，自動滾動到底部
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (_historyScrollController.hasClients) {
                                    _historyScrollController.jumpTo(
                                      _historyScrollController.position.maxScrollExtent,
                                    );
                                  }
                                });
                                return ListView.builder(
                                  controller: _historyScrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  itemCount: controller.history.length + (_isAiThinking ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == controller.history.length) {
                                      return _buildThinkingBubble();
                                    }
                                    final item = controller.history[index];
                                    final isUser = item['sender'] == 'user';
                                    return _buildHistoryBubble(item, isUser, controller);
                                  },
                                );
                              },
                            ),
                    ),

                    const Divider(height: 1, color: Color(0xFFEFEBE9)),

                    // 底部控制列：整合鍵盤、語音、關閉，作為主要的對話介面
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 1. 打字聊天
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFF5EBE6),
                            child: IconButton(
                              icon: const Icon(Icons.keyboard, color: Color(0xFF8C6D58), size: 28),
                              onPressed: () {
                                Navigator.pop(context); // 先關日記
                                _showTextInputDialog(controller); // 打開打字對話框
                              },
                            ),
                          ),
                          // 2. 語音對話按鈕 (跟我說話) - 直接在日記內錄音，不跳轉 Overlay
                          ElevatedButton.icon(
                            onPressed: () async {
                              // 在日記 Dialog 內直接錄音
                              if (!_speechEnabled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('請先允許麥克風權限')),
                                );
                                return;
                              }
                              setState(() {
                                _isDialogRecording = true;
                                _dialogRecognizedWords = '聆聽中，請說話...';
                              });
                              controller.forceRefresh();
                              await _speechToText.listen(
                                localeId: _currentLocaleId,
                                onResult: (result) {
                                  final words = result.recognizedWords;
                                  setState(() {
                                    _dialogRecognizedWords = words.isNotEmpty ? words : '聆聽中，請說話...';
                                  });
                                  controller.forceRefresh();
                                  if (result.finalResult && words.isNotEmpty) {
                                    setState(() { _isDialogRecording = false; });
                                    controller.forceRefresh();
                                    _sendToAiChat(words);
                                  }
                                },
                                listenMode: ListenMode.confirmation,
                              );
                            },
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _isDialogRecording
                                  ? const Icon(Icons.mic, size: 28, key: ValueKey('mic_on'), color: Colors.white)
                                  : const Icon(Icons.mic_none, size: 28, key: ValueKey('mic_off')),
                            ),
                            label: Text(
                              _isDialogRecording ? _dialogRecognizedWords : '跟我說話',
                              style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isDialogRecording
                                  ? const Color(0xFFB71C1C)
                                  : const Color(0xFF8C6D58),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 2,
                            ),
                          ),
                          // 3. 關閉日記
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFEFEBE9),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF8C6D58), size: 28),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              );
            },
          ),
        );
      },
    ).then((_) {
      _isDiaryDialogOpen = false;
      _historyAudioPlayer.stop();
      final ctrl = Provider.of<ZenPondController>(context, listen: false);
      ctrl.setTtsState(playingId: null, loading: false);
      setState(() {
        _isDialogRecording = false;
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_historyScrollController.hasClients) {
        _historyScrollController.animateTo(
          _historyScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showClearConfirmDialog(ZenPondController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '確定要清空日記嗎？',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: const Color(0xFF3E2723),
          ),
        ),
        content: Text(
          '清空後將無法復原與小幫手的溫馨對話紀錄喔。',
          style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '留著日記',
              style: GoogleFonts.notoSansTc(fontSize: 18, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.clearHistory();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '確定清空',
              style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 播放歷史紀錄語音 (狀態存於 controller，讓 Dialog Consumer 能同步刷新)
  Future<void> _playHistoryTts(String id, String text, ZenPondController ctrl) async {
    if (ctrl.ttsLoading) return;

    if (ctrl.ttsPlayingId == id) {
      await _historyAudioPlayer.stop();
      ctrl.setTtsState(playingId: null, loading: false);
      return;
    }

    ctrl.setTtsState(playingId: id, loading: true);

    try {
      String speakText = text.replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '').trim();
      final response = await ApiService.synthesizeTts(text: speakText);
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

      ctrl.setTtsState(playingId: id, loading: false);
      await _historyAudioPlayer.stop();
      await _historyAudioPlayer.play(BytesSource(audioBytes));
      // 播放完成由 onPlayerStateChanged 監聽器重置
    } catch (e) {
      debugPrint('History TTS error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('語音播放失敗，請重試 😊')),
        );
      }
      ctrl.setTtsState(playingId: null, loading: false);
    }
  }

  Widget _buildHistoryBubble(Map<String, dynamic> item, bool isUser, ZenPondController ctrl) {
    final text = item['text'] ?? '';
    final imageUrl = item['imageUrl'] as String?;
    final videoId = item['videoId'] as String?;
    final timestamp = item['timestamp'] ?? 0;
    final bubbleId = "${timestamp}_${item['sender']}";

    final isPlaying = ctrl.ttsPlayingId == bubbleId;
    final isLoading = ctrl.ttsLoading && isPlaying;

    final bubbleColor = isUser ? const Color(0xFFF5EBE6) : const Color(0xFFE6F0EA);
    final textColor = const Color(0xFF3E2723);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final margin = isUser 
        ? const EdgeInsets.only(left: 60, right: 0, bottom: 16) 
        : const EdgeInsets.only(left: 0, right: 60, bottom: 16);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: margin,
        child: Column(
          crossAxisAlignment: align,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: Text(
                isUser ? '我' : '貼心小幫手',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 對話文字 - 升級為 24pt
                  Text(
                    text,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24, // 24pt 大字
                      height: 1.5,
                      color: textColor,
                    ),
                  ),
                  
                  // AI 訊息泡泡內建「讀給我聽」大按鈕
                  if (!isUser) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _playHistoryTts(bubbleId, text, ctrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPlaying ? const Color(0xFFC8E6C9) : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF8C6D58).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 音符律動動畫（取代轉圈圈）
                            if (isLoading)
                              SizedBox(
                                width: 24,
                                height: 18,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(3, (i) {
                                    return TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.3, end: 1.0),
                                      duration: Duration(milliseconds: 400 + i * 120),
                                      curve: Curves.easeInOut,
                                      builder: (_, v, __) => Container(
                                        width: 4,
                                        height: 6 + v * 10,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8C6D58),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              )
                            else if (isPlaying)
                              // 播放中：音波律動動畫
                              SizedBox(
                                width: 24,
                                height: 18,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(3, (i) {
                                    return TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.4, end: 1.0),
                                      duration: Duration(milliseconds: 350 + i * 100),
                                      curve: Curves.easeInOut,
                                      builder: (_, v, __) => AnimatedContainer(
                                        duration: Duration(milliseconds: 350 + i * 100),
                                        width: 4,
                                        height: 4 + v * 12,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4CAF50),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              )
                            else
                              const Icon(
                                Icons.volume_mute,
                                color: Color(0xFF8C6D58),
                                size: 18,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              isLoading ? '載入中...' : (isPlaying ? '正在朗讀' : '讀給我聽'),
                              style: GoogleFonts.notoSansTc(
                                fontSize: 14,
                                color: const Color(0xFF8C6D58),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '📸 分享的照片',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (videoId != null && videoId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 280,
                        height: 160,
                        child: YoutubeBubblePlayer(videoId: videoId),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 0, right: 60, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: Text(
                '貼心小幫手',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFE6F0EA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF8C6D58),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '正在認真思考中...',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      color: const Color(0xFF3E2723),
                      fontWeight: FontWeight.bold,
                    ),
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
