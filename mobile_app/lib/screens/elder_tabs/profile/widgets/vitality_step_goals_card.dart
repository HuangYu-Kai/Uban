import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// 🎯 今日健康活力雙環 ＆ 四合一指標卡片
class VitalityStepGoalsCard extends StatelessWidget {
  final double progress;
  final int currentSteps;
  final int dailyStepGoal;
  final double totalDistance;
  final Set<int> completedReminderIds;
  final bool isLandscape;

  const VitalityStepGoalsCard({
    super.key,
    required this.progress,
    required this.currentSteps,
    required this.dailyStepGoal,
    required this.totalDistance,
    required this.completedReminderIds,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 14 : 20,
        vertical: isLandscape ? 10 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 今日健康活力指標 Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Text('🎯', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Text(
                '今日健康活力雙環',
                style: GoogleFonts.notoSansTc(
                  fontSize: isLandscape ? 16 : 17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF451A03),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 8 : 10,
                  vertical: isLandscape ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EBE1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '目標 $dailyStepGoal 步',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 11.5 : 12.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF78350F),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: isLandscape ? 8 : 16),

          // ── 步數大圓環 ＋ 4-in-1 健康指標 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 步數圓環
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: isLandscape ? 72 : 110,
                    height: isLandscape ? 72 : 110,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: isLandscape ? 6.5 : 10,
                      backgroundColor: const Color(0xFFF1EBE1),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Color(0xFF59B294)),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '今日步數',
                        style: GoogleFonts.notoSansTc(
                          fontSize: isLandscape ? 10 : 12,
                          color: const Color(0xFF8C6D58),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        NumberFormat('#,###').format(currentSteps),
                        style: GoogleFonts.inter(
                          fontSize: isLandscape ? 16 : 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF451A03),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}% 達成',
                        style: GoogleFonts.notoSansTc(
                          fontSize: isLandscape ? 9.5 : 11.5,
                          color: const Color(0xFF59B294),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SizedBox(width: isLandscape ? 10 : 14),

              // 4-in-1 指標格
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StorybookStatTile(
                            icon: Icons.directions_walk_rounded,
                            iconColor: const Color(0xFF0284C7),
                            label: '步行距離',
                            value: '${totalDistance.toStringAsFixed(2)} 公里',
                            isLandscape: isLandscape,
                          ),
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                        Expanded(
                          child: StorybookStatTile(
                            icon: Icons.local_fire_department_rounded,
                            iconColor: const Color(0xFFF97316),
                            label: '消耗熱量',
                            value: '${(totalDistance * 60).toInt()} 千卡',
                            isLandscape: isLandscape,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isLandscape ? 4 : 8),
                    Row(
                      children: [
                        Expanded(
                          child: StorybookStatTile(
                            icon: Icons.timer_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            label: '活動時間',
                            value:
                                '${(totalDistance > 0 ? (totalDistance / 3.2 * 60).toInt() : (currentSteps ~/ 100)).clamp(0, 180)} 分鐘',
                            isLandscape: isLandscape,
                          ),
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                        Expanded(
                          child: StorybookStatTile(
                            icon: Icons.water_drop_rounded,
                            iconColor: const Color(0xFF06B6D4),
                            label: '溫水補充',
                            value: completedReminderIds.contains(102)
                                ? '1,000 毫升'
                                : '500 毫升',
                            isLandscape: isLandscape,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 繪本風格健康指標小磁磚
class StorybookStatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isLandscape;

  const StorybookStatTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 8 : 10,
        vertical: isLandscape ? 4.5 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(isLandscape ? 14 : 16),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isLandscape ? 4 : 6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: isLandscape ? 15 : 18),
          ),
          SizedBox(width: isLandscape ? 5 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 10 : 11.5,
                    color: const Color(0xFF78350F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: isLandscape ? 12 : 14.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF451A03),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
