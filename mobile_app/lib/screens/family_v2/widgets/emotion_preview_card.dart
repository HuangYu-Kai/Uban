import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../emotion_timeline_screen.dart';

/// 😊 情緒時間軸預覽卡片
/// 
/// 顯示長輩今日情緒變化曲線，點擊進入詳細頁面
class EmotionPreviewCard extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const EmotionPreviewCard({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<EmotionPreviewCard> createState() => _EmotionPreviewCardState();
}

class _EmotionPreviewCardState extends State<EmotionPreviewCard> {
  List<Map<String, dynamic>> _emotionData = [];
  String _currentEmotion = '平靜';
  Color _currentColor = const Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadEmotionData();
  }

  Future<void> _loadEmotionData() async {
    // TODO: 從 API 加載真實情緒數據
    await Future.delayed(const Duration(milliseconds: 600));
    
    setState(() {
      _emotionData = [
        {'time': '08:00', 'emotion': '開心', 'score': 0.8},
        {'time': '10:00', 'emotion': '平靜', 'score': 0.6},
        {'time': '12:00', 'emotion': '開心', 'score': 0.75},
        {'time': '14:00', 'emotion': '焦慮', 'score': 0.3},
        {'time': '16:00', 'emotion': '平靜', 'score': 0.65},
        {'time': '18:00', 'emotion': '開心', 'score': 0.85},
      ];
      _currentEmotion = '平靜';
      _currentColor = const Color(0xFF10B981);
    });
  }

  String _getEmotionEmoji(String emotion) {
    switch (emotion) {
      case '開心':
        return '😊';
      case '平靜':
        return '😌';
      case '焦慮':
        return '😰';
      case '悲傷':
        return '😢';
      default:
        return '😐';
    }
  }

  Color _getEmotionColor(String emotion) {
    switch (emotion) {
      case '開心':
        return const Color(0xFF10B981);
      case '平靜':
        return const Color(0xFF3B82F6);
      case '焦慮':
        return const Color(0xFFF59E0B);
      case '悲傷':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmotionTimelineScreen(
              elderName: widget.elderName,
              elderId: widget.elderId,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _currentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getEmotionEmoji(_currentEmotion),
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '情緒時間軸',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '當前情緒：$_currentEmotion',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFF94A3B8),
                  size: 18,
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // 簡化情緒曲線（水平時間軸）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _emotionData.map((data) {
                final score = data['score'] as double;
                final emotion = data['emotion'] as String;
                
                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 8,
                        height: 60 * score,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _getEmotionColor(emotion),
                              _getEmotionColor(emotion).withValues(alpha: 0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data['time'] as String,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 16),
            
            // 提示文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '點擊查看詳細情緒分析和對話記錄',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
