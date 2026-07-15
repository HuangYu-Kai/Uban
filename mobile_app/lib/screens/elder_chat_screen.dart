import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// 長輩端「和小雲聊天」—— 一般 AI 聊天頁（訊息泡泡 + 輸入列）。
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

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      '您好，${widget.userName}！我是小雲 😊\n想聊什麼都可以跟我說喔～',
      false,
    ));
  }

  @override
  void dispose() {
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
        reply = (result['message'] ?? '小雲現在有點累，等等再聊好嗎？').toString();
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
        _messages.add(_ChatMessage('小雲現在連不上，稍後再聊喔', false));
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6FC1A5), Color(0xFFEDF5F1)],
            stops: [0.0, 0.32],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.9),
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: const Text('☁️', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '小雲',
                style: GoogleFonts.notoSansTc(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Text(
                '陪您聊天的好朋友',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
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
          if (!isUser) ...[
            _miniAvatar(),
            const SizedBox(width: 8),
          ],
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
          _miniAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              '小雲思考中…',
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

  Widget _miniAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryLight,
      ),
      alignment: Alignment.center,
      child: const Text('☁️', style: TextStyle(fontSize: 20)),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        // 讓輸入列浮在底部導覽列之上
        MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 120,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
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
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: GoogleFonts.notoSansTc(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '想跟小雲說什麼…',
                  hintStyle: GoogleFonts.notoSansTc(
                    fontSize: 19,
                    color: AppColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 送出鈕
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _send,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
