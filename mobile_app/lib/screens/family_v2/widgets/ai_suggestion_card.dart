import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../services/ai_suggestion_service.dart';

/// 🤖 AI 智能建議卡片
/// 
/// 每天早上 AI 分析長輩數據，生成個人化建議
/// 用戶可快速執行建議（一鍵撥放音樂、發送提醒等）
/// 
/// 使用 AiSuggestionService 生成建議，支援真實數據和 Mock 數據模式
class AiSuggestionCard extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const AiSuggestionCard({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<AiSuggestionCard> createState() => _AiSuggestionCardState();
}

class _AiSuggestionCardState extends State<AiSuggestionCard> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 使用 AI 建議服務生成建議
      // 目前使用 Mock 數據模式，未來可切換為真實數據模式
      final suggestions = await AiSuggestionService.generateSuggestions(
        elderData: {
          'elder_name': widget.elderName,
          'user_id': widget.elderId,
        },
        useMockData: true, // 設置為 false 以使用真實數據
        // 真實數據模式範例：
        // healthData: {
        //   'sleep_quality': 65.0,
        //   'steps': 450,
        //   'heart_rate': 85,
        //   'sleep_history': [...],
        //   'steps_history': [...],
        //   'heart_rate_history': [...],
        // },
        // emotionData: [
        //   {'time': '08:00', 'emotion': '開心', 'score': 0.8},
        //   {'time': '10:00', 'emotion': '焦慮', 'score': 0.3},
        // ],
      );

      setState(() {
        _suggestions = suggestions.map((s) => s.toMap()).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('載入建議失敗: $e');
      setState(() {
        _isLoading = false;
        _suggestions = [];
      });
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case 'high':
        return '重要';
      case 'medium':
        return '注意';
      default:
        return '提示';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3B82F6),
            const Color(0xFF8B5CF6),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題區
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日智能建議',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'AI 為您量身打造',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // 建議列表
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else if (_suggestions.isEmpty)
                // 空狀態
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.wb_sunny_outlined,
                        size: 48,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '今日一切安好',
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI 分析後沒有發現需要特別關注的事項',
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._suggestions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final suggestion = entry.value;
                  
                  return Container(
                    margin: EdgeInsets.only(bottom: index < _suggestions.length - 1 ? 12 : 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              suggestion['icon'] as IconData,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                suggestion['title'] as String,
                                style: GoogleFonts.notoSansTc(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getPriorityColor(suggestion['priority'] as String).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getPriorityColor(suggestion['priority'] as String).withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _getPriorityLabel(suggestion['priority'] as String),
                                style: GoogleFonts.notoSansTc(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          suggestion['description'] as String,
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            // TODO: 執行建議動作
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('執行：${suggestion['action']}'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.touch_app_rounded,
                                  size: 16,
                                  color: _getPriorityColor(suggestion['priority'] as String),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  suggestion['action'] as String,
                                  style: GoogleFonts.notoSansTc(
                                    color: _getPriorityColor(suggestion['priority'] as String),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate()
                    .fadeIn(delay: (index * 100).ms)
                    .slideX(begin: 0.1, end: 0);
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}
