import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ★ 2026-10-07 小豬共養：家人送給小豬的點心（長輩端）。
class PetGift {
  final int giftId;
  final String familyName;
  final String foodId;
  final String foodName;
  final String? createdAt;

  const PetGift({
    required this.giftId,
    required this.familyName,
    required this.foodId,
    required this.foodName,
    this.createdAt,
  });

  static String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  /// 格式不合（沒有 giftId、或食物 id 空白）回傳 null。
  static PetGift? tryParse(dynamic m) {
    if (m is! Map) return null;
    final id = int.tryParse((m['giftId'] ?? m['gift_id'] ?? '').toString());
    final foodId = _nz(m['foodId'] ?? m['food_id']);
    if (id == null || foodId == null) return null;
    return PetGift(
      giftId: id,
      familyName: _nz(m['familyName'] ?? m['family_name']) ?? '家人',
      foodId: foodId,
      foodName: _nz(m['foodName'] ?? m['food_name']) ?? '點心',
      createdAt: _nz(m['createdAt'] ?? m['created_at']),
    );
  }

  /// 小嘎關懷訊息：「璿OwO 送了一份「蜜糖紅蘋果」給小豬，快去餵牠吧！」
  String get careMessage => '$familyName 送了一份「$foodName」給小豬，快去餵牠吧！';
}

/// 橫幅文字：最多列 3 份「🍎 蜜糖紅蘋果（璿OwO）」，多於 3 份加「等 N 份」。
/// [emojiOf] 由呼叫端提供食物 id → emoji（查不到用 🍎 以外的通用 🎁）。
String petGiftBannerText(List<PetGift> gifts,
    {String Function(String foodId)? emojiOf}) {
  if (gifts.isEmpty) return '';
  final shown = gifts.take(3).map((g) {
    final e = emojiOf?.call(g.foodId) ?? '🎁';
    return '$e ${g.foodName}（${g.familyName}）';
  }).join('、');
  final more = gifts.length > 3 ? ' 等 ${gifts.length} 份' : '';
  return '家人送的點心：$shown$more';
}

/// ★ 2026-10-07 小豬共養（長輩端）API 層。
///
/// 禮物同時已進 elder_food_grant（食物庫存自然 +1），本層只負責「還沒餵的禮物」
/// 清單，不動食物經濟；長輩照常餵食，後端自動標記並通知送禮的家人。
class ElderPetGiftApi {
  /// 尚未餵的家人禮物（最舊在前）。
  static final ValueNotifier<List<PetGift>> unfed =
      ValueNotifier<List<PetGift>>(const []);

  /// 底部導覽「小豬」小紅點：unfed 至少一份。
  static final ValueNotifier<bool> hasUnfed = ValueNotifier<bool>(false);

  /// 讀 GET /pet_gift/elder/{id}/unfed。失敗（網路／非 success）保留前一個值。
  static Future<void> refresh(Object elderId) async {
    try {
      final res = await ApiClient.get('/pet_gift/elder/$elderId/unfed');
      if (res == null || res['status'] != 'success') return;
      final raw = res['data'] is Map ? res['data']['items'] : null;
      final list = <PetGift>[];
      if (raw is List) {
        for (final m in raw) {
          final g = PetGift.tryParse(m);
          if (g != null) list.add(g);
        }
      }
      unfed.value = List.unmodifiable(list);
      hasUnfed.value = list.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ ElderPetGiftApi.refresh error: $e');
    }
  }

  /// App 內刷新訊號：Socket `pet-gift`、餵食成功後遞增，外殼監聽後重讀。
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);
}
