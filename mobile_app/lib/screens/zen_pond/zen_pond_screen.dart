import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

import 'controllers/zen_pond_controller.dart';
import 'widgets/pond_background.dart';
import 'widgets/interactive_ripples.dart';
import 'widgets/pond_decorations.dart';
import 'widgets/koi_fish_notification.dart';
import 'widgets/lotus_leaf_card.dart';
import 'widgets/falling_leaf_message.dart';
import 'widgets/leaf_message_card.dart';
import '../../services/api_service.dart';

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
    _controller.addListener(_onControllerChanged);
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
  String _recognizedWords = '請按住麥克風並說話...';

  // --- AI 思考狀態 ---
  bool _isAiThinking = false;

  // --- 麥克風呼吸擴散動畫 ---
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // 原生語音錄音初始化
  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _speechEnabled = await _speechToText.initialize(
          onStatus: (sttStatus) {
            debugPrint('ZenPond STT status: $sttStatus');
            if ((sttStatus == 'done' || sttStatus == 'notListening') && _isRecording) {
              _stopListening();
            }
          },
          onError: (err) {
            debugPrint('ZenPond STT error: $err');
            _speechEnabled = false;
          },
        );
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
          localeId: null,
        );
      } catch (e) {
        debugPrint('STT listen failed: $e');
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
      await _speechToText.stop();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _pulseController.stop();
          _pulseController.reset();
        });
      }

      final text = _recognizedWords.trim();
      if (text.isNotEmpty && text != '聆聽中，請說話...' && text != '請按住麥克風並說話...' && text != '本機不支援語音識別，請點左下鍵盤聊天喔 😊') {
        _sendToAiChat(text);
      } else {
        setState(() {
          _recognizedWords = '沒聽清楚，請再試一次 😊';
        });
      }
    }
  }

  // 發送訊息並觸發翠綠落葉及 edge-tts 播報
  Future<void> _sendToAiChat(String text) async {
    setState(() {
      _isAiThinking = true;
    });

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
          // 1. 水面降落一片全新代表 AI 回覆的「碧綠落葉」，並自動發起 edge-tts 自動念出！
          final controller = Provider.of<ZenPondController>(context, listen: false);
          controller.addLeaf(
            text: reply,
            colorType: LeafColorType.green,
            playTts: true,
          );

          // 2. 成功後，自動平滑收起對話 Overlay
          controller.closeAiOverlay();
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
                  onDismiss: () => controller.dismissLeaf(leaf),
                ),

            // 第六層：時間切換測試面板
            Positioned(
              left: 20,
              top: 50,
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

                              // 中間：大字體語音識別內容
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: _isAiThinking
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const CircularProgressIndicator(
                                            color: Color(0xFF8C6D58),
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            '正在認真思考中...',
                                            style: GoogleFonts.notoSansTc(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF8C6D58),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
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
                                      onTapDown: (_) {
                                        if (!_isAiThinking) _startListening();
                                      },
                                      onTapUp: (_) {
                                        if (!_isAiThinking) _stopListening();
                                      },
                                      onTapCancel: () {
                                        if (!_isAiThinking) _stopListening();
                                      },
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // 擴散脈衝呼吸波紋
                                          if (_isRecording)
                                            AnimatedBuilder(
                                              animation: _pulseAnimation,
                                              builder: (context, child) {
                                                return Transform.scale(
                                                  scale: _pulseAnimation.value,
                                                  child: Container(
                                                    width: 120,
                                                    height: 120,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: const Color(0xFFFFB74D).withOpacity(
                                                        1.0 - _pulseController.value,
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
}
