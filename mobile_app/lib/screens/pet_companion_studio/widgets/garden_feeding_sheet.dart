import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';

/// 🧺 田園果實食匣半透明抽屜組件
/// - 橫螢幕：從右側滑入 (Right Side-Sheet)
/// - 直螢幕：從底部升起 (Bottom Sheet)
class GardenFeedingSheet extends StatefulWidget {
  final bool isLandscape;
  final Map<String, int> foodInventory;
  final Function(PetFoodItem food) onFeedFood;
  final VoidCallback onClose;

  const GardenFeedingSheet({
    super.key,
    required this.isLandscape,
    required this.foodInventory,
    required this.onFeedFood,
    required this.onClose,
  });

  @override
  State<GardenFeedingSheet> createState() => _GardenFeedingSheetState();
}

class _GardenFeedingSheetState extends State<GardenFeedingSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    // 橫螢幕從右側滑入 (1, 0) -> (0, 0)
    // 直螢幕從底部升起 (0, 1) -> (0, 0)
    _slideAnimation = Tween<Offset>(
      begin: widget.isLandscape ? const Offset(1.0, 0.0) : const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _slideController.forward();
  }

  void _handleClose() {
    HapticFeedback.lightImpact();
    _slideController.reverse().then((_) {
      widget.onClose();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = widget.isLandscape;
    final mediaQuery = MediaQuery.of(context);

    return GestureDetector(
      onTap: _handleClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.18),
        child: Stack(
          children: [
            Align(
              alignment: isLandscape ? Alignment.centerRight : Alignment.bottomCenter,
              child: SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onTap: () {}, // 攔截點擊，避免點擊內容區域關閉
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(32),
                      bottomLeft: isLandscape ? const Radius.circular(32) : Radius.zero,
                      topRight: isLandscape ? Radius.zero : const Radius.circular(32),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        width: isLandscape ? 440 : double.infinity,
                        height: isLandscape
                            ? double.infinity
                            : mediaQuery.size.height * 0.52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(32),
                            bottomLeft: isLandscape ? const Radius.circular(32) : Radius.zero,
                            topRight: isLandscape ? Radius.zero : const Radius.circular(32),
                          ),
                          border: Border.all(
                            color: const Color(0xFFEADBCE),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF78350F).withValues(alpha: 0.14),
                              blurRadius: 28,
                              offset: isLandscape ? const Offset(-8, 0) : const Offset(0, -8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // ── 抽屜頂部標題列 ──
                            _buildHeader(),
                            const Divider(height: 1, color: Color(0xFFF1E6D8)),

                            // ── 食物列表 ──
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                itemCount: PetFoodItem.milestoneMenu.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final food = PetFoodItem.milestoneMenu[index];
                                  final count = widget.foodInventory[food.id] ?? food.initialCount;
                                  final bool canFeed = count > 0 || count == -1;

                                  return _buildFoodCard(food, count, canFeed);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 頂部標題列 ──
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7EFE3),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEADBCE), width: 1.2),
              ),
              child: const Text('🧺', style: TextStyle(fontSize: 22)),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '田園果實食匣',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF451A03),
                  ),
                ),
                Text(
                  '點擊「餵食」或直接拖曳食物給小豬',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF78350F).withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleClose,
            tooltip: '關閉食匣',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2ECE1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5D9C5), width: 1.2),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFF78350F),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // ── 食物卡片（支援拖曳與點擊投餵）──
  Widget _buildFoodCard(PetFoodItem food, int count, bool canFeed) {
    final String countLabel = count == -1 ? '常駐無限' : '剩餘 $count 份';

    final cardContent = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: canFeed ? const Color(0xFFEADBCE) : const Color(0xFFE5E7EB),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: canFeed
                ? const Color(0xFF78350F).withValues(alpha: 0.05)
                : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // 🍎 手繪水彩透明食物圖標
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF7F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1E6D8), width: 1.2),
            ),
            child: Image.asset(
              food.imageAsset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 14),

          // 📝 食物名稱、功效說明與庫存
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      food.name,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: canFeed
                            ? const Color(0xFF451A03)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: food.themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        countLabel,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: food.themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  food.subtitle,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFF78350F).withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '💡 ${food.unlockCondition}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11.5,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // 🔘 投餵按鈕（針對長輩手指友好的大圓角按鈕）
          ElevatedButton(
            onPressed: canFeed
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onFeedFood(food);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              elevation: canFeed ? 2 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              canFeed ? '餵食' : '鎖定',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: canFeed ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );

    if (!canFeed) return cardContent;

    // 可投餵的食物支援直接拖曳到小豬身上的手勢
    return Draggable<PetFoodItem>(
      data: food,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Image.asset(food.imageAsset, fit: BoxFit.contain),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: cardContent),
      child: cardContent,
    );
  }
}
