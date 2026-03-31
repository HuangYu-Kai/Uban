import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../widgets/youtube_bubble_player.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();

  // 演示用固定的 User ID (對應後端資料庫中的長輩)
  final int _elderId = 1;

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
    await flutterTts.setSpeechRate(0.5);
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
  }

  void _stopListening() {
    setState(() {
      _isListening = false;
      _listeningText = "請說話...";
    });

    // 模擬辨識到的文字
    _handleUserMessage("今天天氣很好，我想去公園走走");
  }

  // 處理使用者訊息
  Future<void> _handleUserMessage(String text) async {
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isThinking = true;
    });
    _scrollToBottom();

    try {
      // 呼叫後端 AI 介面
      final result = await ApiService.aiChat(_elderId, text);

      if (!mounted) return;

      if (result.containsKey('reply')) {
        String response = result['reply'];
        setState(() {
          _isThinking = false;
          _messages.add({'role': 'ai', 'text': response});
        });
        _scrollToBottom();
        
        // 播放語音時，先移除 [VIDEO_ID:...] 標籤，避免唸出技術字眼
        String speakText = response.replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '');
        _speak(speakText);
      } else {
        throw Exception('回傳格式錯誤');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add({'role': 'ai', 'text': '抱歉，小幫手現在連不上網路。您可以待會再試試看嗎？'});
      });
      _scrollToBottom();
    }
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
      backgroundColor: const Color(0xFFFFFBF0),
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
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.deepOrange),
            onPressed: _simulateCaregiverTopic,
            tooltip: '模擬家人話題',
          ),
        ],
      ),
      body: Column(
        children: [
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
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isListening ? _listeningText : "按住麥克風說話",
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              color: _isListening ? Colors.deepOrange : Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSmallIconButton(Icons.keyboard, () => _showTextInputDialog()),
              _buildMicButton(),
              _buildSmallIconButton(Icons.volume_up, () {
                if (_messages.isNotEmpty && !_isThinking) {
                  final lastAiMsg = _messages.lastWhere((m) => m['role'] == 'ai', orElse: () => {});
                  if (lastAiMsg.isNotEmpty) _speak(lastAiMsg['text']);
                }
              }),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSmallIconButton(IconData icon, VoidCallback onPressed) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.grey[200],
      child: IconButton(
        icon: Icon(icon, color: Colors.grey, size: 30),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTapDown: (_) => _startListening(),
      onTapUp: (_) => _stopListening(),
      onTapCancel: _stopListening,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isListening ? 140 : 120,
        height: _isListening ? 140 : 120,
        decoration: BoxDecoration(
          color: _isListening ? Colors.deepOrange : Colors.orange,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (_isListening ? Colors.tealAccent : Colors.teal).withValues(alpha: 0.4),
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
    );
  }

  Widget _buildChatBubble(String text, bool isAi, {String? imageUrl}) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: isAi ? Radius.zero : const Radius.circular(24),
            bottomRight: isAi ? const Radius.circular(24) : Radius.zero,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Builder(
          builder: (context) {
            if (isAi && text.contains('[VIDEO_ID:')) {
              final regExp = RegExp(r'\[VIDEO_ID:([^\]]+)\]');
              final match = regExp.firstMatch(text);
              if (match != null) {
                final videoId = match.group(1)!;
                final cleanText = text.replaceAll(regExp, '').trim();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAiHeader(),
                    if (cleanText.isNotEmpty) ...[
                      _buildTextContent(cleanText),
                      const SizedBox(height: 12),
                    ],
                    YoutubeBubblePlayer(videoId: videoId),
                  ],
                );
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isAi) _buildAiHeader(),
                if (imageUrl != null) _buildImageContent(imageUrl),
                _buildTextContent(text),
              ],
            );
          },
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.2, end: 0);
  }

  Widget _buildAiHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.robot, size: 24, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Text(
            '貼心小幫手',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextContent(String text) {
    return Text(
      text,
      style: GoogleFonts.notoSansTc(
        fontSize: 28,
        height: 1.5,
        color: const Color(0xFF333333),
      ),
    );
  }

  Widget _buildImageContent(String imageUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(height: 200, width: double.infinity, child: Center(child: CircularProgressIndicator(color: Colors.deepOrange)));
        },
        errorBuilder: (context, error, stackTrace) => Container(height: 200, width: double.infinity, color: Colors.grey[200], child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50))),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.deepOrange)),
            const SizedBox(width: 16),
            Text('思考中...', style: GoogleFonts.notoSansTc(fontSize: 24, color: Colors.grey)),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  void _showTextInputDialog() {
    final TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('輸入訊息', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          style: GoogleFonts.notoSansTc(fontSize: 24),
          decoration: const InputDecoration(hintText: '請輸入您想說的話...', border: OutlineInputBorder()),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: GoogleFonts.notoSansTc(fontSize: 20, color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              if (text.isNotEmpty) _handleUserMessage(text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: Text('發送', style: GoogleFonts.notoSansTc(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
