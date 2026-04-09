import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../services/ai_suggestion_service.dart';
import '../../../services/api_service.dart';
import 'package:flutter_application_1/utils/app_logger.dart';

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
      // 如果有 elderId，從 API 獲取真實建議
      if (widget.elderId != null) {
        appLogger.d('🔄 Loading suggestions for elder ID: ${widget.elderId}');
        final response = await ApiService.getDailySuggestions(widget.elderId!);
        
        if (response['status'] == 'success' && response['data'] != null) {
          final data = response['data'];
          final suggestionsData = data['suggestions'] as List<dynamic>;
          
          setState(() {
            _suggestions = suggestionsData.map((s) => s as Map<String, dynamic>).toList();
            _isLoading = false;
          });
          
          appLogger.d('✅ Loaded ${_suggestions.length} suggestions from API');
          return;
        } else {
          appLogger.d('⚠️ API returned error: ${response['message']}');
        }
      }
      
      // 備用：使用 Mock 數據
      appLogger.d('📝 Using mock suggestions');
      final suggestions = await AiSuggestionService.generateSuggestions(
        elderData: {
          'elder_name': widget.elderName,
          'user_id': widget.elderId,
        },
        useMockData: true,
      );

      setState(() {
        _suggestions = suggestions.map((s) => s.toMap()).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 載入建議失敗: $e');
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

  Widget _buildIconWidget(Map<String, dynamic> suggestion) {
    final icon = suggestion['icon'];
    
    if (icon is IconData) {
      // 舊格式：IconData
      return Icon(
        icon,
        color: Colors.white,
        size: 20,
      );
    } else if (icon is String) {
      // 新格式：emoji 字符串
      return Text(
        icon,
        style: const TextStyle(fontSize: 20),
      );
    } else {
      // 默認圖標
      return const Icon(
        Icons.lightbulb_outline_rounded,
        color: Colors.white,
        size: 20,
      );
    }
  }

  String _getActionLabel(dynamic action) {
    if (action is Map) {
      return action['label'] as String? ?? '執行';
    } else if (action is String) {
      return action;
    }
    return '執行';
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
            color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // 背景裝飾
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            // 主要內容
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // 標題區 - 增強設計
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日智能建議',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '✨ AI 為您量身打造',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 建議列表
              if (_isLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '分析中...',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_suggestions.isEmpty)
                // 空狀態 - 優化設計
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.wb_sunny_outlined,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '今日一切安好 💚',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 分析後沒有發現需要特別關注的事項',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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
                            // 處理圖標（可能是 IconData 或 emoji 字符串）
                            _buildIconWidget(suggestion),
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
                            // 執行建議動作（支持新 API 格式）
                            final action = suggestion['action'];
                            String actionLabel = '';
                            
                            if (action is Map) {
                              actionLabel = action['label'] as String? ?? '執行';
                            } else if (action is String) {
                              actionLabel = action;
                            }
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('執行：$actionLabel'),
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
                                  _getActionLabel(suggestion['action']),
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
                }),
            ],
          ),
        ),
      ],
    ),
  ),
);
  }
}
