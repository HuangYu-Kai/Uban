import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 高級健康儀表板卡片組件
/// 顯示長者的健康指標、活動趨勢和實時數據
class HealthDashboardCard extends StatefulWidget {
  final String elderName;
  final Map<String, dynamic>? healthData;
  final VoidCallback? onRefresh;

  const HealthDashboardCard({
    super.key,
    required this.elderName,
    this.healthData,
    this.onRefresh,
  });

  @override
  State<HealthDashboardCard> createState() => _HealthDashboardCardState();
}

class _HealthDashboardCardState extends State<HealthDashboardCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _waveController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.1),
            const Color(0xFF764BA2).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with pulse indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.elderName} 的健康狀態',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '實時監測中',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                _buildPulseIndicator(),
              ],
            ),
            const SizedBox(height: 20),

            // Health metrics grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _buildMetricCard(
                  icon: Icons.favorite,
                  label: '心率',
                  value: '${_getHeartRate()} BPM',
                  status: 'normal',
                  color: const Color(0xFFEF4444),
                ),
                _buildMetricCard(
                  icon: Icons.directions_walk,
                  label: '步數',
                  value: '${_getSteps()}',
                  status: 'good',
                  color: const Color(0xFF10B981),
                ),
                _buildMetricCard(
                  icon: Icons.local_fire_department,
                  label: '卡路里',
                  value: '${_getCalories()} kcal',
                  status: 'normal',
                  color: const Color(0xFFF59E0B),
                ),
                _buildMetricCard(
                  icon: Icons.bedtime,
                  label: '睡眠品質',
                  value: '${_getSleepQuality()}%',
                  status: _getSleepQuality() > 75 ? 'good' : 'normal',
                  color: const Color(0xFF6366F1),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Activity trend chart
            _buildActivityChart(),
            const SizedBox(height: 20),

            // Wellness tips
            _buildWellnessTips(),
          ],
        ),
      ),
    ).animate().fade(duration: 600.ms).slideY(begin: 0.2);
  }

  Widget _buildPulseIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEF4444)
                      .withOpacity(1 - _pulseController.value),
                  width: 2,
                ),
              ),
            ),
            // Middle pulse ring
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEF4444)
                      .withOpacity(1 - (_pulseController.value * 0.6)),
                  width: 1.5,
                ),
              ),
            ),
            // Center dot
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEF4444),
              ),
              child: const Icon(
                Icons.favorite,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String status,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              _buildStatusBadge(status),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().scale(delay: 100.ms, duration: 500.ms);
  }

  Widget _buildStatusBadge(String status) {
    final color = status == 'good' ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        status == 'good' ? '良好' : '正常',
        style: GoogleFonts.notoSansTc(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActivityChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '活動趨勢 (7 天)',
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: BarChart(
            BarChartData(
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      const days = ['一', '二', '三', '四', '五', '六', '日'];
                      return Text(
                        days[value.toInt()],
                        style: GoogleFonts.notoSansTc(
                          fontSize: 10,
                          color: const Color(0xFF94A3B8),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(7, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: 30 + (i * 8).toDouble(),
                      color: const Color(0xFF667EEA),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                      width: 8,
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWellnessTips() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.lightbulb,
              color: Color(0xFF10B981),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '健康建議',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '建議增加戶外活動時間，有利身心健康',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mock data methods - replace with real API calls
  int _getHeartRate() {
    return widget.healthData?['heart_rate'] ?? 72;
  }

  int _getSteps() {
    return widget.healthData?['steps'] ?? 4250;
  }

  int _getCalories() {
    return widget.healthData?['calories'] ?? 320;
  }

  int _getSleepQuality() {
    return widget.healthData?['sleep_quality'] ?? 82;
  }
}

