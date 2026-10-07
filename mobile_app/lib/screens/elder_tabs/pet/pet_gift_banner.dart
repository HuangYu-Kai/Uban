import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../services/api/elder_pet_gift_api.dart';
import '../../pet_companion_studio/models/pet_food_item.dart';

/// ★ 2026-10-07 小豬共養：小豬分頁餵食區上方的「家人送的點心」橫幅。
///
/// 監聽 [ElderPetGiftApi.unfed]，沒有未餵禮物時不佔空間。長輩大字（18）、
/// 文字可換行、不設固定高度，360 寬 + 放大字級也不會溢出。
class PetGiftBanner extends StatelessWidget {
  /// 測試可注入；預設用全域 [ElderPetGiftApi.unfed]。
  final ValueListenable<List<PetGift>>? listenable;

  /// 點「餵牠吃」：餵這一份禮物。null 時不顯示按鈕。
  final void Function(PetGift gift)? onFeed;
  const PetGiftBanner({super.key, this.listenable, this.onFeed});

  static String _emojiOf(String foodId) {
    for (final f in PetFoodItem.milestoneMenu) {
      if (f.id == foodId) return f.emoji;
    }
    return '🎁';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PetGift>>(
      valueListenable: listenable ?? ElderPetGiftApi.unfed,
      builder: (context, gifts, _) {
        if (gifts.isEmpty) return const SizedBox.shrink();
        final label = petGiftBannerText(gifts, emojiOf: _emojiOf);
        const textStyle = TextStyle(
          fontSize: 18,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9F1239),
        );
        return Container(
          key: const ValueKey('pet_gift_banner'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFECDD3), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: label,
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🎁', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('家人送的點心', style: textStyle)),
                  ],
                ),
              ),
              for (final g in gifts.take(3)) ...[
                const SizedBox(height: 8),
                Text('${_emojiOf(g.foodId)} ${g.foodName}（${g.familyName}）',
                    style: textStyle),
                if (onFeed != null) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: ValueKey('pet_gift_feed_${g.giftId}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => onFeed!(g),
                      child: const Text('餵牠吃'),
                    ),
                  ),
                ],
              ],
              if (gifts.length > 3) ...[
                const SizedBox(height: 8),
                Text('等 ${gifts.length} 份', style: textStyle),
              ],
            ],
          ),
        );
      },
    );
  }
}
