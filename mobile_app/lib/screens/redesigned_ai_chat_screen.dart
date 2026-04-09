import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 🎨 重新設計的聊天界面 - 高端現代风格
/// 靈感来自 Discord、Slack 的現代設計
class RedesignedAiChatScreen extends StatefulWidget {
  final String? elderName;
  final String? aiPersona;
  final int? elderId;

  const RedesignedAiChatScreen({
    super.key,
    this.elderName,
    this.aiPersona,
    this.elderId,
  });

  @override
  State<RedesignedAiChatScreen> createState() =>
      _RedesignedAiChatScreenState();
}

class _RedesignedAiChatScreenState extends State<RedesignedAiChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  bool _isTyping = false;
  bool _isRecording = false;
  late AnimationController _recordingController;

  // AI 人格配置
  final Map<String, Map<String, dynamic>> personaConfig = {
    'gentle': {
      'color': Color(0xFF8B5CF6),
      'emoji': '🤗',
      'name': '溫柔陪伴',
    },
    'friend': {
      'color': Color(0xFFEA580C),
      'emoji': '🧓',
      'name': '老友益友',
    },
    'butler': {
      'color': Color(0xFF16A34A),
      'emoji': '🎩',
      'name': '專業管家',
    },
    'grandson': {
      'color': Color(0xFF3B82F6),
      'emoji': '👦',
      'name': '活力孫兒',
    },
  };

  @override
  void initState() {
    super.initState();
    _recordingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _loadInitialMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordingController.dispose();
    super.dispose();
  }

  void _loadInitialMessage() {
    setState(() {
      _messages.add({
        'isUser': false,
        'text': '你好呀！我是 ${personaConfig['gentle']?['name'] ?? 'AI 伴侣'}。',
        'timestamp': DateTime.now(),
      });
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final userMessage = _messageController.text.trim();
    setState(() {
      _messages.add({
        'isUser': true,
        'text': userMessage,
        'timestamp': DateTime.now(),
      });
      _isTyping = true;
      _messageController.clear();
    });
    _scrollToBottom();

    // Simulate AI response
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      const responses = [
        '這是個很好的問題呢！讓我想想...',
        '我也這麼認為。你最近在做什麼有趣的事嗎？',
        '這確實需要時間來調整。但你做得很好！',
        '哈，你真有趣！我喜歡和你聊天。',
      ];

      final response = responses[_messages.length % responses.length];

      setState(() {
        _isTyping = false;
        _messages.add({
          'isUser': false,
          'text': response,
          'timestamp': DateTime.now(),
        });
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getPersonaColor() {
    final persona = widget.aiPersona?.toLowerCase() ?? 'gentle';
    return personaConfig[persona]?['color'] ?? Color(0xFF8B5CF6);
  }

  String _getPersonaEmoji() {
    final persona = widget.aiPersona?.toLowerCase() ?? 'gentle';
    return personaConfig[persona]?['emoji'] ?? '🤗';
  }

  String _getPersonaName() {
    final persona = widget.aiPersona?.toLowerCase() ?? 'gentle';
    return personaConfig[persona]?['name'] ?? 'AI 伴侣';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPersonaColor();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(primaryColor),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _messages.length) {
                        return _buildTypingIndicator(primaryColor);
                      }
                      final message = _messages[index];
                      return _buildMessageBubble(message, primaryColor);
                    },
                  ),
          ),
          // Input area
          _buildInputBar(primaryColor),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Color primaryColor) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _getPersonaEmoji(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getPersonaName(),
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                '${widget.elderName ?? '聊天中'} · 在線',
                style: GoogleFonts.notoSansTc(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.info_outline_rounded,
              color: primaryColor, size: 22),
          onPressed: () => _showPersonaInfo(primaryColor),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final primaryColor = _getPersonaColor();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Center(
              child: Text(
                _getPersonaEmoji(),
                style: const TextStyle(fontSize: 48),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '開始對話',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '和 ${_getPersonaName()} 聊天吧',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, Color primaryColor) {
    final isUser = message['isUser'] ?? false;
    final text = message['text'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isUser ? primaryColor : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: isUser
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              text,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                height: 1.5,
                color: isUser ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w400,
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 200.ms)
              .slideX(begin: isUser ? 0.2 : -0.2),
          const SizedBox(height: 4),
          Text(
            _formatTime(message['timestamp'] as DateTime),
            style: GoogleFonts.notoSansTc(
              fontSize: 11,
              color: const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: List.generate(
                3,
                (index) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedBuilder(
                    animation: Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _recordingController,
                        curve: Interval(index * 0.1, 0.3 + index * 0.1),
                      ),
                    ),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -6 * _recordingController.value),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: const Color(0xFFF0F1F3), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Voice button
            GestureDetector(
              onLongPress: () {
                setState(() => _isRecording = true);
              },
              onLongPressEnd: (_) {
                setState(() => _isRecording = false);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? primaryColor.withValues(alpha: 0.1)
                      : const Color(0xFFF1F5F9),
                  border: Border.all(
                    color: _isRecording
                        ? primaryColor
                        : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _recordingController,
                  builder: (context, child) {
                    return Icon(
                      Icons.mic,
                      color: _isRecording ? primaryColor : const Color(0xFF667EEA),
                      size: 20 + (_recordingController.value * 2),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Message input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        enabled: !_isTyping,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: '按住 🎤 或打字...',
                          hintStyle: GoogleFonts.notoSansTc(
                            fontSize: 14,
                            color: const Color(0xFFA0AEC0),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    // Emoji button
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined,
                          color: Color(0xFF94A3B8), size: 20),
                      onPressed: () {},
                      constraints: const BoxConstraints(maxWidth: 44),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            GestureDetector(
              onTap: _messageController.text.isEmpty || _isTyping
                  ? null
                  : _sendMessage,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _messageController.text.isEmpty || _isTyping
                      ? const Color(0xFFE5E7EB)
                      : primaryColor,
                  boxShadow:
                      _messageController.text.isNotEmpty && !_isTyping
                          ? [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : [],
                ),
                child: _isTyping
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonaInfo(Color primaryColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _getPersonaEmoji(),
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getPersonaName(),
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '与 ${widget.elderName ?? '长者'} 互动中',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: const Color(0xFFF0F1F3)),
            const SizedBox(height: 16),
            _buildInfoRow('状态', '在線 · 活跃中'),
            const SizedBox(height: 12),
            _buildInfoRow('响应速度', '即时'),
            const SizedBox(height: 12),
            _buildInfoRow('說話风格', _getPersonaName()),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '关闭',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (dateTime.day == now.day) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    return '${dateTime.month}/${dateTime.day}';
  }
}
