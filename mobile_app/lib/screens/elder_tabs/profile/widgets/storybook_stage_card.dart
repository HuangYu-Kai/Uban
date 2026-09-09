import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../pet_companion_studio/models/pet_growth_state.dart';
import '../../../pet_companion_studio/widgets/animated_piglet_actor.dart';
import '../../../pet_companion_studio/widgets/hand_drawn_piglet_actor.dart';
import '../../../pet_companion_studio/widgets/pet_growth_scale_card.dart';
import '../models/pet_mood.dart';
import '../painters/pet_heart_painter.dart';

/// 🐾 溫暖手作繪本厚塗油畫風：小豬夥伴生活舞台卡片
class StorybookStageCard extends StatelessWidget {
  final bool isLandscape;
  final PetMood petMood;
  final double stepProgress;
  final int totalTasks;
  final int completedTasks;
  final PetGrowthState? petGrowthState;
  final String speechText;
  final List<PetHeartParticle> petParticles;
  final VoidCallback onTap;

  const StorybookStageCard({
    super.key,
    this.isLandscape = false,
    required this.petMood,
    required this.stepProgress,
    required this.totalTasks,
    required this.completedTasks,
    this.petGrowthState,
    required this.speechText,
    required this.petParticles,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String moodLabel;
    IconData moodIcon;
    Color moodThemeColor;

    switch (petMood) {
      case PetMood.superHappy:
        moodLabel = (totalTasks > 0 && completedTasks >= totalTasks)
            ? '任務全達標 🎉'
            : (stepProgress >= 1.0 ? '步數達成 👑' : '活力滿分 🌟');
        moodIcon = Icons.stars_rounded;
        moodThemeColor = const Color(0xFFF59E0B);
        break;
      case PetMood.walking:
        moodLabel = '同行漫步中';
        moodIcon = Icons.directions_walk_rounded;
        moodThemeColor = const Color(0xFF0284C7);
        break;
      case PetMood.sleeping:
        moodLabel = '乖乖休息中';
        moodIcon = Icons.bedtime_rounded;
        moodThemeColor = const Color(0xFF8B5CF6);
        break;
      case PetMood.reminding:
        moodLabel = '生活待辦提醒';
        moodIcon = Icons.notifications_active_rounded;
        moodThemeColor = const Color(0xFFF97316);
        break;
      case PetMood.content:
        moodLabel = '元氣陪伴中';
        moodIcon = Icons.favorite_rounded;
        moodThemeColor = const Color(0xFF059669);
        break;
    }

    final currentGrowthState = petGrowthState ??
        const PetGrowthState(
          weightGrams: 28000,
          vitality: 88,
          todaySteps: 3500,
          fedFoodIds: {},
          lastDateStr: '',
          isCrownUnlocked: false,
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: EdgeInsets.all(isLandscape ? 14 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── A. 標頭列：夥伴名稱 ＋ 心情膠囊 ＋ 前往小豬的家標籤 ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🐽', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的元氣小豬夥伴',
                            style: GoogleFonts.notoSansTc(
                              fontSize: isLandscape ? 17 : 18,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF451A03),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // 心情標籤膠囊
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: moodThemeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(moodIcon, size: 13, color: moodThemeColor),
                                const SizedBox(width: 4),
                                Text(
                                  moodLabel,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: moodThemeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 🏡 小豬的家標籤（提示長輩點擊全卡片皆可進入）
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 12 : 14,
                        vertical: isLandscape ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🏡', style: TextStyle(fontSize: 15)),
                          const SizedBox(width: 5),
                          Text(
                            '小豬的家',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: Color(0xFF92400E),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: isLandscape ? 6 : 14),

                // ── B. 核心小豬正面手繪油畫舞台 ──
                IgnorePointer(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // 呼吸背景微暈
                      Container(
                        width: isLandscape ? 120 : 200,
                        height: isLandscape ? 120 : 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              moodThemeColor.withValues(alpha: 0.16),
                              moodThemeColor.withValues(alpha: 0.03),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),

                      // 愛心粒子噴發層（用於生活任務打卡慶祝）
                      if (petParticles.isNotEmpty)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: PetHeartPainter(petParticles),
                          ),
                        ),

                      // 小豬油畫主角與對話氣泡
                      HandDrawnPigletActor(
                        size: isLandscape ? 120 : 195,
                        stage: currentGrowthState.stage,
                        mood: petMood == PetMood.superHappy
                            ? ActorMood.superHappy
                            : (petMood == PetMood.sleeping
                                ? ActorMood.sleeping
                                : (petMood == PetMood.reminding
                                    ? ActorMood.anticipating
                                    : ActorMood.idle)),
                        speechText: speechText,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isLandscape ? 6 : 14),

                // ── C. 體重秤與成長階段卡 ──
                IgnorePointer(
                  child: Center(
                    child: PetGrowthScaleCard(
                      growthState: currentGrowthState,
                      isCompact: isLandscape,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
