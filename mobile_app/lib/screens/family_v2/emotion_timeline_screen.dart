import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/emotion_data.dart';
import '../../services/emotion_storage_service.dart';

/// 😊 情緒時間軸完整頁面
/// 
/// 顯示長輩完整一天的情緒變化曲線
/// 支援點擊查看詳細對話記錄
class EmotionTimelineScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;
  final DateTime? initialDate;

  const EmotionTimelineScreen({
    super.key,
    required this.elderName,
    this.elderId,
    this.initialDate,
  });

  @override
  State<EmotionTimelineScreen> createState() => _EmotionTimelineScreenState();
}

class _EmotionTimelineScreenState extends State<EmotionTimelineScreen> {
  late DateTime _selectedDate;
  List<EmotionData> _emotionData = [];
  bool _isLoading = true;
  int? _selectedPointIndex;
  final EmotionStorageService _storageService = EmotionStorageService();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _loadEmotionData();
  }

  Future<void> _loadEmotionData() async {
    setState(() => _isLoading = true);
    
    // TODO: 從 API 或本地存儲加載真實數據
    // 目前使用模擬數據
    await Future.delayed(const Duration(milliseconds: 500));
    
    final mockData = _generateMockData();
    
    setState(() {
      _emotionData = mockData;
      _isLoading = false;
    });
  }

  List<EmotionData> _generateMockData() {
    final random = DateTime.now().millisecond;
    final baseDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    
    return List.generate(12, (index) {
      final hour = index * 2; // 每2小時一個數據點
      final emotions = [EmotionType.happy, EmotionType.calm, EmotionType.anxious, EmotionType.sad];
      final emotionType = emotions[(random + index) % emotions.length];
      
      return EmotionData(
        id: 'emotion_$index',
        elderId: widget.elderId ?? 1,
        timestamp: baseDate.add(Duration(hours: hour)),
        emotionType: emotionType,
        confidenceScore: 0.6 + (index % 4) * 0.1,
        metadata: {
          'dialogSnippet': _getDialogSnippet(emotionType),
          'trigger': _getTrigger(emotionType),
        },
      );
    });
  }

  String _getDialogSnippet(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return '「孫子今天來看我，真開心！」';
      case EmotionType.calm:
        return '「今天天氣不錯，很舒服。」';
      case EmotionType.anxious:
        return '「不知道藥吃對了沒...」';
      case EmotionType.sad:
        return '「有點想念老伴了...」';
      default:
        return '「...」';
    }
  }

  String _getTrigger(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return '家人探訪';
      case EmotionType.calm:
        return '日常活動';
      case EmotionType.anxious:
        return '健康擔憂';
      case EmotionType.sad:
        return '懷念往事';
      default:
        return '未知';
    }
  }

  Color _getEmotionColor(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return const Color(0xFF10B981);
      case EmotionType.calm:
        return const Color(0xFF3B82F6);
      case EmotionType.anxious:
        return const Color(0xFFF59E0B);
      case EmotionType.sad:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _getEmotionLabel(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return '開心';
      case EmotionType.calm:
        return '平靜';
      case EmotionType.anxious:
        return '焦慮';
      case EmotionType.sad:
        return '悲傷';
      default:
        return '其他';
    }
  }

  String _getEmotionEmoji(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return '😊';
      case EmotionType.calm:
        return '😌';
      case EmotionType.anxious:
        return '😰';
      case EmotionType.sad:
        return '😢';
      default:
        return '😐';
    }
  }

  void _previousDay() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _selectedPointIndex = null;
    });
    _loadEmotionData();
  }

  void _nextDay() {
    HapticFeedback.lightImpact();
    if (_selectedDate.isBefore(DateTime.now())) {
      setState(() {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
        _selectedPointIndex = null;
      });
      _loadEmotionData();
    }
  }

  Map<String, int> _getEmotionStatistics() {
    final stats = <String, int>{};
    for (final emotion in _emotionData) {
      final label = _getEmotionLabel(emotion.emotionType);
      stats[label] = (stats[label] ?? 0) + 1;
    }
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '情緒時間軸',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // 日期選擇器
                  _buildDateSelector(),
                  
                  // 情緒曲線圖
                  _buildEmotionChart(),
                  
                  // 選中點詳情
                  if (_selectedPointIndex != null)
                    _buildSelectedPointDetail(),
                  
                  // 情緒統計
                  _buildEmotionStatistics(),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _previousDay,
            color: const Color(0xFF3B82F6),
          ),
          Column(
            children: [
              Text(
                '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Text(
                _getWeekdayLabel(_selectedDate.weekday),
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _selectedDate.isBefore(DateTime.now()) ? _nextDay : null,
            color: _selectedDate.isBefore(DateTime.now())
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE2E8F0),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  String _getWeekdayLabel(int weekday) {
    const labels = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
    return labels[weekday - 1];
  }

  Widget _buildEmotionChart() {
    if (_emotionData.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            '此日期暫無情緒數據',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '情緒變化曲線',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.25,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFFE2E8F0),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        const labels = ['悲傷', '焦慮', '平靜', '開心'];
                        if (value >= 0 && value < labels.length) {
                          return Text(
                            labels[value.toInt()],
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}:00',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _emotionData.asMap().entries.map((entry) {
                      final hour = entry.value.timestamp.hour.toDouble();
                      final emotionValue = _emotionTypeToValue(entry.value.emotionType);
                      return FlSpot(hour, emotionValue);
                    }).toList(),
                    isCurved: true,
                    color: const Color(0xFF3B82F6),
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final emotion = _emotionData[index];
                        return FlDotCirclePainter(
                          radius: emotion.isAbnormal ? 6 : 4,
                          color: _getEmotionColor(emotion.emotionType),
                          strokeWidth: emotion.isAbnormal ? 2 : 0,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                    if (response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
                      setState(() {
                        _selectedPointIndex = response.lineBarSpots!.first.spotIndex;
                      });
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.white,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final emotion = _emotionData[spot.spotIndex];
                        return LineTooltipItem(
                          '${_getEmotionEmoji(emotion.emotionType)} ${_getEmotionLabel(emotion.emotionType)}\n${emotion.timestamp.hour}:00',
                          GoogleFonts.notoSansTc(
                            color: _getEmotionColor(emotion.emotionType),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                minY: 0,
                maxY: 3,
                minX: 0,
                maxX: 24,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  double _emotionTypeToValue(EmotionType type) {
    switch (type) {
      case EmotionType.sad:
        return 0.5;
      case EmotionType.anxious:
        return 1.2;
      case EmotionType.calm:
        return 2.0;
      case EmotionType.happy:
        return 2.8;
      default:
        return 1.5;
    }
  }

  Widget _buildSelectedPointDetail() {
    final emotion = _emotionData[_selectedPointIndex!];
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getEmotionColor(emotion.emotionType).withValues(alpha: 0.1),
            _getEmotionColor(emotion.emotionType).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getEmotionColor(emotion.emotionType).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _getEmotionEmoji(emotion.emotionType),
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${emotion.timestamp.hour.toString().padLeft(2, '0')}:${emotion.timestamp.minute.toString().padLeft(2, '0')} ${_getEmotionLabel(emotion.emotionType)}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _getEmotionColor(emotion.emotionType),
                      ),
                    ),
                    Text(
                      '信心分數：${(emotion.confidenceScore * 100).toInt()}%',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 16, color: _getEmotionColor(emotion.emotionType)),
                    const SizedBox(width: 8),
                    Text(
                      '對話片段',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  emotion.metadata?['dialogSnippet'] ?? '無對話記錄',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF475569),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getEmotionColor(emotion.emotionType).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '觸發因素：${emotion.metadata?['trigger'] ?? '未知'}',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getEmotionColor(emotion.emotionType),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildEmotionStatistics() {
    final stats = _getEmotionStatistics();
    final total = stats.values.fold(0, (sum, count) => sum + count);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日情緒分佈',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          ...stats.entries.map((entry) {
            final percentage = ((entry.value / total) * 100).toInt();
            final emotionType = _labelToEmotionType(entry.key);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getEmotionEmoji(emotionType),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$percentage%',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _getEmotionColor(emotionType),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: entry.value / total,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(_getEmotionColor(emotionType)),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  EmotionType _labelToEmotionType(String label) {
    switch (label) {
      case '開心':
        return EmotionType.happy;
      case '平靜':
        return EmotionType.calm;
      case '焦慮':
        return EmotionType.anxious;
      case '悲傷':
        return EmotionType.sad;
      default:
        return EmotionType.calm;
    }
  }
}
