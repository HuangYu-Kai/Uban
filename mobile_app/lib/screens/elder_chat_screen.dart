import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// 長輩端「和小嘎聊天」—— 一般 AI 聊天頁（訊息泡泡 + 輸入列）。
///
/// 沿用既有 AI 後端 `ApiService.aiChat`。
/// 註：原本的禪意池塘聊天 `ZenPondScreen`（lib/screens/zen_pond/）**保留未刪**，
/// 只是不再掛在長輩導覽的聊天分頁；如需切回可於 elder_home_screen 換回。
class ElderChatScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderChatScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderChatScreen> createState() => _ElderChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser);
}

class _ElderChatScreenState extends State<ElderChatScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isThinking = false;

  // 語音輸入（沿用 speech_to_text）
  final SpeechToText _stt = SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  String _recognized = '';
  bool _voiceMode = true; // true=語音「按住說話」列，false=鍵盤輸入

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      '您好，${widget.userName}！我是小嘎 😊\n想聊什麼都可以跟我說喔～',
      false,
    ));
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _stt.initialize();
    } catch (_) {
      _speechReady = false;
    }
    if (mounted) setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() => _recognized = result.recognizedWords);
  }

  Future<void> _startListening() async {
    if (_isThinking || _isListening) return;
    if (!_speechReady) {
      _speechReady = await _stt.initialize();
      if (!_speechReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('這台裝置無法使用語音，請改用打字喔')),
          );
        }
        return;
      }
    }
    setState(() {
      _isListening = true;
      _recognized = '';
    });
    await _stt.listen(
      onResult: _onSpeechResult,
      localeId: 'zh_TW',
      listenFor: const Duration(seconds: 30),
    );
  }

  Future<void> _stopListeningAndSend() async {
    if (!_isListening) return;
    await _stt.stop();
    final text = _recognized.trim();
    setState(() => _isListening = false);
    if (text.isNotEmpty) {
      _controller.text = text;
      _send();
    }
  }

  @override
  void dispose() {
    _stt.stop();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isThinking) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isThinking = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final result = await ApiService.aiChat(widget.userId, text);
      String reply = '';
      if (result['reply'] != null) {
        reply = result['reply'].toString();
      } else if (result['data'] is Map && result['data']['reply'] != null) {
        reply = result['data']['reply'].toString();
      } else if (result['status'] == 'error') {
        reply = (result['message'] ?? '小嘎現在有點累，等等再聊好嗎？').toString();
      }
      // 移除回覆中的 [圖片]/[影片] 等標記
      reply = reply.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
      if (reply.isEmpty) reply = '嗯嗯，我在聽～';
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(reply, false));
        _isThinking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage('小嘎現在連不上，稍後再聊喔', false));
        _isThinking = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: _messages.length + (_isThinking ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return _buildThinkingBubble();
                        }
                        return _buildBubble(_messages[index]);
                      },
                    ),
                  ),
                  _buildInputBar(),
                ],
              ),
              if (_isListening) _buildListeningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // 錄音中：上方即時顯示辨識到的字，下方麥克風 + 放開送出
  Widget _buildListeningOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Column(
            children: [
              // 上方：即時辨識文字大氣泡
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 60, 28, 0),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 90),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF95EC69), // WeChat 綠
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _recognized.isEmpty ? '請開始說話…' : _recognized,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: _recognized.isEmpty
                          ? Colors.black45
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // 下方：麥克風 + 放開送出
              const Icon(Icons.graphic_eq_rounded,
                  color: Colors.white, size: 64),
              const SizedBox(height: 14),
              Text(
                '放開　送出給小嘎',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isUser ? 22 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                msg.text,
                style: GoogleFonts.notoSansTc(
                  fontSize: 20,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: isUser ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              '小嘎思考中…',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 120,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 切換：語音 / 鍵盤
          GestureDetector(
            onTap: () => setState(() => _voiceMode = !_voiceMode),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _voiceMode ? Icons.keyboard_rounded : Icons.mic_none_rounded,
                color: AppColors.primaryDark,
                size: 30,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _voiceMode ? _buildHoldToTalkBar() : _buildTextField(),
          ),
          if (!_voiceMode) ...[
            const SizedBox(width: 10),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _send,
                child: const Padding(
                  padding: EdgeInsets.all(15),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 「按住 說話」列
  Widget _buildHoldToTalkBar() {
    return GestureDetector(
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) => _stopListeningAndSend(),
      onLongPressCancel: () => _stopListeningAndSend(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isListening ? AppColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          _isListening ? '放開　送出' : '按住　說話',
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 4,
        autofocus: true,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        style: GoogleFonts.notoSansTc(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: '想跟小嘎說什麼…',
          hintStyle:
              GoogleFonts.notoSansTc(fontSize: 19, color: AppColors.textHint),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
    );
  }
}
