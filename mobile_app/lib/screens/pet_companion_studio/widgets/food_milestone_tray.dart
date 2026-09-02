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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFEADBCE),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('🥣', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '步數能量美食盤 (長按拖曳或點擊投餵)',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF451A03),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F2E7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5D9C5), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🐾', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      '今日 $currentSteps 步',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF78350F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 8 階美食橫向滑動盤
          SizedBox(
            height: 176,
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
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isUnlocked
            ? (isFed ? const Color(0xFFF9FAF7) : Colors.white)
            : const Color(0xFFF5EFEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isUnlocked
              ? (isFed
                  ? const Color(0xFFE2E8F0)
                  : item.themeColor.withValues(alpha: 0.55))
              : const Color(0xFFE8DFD8),
          width: isUnlocked && !isFed ? 2.0 : 1.2,
        ),
        boxShadow: isUnlocked && !isFed
            ? [
                BoxShadow(
                  color: item.themeColor.withValues(alpha: 0.16),
                  blurRadius: 12,
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
                      ? item.themeColor.withValues(alpha: 0.14)
                      : const Color(0xFFE7DFD5),
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
                      color: Color(0xFF059669),
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
                      color: Color(0xFF94A3B8),
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
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isUnlocked
                  ? (isFed ? const Color(0xFF94A3B8) : const Color(0xFF451A03))
                  : const Color(0xFF94A3B8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 5),

          // 增重回饋與步數標籤
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
                          : const Color(0xFFE7DFD5)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isFed ? '已飽足' : '${item.stepMilestone}步',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isFed
                        ? const Color(0xFF059669)
                        : (isUnlocked ? item.themeColor : const Color(0xFF78716C)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${item.weightGainGrams}g',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFB45309),
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
          scale: 1.18,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              shape: BoxShape.circle,
              border: Border.all(color: item.themeColor, width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: item.themeColor.withValues(alpha: 0.35),
                  blurRadius: 18,
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
