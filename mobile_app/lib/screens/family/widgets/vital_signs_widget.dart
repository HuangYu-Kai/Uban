import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 💓 實時生命徵象 Widget
/// 
/// 顯示心率、步數、卡路里等生命徵象，使用動畫表達數據變化
class VitalSignsWidget extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const VitalSignsWidget({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<VitalSignsWidget> createState() => _VitalSignsWidgetState();
}

class _VitalSignsWidgetState extends State<VitalSignsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartbeatController;
  
  int _heartRate = 72;
  int _steps = 5234;
  int _calories = 420;
  double _sleepHours = 7.2;

  @override
  void initState() {
    super.initState();
    _heartbeatController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    
    _loadVitalSigns();
  }

  @override
  void dispose() {
    _heartbeatController.dispose();
    super.dispose();
  }

  Future<void> _loadVitalSigns() async {
    // TODO: 從 API 加載真實生命徵象數據
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _heartRate = 72;
      _steps = 5234;
      _calories = 420;
      _sleepHours = 7.2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedBuilder(
                  animation: _heartbeatController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (_heartbeatController.value * 0.15),
                      child: const Icon(
                        Icons.favorite,
                        color: Color(0xFFEF4444),
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '實時生命徵象',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ).animate(onPlay: (controller) => controller.repeat())
                      .fade(duration: 1500.ms, begin: 0.3, end: 1.0)
                      .then()
                      .fade(duration: 1500.ms, begin: 1.0, end: 0.3),
                    const SizedBox(width: 6),
                    Text(
                      '正常',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 生命徵象數據網格
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _buildMetricCard(
                icon: Icons.favorite,
                label: '心率',
                value: _heartRate.toString(),
                unit: 'bpm',
                color: const Color(0xFFEF4444),
                isAnimated: true,
              ),
              _buildMetricCard(
                icon: Icons.directions_walk,
                label: '步數',
                value: _steps.toString(),
                unit: '步',
                color: const Color(0xFF10B981),
              ),
              _buildMetricCard(
                icon: Icons.local_fire_department,
                label: '卡路里',
                value: _calories.toString(),
                unit: 'kcal',
                color: const Color(0xFFF59E0B),
              ),
              _buildMetricCard(
                icon: Icons.bed,
                label: '睡眠',
                value: _sleepHours.toStringAsFixed(1),
                unit: '小時',
                color: const Color(0xFF8B5CF6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
    bool isAnimated = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.notoSansTc(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
