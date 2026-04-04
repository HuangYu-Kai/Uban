import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 聊天氣泡組件，支持打字機效果和豐富的 Markdown
class AnimatedChatBubble extends StatefulWidget {
  final String text;
  final bool isUser;
  final String? aiPersona;
  final Duration? typewriterDuration;
  final bool isLastMessage;

  const AnimatedChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.aiPersona,
    this.typewriterDuration,
    this.isLastMessage = false,
  });

  @override
  State<AnimatedChatBubble> createState() => _AnimatedChatBubbleState();
}

class _AnimatedChatBubbleState extends State<AnimatedChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _typewriterController;
  late Animation<int> _charCount;
  String _displayText = '';

  @override
  void initState() {
    super.initState();

    // Only animate typewriter for AI messages
    if (!widget.isUser) {
      final duration = widget.typewriterDuration ??
          Duration(milliseconds: widget.text.length * 30);

      _typewriterController = AnimationController(
        duration: duration,
        vsync: this,
      );

      _charCount = IntTween(
        begin: 0,
        end: widget.text.length,
      ).animate(CurvedAnimation(parent: _typewriterController, curve: Curves.linear));

      _typewriterController.forward();

      _charCount.addListener(() {
        setState(() {
          _displayText = widget.text.substring(0, _charCount.value);
        });
      });
    } else {
      _displayText = widget.text;
    }
  }

  @override
  void dispose() {
    _typewriterController.dispose();
    super.dispose();
  }

  Color _getAiPersonaColor(String? persona) {
    if (persona == null) return const Color(0xFF667EEA);

    final lowerPersona = persona.toLowerCase();
    
    if (lowerPersona.contains('親切') || lowerPersona.contains('warmth')) {
      return const Color(0xFFF59E0B); // Warm orange
    } else if (lowerPersona.contains('嚴謹') || lowerPersona.contains('professional')) {
      return const Color(0xFF3B82F6); // Professional blue
    } else if (lowerPersona.contains('活潑') || lowerPersona.contains('playful')) {
      return const Color(0xFFEC4899); // Playful pink
    } else if (lowerPersona.contains('溫柔') || lowerPersona.contains('gentle')) {
      return const Color(0xFF8B5CF6); // Gentle purple
    }
    
    return const Color(0xFF667EEA); // Default indigo
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isUser
        ? const Color(0xFF2563EB)
        : _getAiPersonaColor(widget.aiPersona);

    final textColor =
        widget.isUser ? Colors.white : const Color(0xFF0F172A);

    return Container(
      margin: EdgeInsets.only(
        bottom: 12,
        left: widget.isUser ? 60 : 0,
        right: widget.isUser ? 0 : 60,
      ),
      child: Column(
        crossAxisAlignment: widget.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // AI Persona indicator
          if (!widget.isUser && widget.isLastMessage)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 12),
              child: Text(
                widget.aiPersona ?? 'AI 助手',
                style: GoogleFonts.notoSansTc(
                  fontSize: 10,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Chat bubble
          Container(
            decoration: BoxDecoration(
              color: widget.isUser
                  ? bubbleColor
                  : bubbleColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: !widget.isUser
                  ? Border.all(
                      color: bubbleColor.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
              boxShadow: widget.isUser
                  ? [
                      BoxShadow(
                        color: bubbleColor.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Stack(
              children: [
                Text(
                  _displayText,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
                // Blinking cursor for typewriter effect
                if (!widget.isUser &&
                    _displayText.length < widget.text.length)
                  Positioned(
                    right: 0,
                    child: _buildCursor(),
                  ),
              ],
            ),
          ).animate().slideX(begin: widget.isUser ? 0.3 : -0.3).fade(),
          // Timestamp (optional)
          if (widget.isLastMessage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _getTimeString(),
                style: GoogleFonts.notoSansTc(
                  fontSize: 10,
                  color: const Color(0xFFA0AEC0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCursor() {
    return AnimatedBuilder(
      animation: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _typewriterController,
          curve: Interval(0.8, 1.0),
        ),
      ),
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (0.5 * (0.5 + 0.5 * (1 - (_typewriterController.value % 0.5).abs() / 0.25))),
          child: Text(
            '▌',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: _getAiPersonaColor(widget.aiPersona),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }

  String _getTimeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

/// 聊天列表視圖，管理多個聊天氣泡
class ChatListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String? aiPersona;
  final ScrollController? scrollController;

  const ChatListView({
    super.key,
    required this.messages,
    this.aiPersona,
    this.scrollController,
  });

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  @override
  void didUpdateWidget(ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new message arrives
    Future.delayed(const Duration(milliseconds: 100), () {
      if (widget.scrollController != null &&
          widget.scrollController!.hasClients) {
        widget.scrollController!.animateTo(
          widget.scrollController!.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final message = widget.messages[index];
        final isLastMessage = index == widget.messages.length - 1;

        return AnimatedChatBubble(
          text: message['text'] ?? '',
          isUser: message['isUser'] ?? false,
          aiPersona: !message['isUser'] ? widget.aiPersona : null,
          isLastMessage: isLastMessage,
          typewriterDuration: message['duration'],
        );
      },
    );
  }
}

/// 聊天輸入框組件，支持聲音和文字輸入
class ChatInputBar extends StatefulWidget {
  final Function(String) onSendMessage;
  final Function? onVoiceStart;
  final Function? onVoiceEnd;
  final bool isLoading;

  const ChatInputBar({
    super.key,
    required this.onSendMessage,
    this.onVoiceStart,
    this.onVoiceEnd,
    this.isLoading = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  bool _isRecording = false;
  late AnimationController _recordingController;

  @override
  void initState() {
    super.initState();
    _recordingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _recordingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Microphone button
            GestureDetector(
              onLongPress: () {
                setState(() => _isRecording = true);
                widget.onVoiceStart?.call();
              },
              onLongPressEnd: (_) {
                setState(() => _isRecording = false);
                widget.onVoiceEnd?.call();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                      : const Color(0xFF667EEA).withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isRecording
                        ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                        : const Color(0xFF667EEA).withValues(alpha: 0.3),
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _recordingController,
                  builder: (context, child) {
                    return Icon(
                      Icons.mic,
                      color: _isRecording
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF667EEA),
                      size: 20 + (_recordingController.value * 2),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  enabled: !widget.isLoading,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: '輸入訊息或按住麥克風說話...',
                    hintStyle: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: const Color(0xFFA0AEC0),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Send button
            GestureDetector(
              onTap: widget.isLoading
                  ? null
                  : () {
                      if (_textController.text.isNotEmpty) {
                        widget.onSendMessage(_textController.text);
                        _textController.clear();
                      }
                    },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _textController.text.isEmpty || widget.isLoading
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF2563EB),
                ),
                child: widget.isLoading
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
                    : const Icon(
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
}

