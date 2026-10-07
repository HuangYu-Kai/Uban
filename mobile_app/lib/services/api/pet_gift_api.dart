import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// ★ 2026-10-07 小豬共養：家屬送給長輩小豬的一種點心。
class PetGiftFood {
  final String id;
  final String name;
  final String emoji;
  final String imageAsset;
  const PetGiftFood(this.id, this.name, this.emoji, this.imageAsset);

  /// 後端 `/pet_gift/options` 目前只有這三種；圖與長輩端小豬食物盒同一批資產。
  static const List<PetGiftFood> defaults = [
    PetGiftFood('carrot', '紅蘿蔔', '🥕', 'assets/images/pet_foods/food_carrot.png'),
    PetGiftFood('apple', '蘋果', '🍎', 'assets/images/pet_foods/food_apple.png'),
    PetGiftFood('cabbage', '高麗菜', '🥬', 'assets/images/pet_foods/food_cabbage.png'),
  ];

  static PetGiftFood? byId(String id) {
    for (final f in defaults) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// 歷史中的一筆點心。
class PetGiftRecent {
  final int giftId;
  final String familyName;
  final String foodId;
  final String foodName;
  final String createdAt;
  final String? fedAt;
  const PetGiftRecent({
    required this.giftId,
    required this.familyName,
    required this.foodId,
    required this.foodName,
    this.createdAt = '',
    this.fedAt,
  });

  bool get fed => fedAt != null && fedAt!.isNotEmpty;

  factory PetGiftRecent.fromJson(Map<dynamic, dynamic> j) {
    String s(String k, [String alt = '']) =>
        (j[k] ?? j[alt] ?? '').toString();
    final fed = (j['fed_at'] ?? j['fedAt'])?.toString();
    return PetGiftRecent(
      giftId: int.tryParse(s('gift_id', 'giftId')) ?? 0,
      familyName: s('familyName', 'family_name'),
      foodId: s('food_id', 'foodId'),
      foodName: s('food_name', 'foodName'),
      createdAt: s('created_at', 'createdAt'),
      fedAt: (fed == null || fed.isEmpty || fed == 'null') ? null : fed,
    );
  }
}

/// `GET /pet_gift/status` 的解析結果。
class PetGiftStatus {
  final int weightGrams;
  final String breed;
  final bool canGiftToday;
  final String? myGiftToday;
  final int elderGiftsToday;
  final int perFamilyPerDay;
  final int perElderPerDay;
  final List<PetGiftRecent> recent;
  const PetGiftStatus({
    required this.weightGrams,
    this.breed = 'pink',
    required this.canGiftToday,
    this.myGiftToday,
    this.elderGiftsToday = 0,
    this.perFamilyPerDay = 1,
    this.perElderPerDay = 3,
    this.recent = const [],
  });

  factory PetGiftStatus.fromJson(Map<dynamic, dynamic> d) {
    final pet = d['pet'] is Map ? d['pet'] as Map : const {};
    final limits = d['limits'] is Map ? d['limits'] as Map : const {};
    final my = d['my_gift_today']?.toString();
    return PetGiftStatus(
      weightGrams: (num.tryParse('${pet['weight_grams'] ?? 0}') ?? 0).round(),
      breed: (pet['breed'] ?? 'pink').toString(),
      canGiftToday: d['can_gift_today'] == true || d['can_gift_today'] == 1,
      myGiftToday: (my == null || my.isEmpty || my == 'null') ? null : my,
      elderGiftsToday: int.tryParse('${d['elder_gifts_today'] ?? 0}') ?? 0,
      perFamilyPerDay: int.tryParse('${limits['per_family_per_day'] ?? 1}') ?? 1,
      perElderPerDay: int.tryParse('${limits['per_elder_per_day'] ?? 3}') ?? 3,
      recent: [
        if (d['recent'] is List)
          for (final e in d['recent'] as List)
            if (e is Map) PetGiftRecent.fromJson(e),
      ],
    );
  }
}

/// 讀取結果：[status] 為 null 且 [notBound] 為 true 表示尚未綁定／沒有小豬；兩者皆否為連線失敗。
class PetGiftStatusResult {
  final PetGiftStatus? status;
  final bool notBound;
  const PetGiftStatusResult({this.status, this.notBound = false});
}

/// 送出結果。[message] 一律是可直接給家屬看的繁體中文。
class PetGiftSendResult {
  final bool ok;
  final String message;
  final int? giftId;
  const PetGiftSendResult(this.ok, this.message, {this.giftId});
}

/// ★ 2026-10-07 小豬共養：家屬端 API（送點心給長輩的小豬）。
class PetGiftApi {
  static const String networkErrorMessage = '目前連不上伺服器，請確認網路後再試一次';

  static Future<PetGiftStatusResult> getStatus({
    required int familyId,
    required String elderId,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiClient.baseUrl}/pet_gift/status'
              '?family_id=$familyId&elder_id=${Uri.encodeQueryComponent(elderId)}'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) return const PetGiftStatusResult(notBound: true);
      if (res.statusCode == 200) {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        final data = d is Map ? d['data'] : null;
        if (data is Map) {
          return PetGiftStatusResult(status: PetGiftStatus.fromJson(data));
        }
      }
      return const PetGiftStatusResult();
    } catch (e) {
      debugPrint('⚠️ [PetGiftApi] getStatus error: $e');
      return const PetGiftStatusResult();
    }
  }

  /// 送點心。400 後端回友善中文（已送過／小豬收太多）直接採用；其餘一律固定中文。
  static Future<PetGiftSendResult> send({
    required int familyId,
    required String elderId,
    required String foodId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pet_gift'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
              'food_id': foodId,
            }),
          )
          .timeout(const Duration(seconds: 20));
      Map<dynamic, dynamic>? decoded;
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map) decoded = d;
      } catch (_) {}
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = decoded?['data'];
        return PetGiftSendResult(true, '已送出',
            giftId: data is Map ? int.tryParse('${data['gift_id']}') : null);
      }
      if (res.statusCode == 404) {
        return const PetGiftSendResult(false, '這位長輩目前沒有和您綁定，無法送點心');
      }
      if (res.statusCode == 400) {
        final m = (decoded?['detail'] ?? decoded?['message'] ?? '').toString().trim();
        if (m.isNotEmpty && RegExp(r'[一-鿿]').hasMatch(m)) {
          return PetGiftSendResult(false, m);
        }
        return const PetGiftSendResult(false, '點心沒有送出，請稍後再試一次');
      }
      return const PetGiftSendResult(false, '送出沒有成功，請稍後再試一次');
    } catch (e) {
      debugPrint('⚠️ [PetGiftApi] send error: $e');
      return const PetGiftSendResult(false, networkErrorMessage);
    }
  }
}
