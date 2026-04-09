import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/animated_chat_bubble.dart';

/// 增強的家庭 AI 聊天屏幕，支持打字機效果和動態主題
class EnhancedFamilyAiChatScreen extends StatefulWidget {
  final String? elderName;
  final String? aiPersona;
  final int? elderId;

  const EnhancedFamilyAiChatScreen({
    super.key,
    this.elderName,
    this.aiPersona,
    this.elderId,
  });

  @override
  State<EnhancedFamilyAiChatScreen> createState() =>
      _EnhancedFamilyAiChatScreenState();
}

class _EnhancedFamilyAiChatScreenState extends State<EnhancedFamilyAiChatScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  bool _isThinking = false;
  bool _isRecording = false;
  String? _aiPersona;
  Color _accentColor = const Color(0xFF667EEA);

  @override
  void initState() {
    super.initState();
    _aiPersona = widget.aiPersona ?? '親切的老年陪伴員';
    _updateAccentColorFromPersona();
    _loadInitialMessage();
  }

  void _updateAccentColorFromPersona() {
    final persona = _aiPersona?.toLowerCase() ?? '';
    
    if (persona.contains('親切') || persona.contains('warmth')) {
      _accentColor = const Color(0xFFF59E0B);
    } else if (persona.contains('嚴謹') || persona.contains('professional')) {
      _accentColor = const Color(0xFF3B82F6);
    } else if (persona.contains('活潑') || persona.contains('playful')) {
      _accentColor = const Color(0xFFEC4899);
    } else if (persona.contains('溫柔') || persona.contains('gentle')) {
      _accentColor = const Color(0xFF8B5CF6);
    }
  }

  void _loadInitialMessage() {
    setState(() {
      _messages.add({
        'isUser': false,
        'text': '您好！我是您的智慧照護助理。${widget.elderName ?? '您的長輩'}今天的狀態穩定，早起活動量正常。有什麼想了解的嗎？',
        'duration': const Duration(milliseconds: 2000),
      });
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final userText = _controller.text.trim();
    setState(() {
      _messages.add({
        'isUser': true,
        'text': userText,
      });
      _isThinking = true;
      _controller.clear();
    });
    _scrollToBottom();

    // Simulate AI response with natural delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      
      final responses = [
        '根據最近的記錄，${widget.elderName ?? '媽媽'}在早上 8:42 完成了日常散步。心率保持在 72 次/分，屬於健康範圍。',
        '這是一個很好的問題！根據我的分析，${widget.elderName ?? '您的長輩'}最近的活動習慣良好，建議繼續保持現有的運動量。',
        '我看到${widget.elderName ?? '長輩'}昨天的睡眠品質達到了 85%，這表示他/她休息充分。',
        '建議在午後增加一些戶外活動時間，有利於維持良好的生理時鐘。',
      ];

      final response = responses[_messages.length % responses.length];
      
      setState(() {
        _isThinking = false;
        _messages.add({
          'isUser': false,
          'text': response,
          'duration': Duration(milliseconds: response.length * 25),
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ChatListView(
                    messages: _messages,
                    aiPersona: _aiPersona,
                    scrollController: _scrollController,
                  ),
          ),
          // Thinking indicator
          if (_isThinking) _buildThinkingIndicator(),
          // Input bar
          ChatInputBar(
            onSendMessage: (String text) => _sendMessage(),
            onVoiceStart: () {
              setState(() => _isRecording = true);
            },
            onVoiceEnd: () {
              setState(() => _isRecording = false);
              // Handle voice input here
            },
            isLoading: _isThinking,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Color(0xFF0F172A),
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '智慧照護助理',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _aiPersona ?? '在線中',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF667EEA),
            size: 20,
          ),
          onPressed: _showAiInfoModal,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: _accentColor,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
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
            '詢問關於 ${widget.elderName ?? "長輩"} 的任何事情',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: _accentColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI 助手正在思考...',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedBuilder(
                      animation: Tween<double>(begin: 0, end: 1).animate(
                        CurvedAnimation(
                          parent: AnimationController(
                            duration: const Duration(milliseconds: 600),
                            vsync: this,
                          )..repeat(),
                          curve: Curves.easeInOut,
                        ),
                      ),
                      builder: (context, child) {
                        return Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 
                              0.3 + (0.7 * (1 - (index / 3))),
                            ),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAiInfoModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI 助手資訊',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('性格設定', _aiPersona ?? '未設定'),
            const SizedBox(height: 12),
            _buildInfoRow('監測對象', widget.elderName ?? '未設定'),
            const SizedBox(height: 12),
            _buildInfoRow('功能狀態', '在線 · 全功能'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '關閉',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
            color: const Color(0xFF64748B),
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
}

