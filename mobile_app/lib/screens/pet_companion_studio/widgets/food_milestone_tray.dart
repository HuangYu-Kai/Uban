import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';

class FoodMilestoneTray extends StatelessWidget {
  final int currentSteps;
  final Function(PetFoodItem food) onSelectFood;
  final Set<String> fedFoodIds;

  const FoodMilestoneTray({
    super.key,
    required this.currentSteps,
    required this.onSelectFood,
    required this.fedFoodIds,
  });

  @override
  Widget build(BuildContext context) {
    final foods = PetFoodItem.milestoneMenu;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題欄
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF59B294).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      color: Color(0xFF059669),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '步數能量美食盤 (長按拖曳或點擊餵食)',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '今日步數: $currentSteps 步',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 8 階美食橫向滑動盤 (大觸控卡片)
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: foods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = foods[index];
                final bool isUnlocked = currentSteps >= item.stepMilestone;
                final bool isFed = fedFoodIds.contains(item.id);

                return _buildFoodCard(context, item, isUnlocked, isFed);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodCard(
    BuildContext context,
    PetFoodItem item,
    bool isUnlocked,
    bool isFed,
  ) {
    final Widget cardContent = Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isUnlocked
            ? (isFed ? const Color(0xFFF8FAFC) : Colors.white)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isUnlocked
              ? (isFed
                  ? const Color(0xFFE2E8F0)
                  : item.themeColor.withValues(alpha: 0.45))
              : const Color(0xFFE2E8F0),
          width: isUnlocked && !isFed ? 2.2 : 1.2,
        ),
        boxShadow: isUnlocked && !isFed
            ? [
                BoxShadow(
                  color: item.themeColor.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 食物 Emoji 圖示
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? item.themeColor.withValues(alpha: 0.12)
                      : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    item.emoji,
                    style: TextStyle(
                      fontSize: 32,
                      color: isUnlocked ? null : Colors.grey,
                    ),
                  ),
                ),
              ),
              if (isFed)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (!isUnlocked)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: const BoxDecoration(
                      color: Color(0xFF64748B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // 食物名稱
          Text(
            item.name,
            style: GoogleFonts.notoSansTc(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: isUnlocked
                  ? (isFed ? const Color(0xFF94A3B8) : const Color(0xFF0F172A))
                  : const Color(0xFF94A3B8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          // 增重回饋與步數狀態
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isFed
                      ? const Color(0xFFECFDF5)
                      : (isUnlocked
                          ? item.themeColor.withValues(alpha: 0.12)
                          : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isFed
                      ? '已飽足'
                      : (isUnlocked ? '${item.stepMilestone}步' : '${item.stepMilestone}步'),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isFed
                        ? const Color(0xFF059669)
                        : (isUnlocked ? item.themeColor : const Color(0xFF64748B)),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${item.weightGainGrams}g',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFE11D48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!isUnlocked || isFed) {
      return Opacity(
        opacity: isFed ? 0.75 : 0.55,
        child: cardContent,
      );
    }

    // 可拖曳或點擊 (長按可拖曳投餵，短按直接餵食)
    return LongPressDraggable<PetFoodItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.15,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: item.themeColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              item.emoji,
              style: const TextStyle(fontSize: 44),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: cardContent,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelectFood(item),
        child: cardContent,
      ),
    );
  }
}
