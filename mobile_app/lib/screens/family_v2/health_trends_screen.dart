import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/elder_manager.dart';

/// 📊 健康趨勢中心
/// 
/// 多維度健康數據趨勢圖表
/// 支援心率、血壓、血糖、體重等多條曲線
class HealthTrendsScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const HealthTrendsScreen({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<HealthTrendsScreen> createState() => _HealthTrendsScreenState();
}

enum TimeRange { day, week, month, year }

enum HealthMetric { heartRate, bloodPressure, bloodSugar, weight }

class _HealthTrendsScreenState extends State<HealthTrendsScreen> {
  final ElderManager _elderManager = ElderManager();
  
  TimeRange _selectedTimeRange = TimeRange.week;
  Set<HealthMetric> _visibleMetrics = {
    HealthMetric.heartRate,
    HealthMetric.bloodPressure,
    HealthMetric.bloodSugar,
    HealthMetric.weight,
  };
  
  bool _isLoading = true;
  Map<HealthMetric, List<FlSpot>> _chartData = {};
  
  // 從 ElderManager 取得真實資料
  String get _displayElderName => _elderManager.currentElder?.displayName ?? widget.elderName;
  int? get _displayElderId => _elderManager.currentElder?.id ?? widget.elderId;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() => _isLoading = true);
    
    // TODO: 使用 _displayElderId 從 API 加載真實健康數據
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _chartData = _generateMockData();
      _isLoading = false;
    });
  }

  Map<HealthMetric, List<FlSpot>> _generateMockData() {
    final random = DateTime.now().millisecond;
    final dataPoints = _selectedTimeRange == TimeRange.day ? 24 
        : _selectedTimeRange == TimeRange.week ? 7
        : _selectedTimeRange == TimeRange.month ? 30 : 12;
    
    return {
      HealthMetric.heartRate: List.generate(dataPoints, (i) => 
          FlSpot(i.toDouble(), 60 + (random + i * 3) % 30 + 0.0)),
      HealthMetric.bloodPressure: List.generate(dataPoints, (i) => 
          FlSpot(i.toDouble(), 110 + (random + i * 5) % 30 + 0.0)),
      HealthMetric.bloodSugar: List.generate(dataPoints, (i) => 
          FlSpot(i.toDouble(), 90 + (random + i * 2) % 30 + 0.0)),
      HealthMetric.weight: List.generate(dataPoints, (i) => 
          FlSpot(i.toDouble(), 65 + (random + i) % 5 + 0.0)),
    };
  }

  Color _getMetricColor(HealthMetric metric) {
    switch (metric) {
      case HealthMetric.heartRate:
        return const Color(0xFFEF4444);
      case HealthMetric.bloodPressure:
        return const Color(0xFF3B82F6);
      case HealthMetric.bloodSugar:
        return const Color(0xFFF59E0B);
      case HealthMetric.weight:
        return const Color(0xFF8B5CF6);
    }
  }

  String _getMetricLabel(HealthMetric metric) {
    switch (metric) {
      case HealthMetric.heartRate:
        return '心率';
      case HealthMetric.bloodPressure:
        return '血壓';
      case HealthMetric.bloodSugar:
        return '血糖';
      case HealthMetric.weight:
        return '體重';
    }
  }

  String _getMetricUnit(HealthMetric metric) {
    switch (metric) {
      case HealthMetric.heartRate:
        return 'bpm';
      case HealthMetric.bloodPressure:
        return 'mmHg';
      case HealthMetric.bloodSugar:
        return 'mg/dL';
      case HealthMetric.weight:
        return 'kg';
    }
  }

  IconData _getMetricIcon(HealthMetric metric) {
    switch (metric) {
      case HealthMetric.heartRate:
        return Icons.favorite;
      case HealthMetric.bloodPressure:
        return Icons.bloodtype;
      case HealthMetric.bloodSugar:
        return Icons.opacity;
      case HealthMetric.weight:
        return Icons.monitor_weight;
    }
  }

  void _toggleMetric(HealthMetric metric) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_visibleMetrics.contains(metric)) {
        if (_visibleMetrics.length > 1) {
          _visibleMetrics.remove(metric);
        }
      } else {
        _visibleMetrics.add(metric);
      }
    });
  }

  void _changeTimeRange(TimeRange range) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedTimeRange = range;
    });
    _loadHealthData();
  }

  String _getTimeRangeLabel(TimeRange range) {
    switch (range) {
      case TimeRange.day:
        return '日';
      case TimeRange.week:
        return '週';
      case TimeRange.month:
        return '月';
      case TimeRange.year:
        return '年';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // 移除自動返回按鈕
        title: Text(
          '健康趨勢',
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
                  // 時間範圍選擇器
                  _buildTimeRangeSelector(),
                  
                  // 圖例（指標選擇）
                  _buildMetricLegend(),
                  
                  // 主要圖表
                  _buildMainChart(),
                  
                  // 數據摘要
                  _buildDataSummary(),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: TimeRange.values.map((range) {
          final isSelected = range == _selectedTimeRange;
          return Expanded(
            child: GestureDetector(
              onTap: () => _changeTimeRange(range),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getTimeRangeLabel(range),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMetricLegend() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: HealthMetric.values.map((metric) {
          final isVisible = _visibleMetrics.contains(metric);
          return GestureDetector(
            onTap: () => _toggleMetric(metric),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isVisible 
                    ? _getMetricColor(metric).withValues(alpha: 0.1)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isVisible 
                      ? _getMetricColor(metric)
                      : const Color(0xFFE2E8F0),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getMetricIcon(metric),
                    size: 16,
                    color: isVisible 
                        ? _getMetricColor(metric)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _getMetricLabel(metric),
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isVisible 
                          ? _getMetricColor(metric)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }

  Widget _buildMainChart() {
    if (_chartData.isEmpty || _visibleMetrics.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            '請至少選擇一個指標',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
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
            '趨勢圖表',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 20,
                  verticalInterval: _selectedTimeRange == TimeRange.day ? 4 : 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFFE2E8F0),
                      strokeWidth: 1,
                    );
                  },
                  getDrawingVerticalLine: (value) {
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
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.notoSansTc(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _selectedTimeRange == TimeRange.day ? 4 
                          : _selectedTimeRange == TimeRange.week ? 1 
                          : _selectedTimeRange == TimeRange.month ? 5 : 2,
                      getTitlesWidget: (value, meta) {
                        String label = '';
                        if (_selectedTimeRange == TimeRange.day) {
                          label = '${value.toInt()}h';
                        } else if (_selectedTimeRange == TimeRange.week) {
                          label = '${value.toInt() + 1}日';
                        } else if (_selectedTimeRange == TimeRange.month) {
                          label = '${value.toInt() + 1}日';
                        } else {
                          label = '${value.toInt() + 1}月';
                        }
                        return Text(
                          label,
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
                lineBarsData: _visibleMetrics.map((metric) {
                  return LineChartBarData(
                    spots: _chartData[metric] ?? [],
                    isCurved: true,
                    color: _getMetricColor(metric),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _getMetricColor(metric).withValues(alpha: 0.1),
                    ),
                  );
                }).toList(),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.white,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final metricIndex = spot.barIndex;
                        final metric = _visibleMetrics.elementAt(metricIndex);
                        return LineTooltipItem(
                          '${_getMetricLabel(metric)}\n${spot.y.toInt()} ${_getMetricUnit(metric)}',
                          GoogleFonts.notoSansTc(
                            color: _getMetricColor(metric),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                minY: 0,
                maxY: 150,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildDataSummary() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: _visibleMetrics.map((metric) {
          final data = _chartData[metric] ?? [];
          final values = data.map((spot) => spot.y).toList();
          final max = values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 0;
          final min = values.isNotEmpty ? values.reduce((a, b) => a < b ? a : b) : 0;
          final avg = values.isNotEmpty ? values.reduce((a, b) => a + b) / values.length : 0;
          
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getMetricIcon(metric),
                      size: 18,
                      color: _getMetricColor(metric),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getMetricLabel(metric),
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${avg.toInt()}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _getMetricColor(metric),
                  ),
                ),
                Text(
                  '最高 ${max.toInt()} | 最低 ${min.toInt()}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}
