import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();

  // 聊天記錄
  final List<Map<String, dynamic>> _messages = [
    {'role': 'ai', 'text': '爺爺午安！今天過得好嗎？\n您可以按住下面的麥克風跟我說話喔！'},
  ];

  bool _isListening = false; // 是否正在聽 (按住麥克風)
  bool _isThinking = false; // AI 是否正在思考
  String _listeningText = "請說話...";

  @override
  void initState() {
    super.initState();
    _initTts();
    // 進入畫面先念出第一句
    Future.delayed(const Duration(seconds: 1), () {
      _speak(_messages.first['text']);
    });

    // 演示用：5秒後模擬子女傳送話題
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _simulateCaregiverTopic();
    });
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("zh-TW");
    await flutterTts.setSpeechRate(0.5); // 語速慢一點
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  // 模擬收到語音輸入
  void _startListening() {
    setState(() {
      _isListening = true;
      _listeningText = "正在聽您說...";
    });
    // 這裡可以加上震動回饋
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
      _listeningText = "請說話...";
    });

    // 模擬辨識到的文字
    // 在真實 App 中，這裡是 STT 的結果
    _handleUserMessage("今天天氣很好，我想去公園走走");
  }

  // 處理使用者訊息
  void _handleUserMessage(String text) {
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isThinking = true;
    });
    _scrollToBottom();

    // 模擬 AI 思考與回應
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      String response = "那真是太棒了！公園的空氣一定很新鮮。\n記得帶瓶水，慢慢走，注意安全喔！";

      setState(() {
        _isThinking = false;
        _messages.add({'role': 'ai', 'text': response});
      });
      _scrollToBottom();
      _speak(response);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 模擬子女設定話題
  void _simulateCaregiverTopic() {
    setState(() {
      _messages.add({
        'role': 'ai',
        'text': '爺爺，秀珠傳了一張照片來。\n她說這是上次去陽明山看花鐘拍的，您還記得嗎？',
        'image':
            'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a3/Yangmingshan_Flower_Clock.jpg/1200px-Yangmingshan_Flower_Clock.jpg', // 範例圖片
      });
    });
    _scrollToBottom();
    _speak('爺爺，秀珠傳了一張照片來，她說這是上次去陽明山看花鐘拍的，您還記得嗎？');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 溫馨米黃
      appBar: AppBar(
        title: Text(
          '貼心陪聊',
          style: GoogleFonts.notoSansTc(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        toolbarHeight: 80,
        actions: [
          // 測試按鈕
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.deepOrange),
            onPressed: _simulateCaregiverTopic,
            tooltip: '模擬家人話題',
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 聊天訊息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount: _messages.length + (_isThinking ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildThinkingBubble();
                }
                final msg = _messages[index];
                return _buildChatBubble(
                  msg['text'],
                  msg['role'] == 'ai',
                  imageUrl: msg['image'],
                );
              },
            ),
          ),

          // 2. 底部輸入區
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 狀態提示字
                Text(
                  _isListening ? _listeningText : "按住麥克風說話",
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    color: _isListening ? Colors.deepOrange : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                // 大按鈕區
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 鍵盤輸入 (次要功能)
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[200],
                      child: IconButton(
                        icon: const Icon(
                          Icons.keyboard,
                          color: Colors.grey,
                          size: 30,
                        ),
                        onPressed: () {
                          // TODO: 開啟鍵盤輸入
                        },
                      ),
                    ),

                    // 麥克風 (主要功能 - 超大)
                    GestureDetector(
                      onTapDown: (_) => _startListening(), // 按下開始
                      onTapUp: (_) => _stopListening(), // 放開結束
                      onTapCancel: _stopListening, // 移開取消
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _isListening ? 140 : 120,
                        height: _isListening ? 140 : 120,
                        decoration: BoxDecoration(
                          color: _isListening
                              ? Colors.deepOrange
                              : Colors.orange, // 換成橘色系
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (_isListening
                                          ? Colors.tealAccent
                                          : Colors.teal)
                                      .withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: _isListening ? 10 : 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // 重播 (次要功能)
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[200],
                      child: IconButton(
                        icon: const Icon(
                          Icons.volume_up,
                          color: Colors.grey,
                          size: 30,
                        ),
                        onPressed: () {
                          if (_messages.isNotEmpty && !_isThinking) {
                            // 找出最後一則 AI 訊息重播
                            final lastAiMsg = _messages.lastWhere(
                              (m) => m['role'] == 'ai',
                              orElse: () => {},
                            );
                            if (lastAiMsg.isNotEmpty) {
                              _speak(lastAiMsg['text']);
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isAi, {String? imageUrl}) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : const Color(0xFFFFF3E0), // 淡橘色
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: isAi ? Radius.zero : const Radius.circular(24),
            bottomRight: isAi ? const Radius.circular(24) : Radius.zero,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAi) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(
                    FontAwesomeIcons.robot,
                    size: 24,
                    color: Colors.deepOrange, // 換成深橘色
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '貼心小幫手',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      color: Colors.deepOrange, // 換成深橘色
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // 顯示圖片 (如果有的話)
            if (imageUrl != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.deepOrange,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 50,
                        ),
                      ),
                    );
                  },
                ),
              ),
            Text(
              text,
              style: GoogleFonts.notoSansTc(
                fontSize: 28, // 大字體
                height: 1.5,
                color: const Color(0xFF333333),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.2, end: 0);
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.deepOrange, // 換成深橘色
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '思考中...',
              style: GoogleFonts.notoSansTc(fontSize: 24, color: Colors.grey),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }
}
