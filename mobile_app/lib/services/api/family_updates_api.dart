import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ★ 2026-10-07 家人分享轉述：家人貼的分享（文字＋照片）與小豬點心，由小嘎在
/// 長輩聊天裡轉述。後端 `GET /ai/family_updates/{id}/opening` 組好開場白，
/// 聊天頁真的顯示出來之後才 `POST .../relayed` 標記（一則只轉述一次）。
class FamilyOpening {
  /// 小嘎要說的話。
  final String message;

  /// 照片網址（可能是相對路徑，顯示前用 [ElderFamilyUpdatesApi.imageUrl] 轉完整）。
  final List<String> images;

  /// 這次轉述涵蓋的項目（`{kind, item_id}`），原樣回傳給 relayed。
  final List<Map<String, dynamic>> items;

  const FamilyOpening({
    required this.message,
    this.images = const [],
    this.items = const [],
  });

  /// 解析 opening 回應；`message` 為 null／空白（沒有要轉述的）或格式不合回傳 null。
  static FamilyOpening? tryParse(dynamic res) {
    if (res is! Map || res['status'] != 'success') return null;
    final data = res['data'];
    if (data is! Map) return null;
    final msg = (data['message'] ?? '').toString().trim();
    if (msg.isEmpty || msg == 'null') return null;
    final images = <String>[];
    final rawImages = data['images'];
    if (rawImages is List) {
      for (final u in rawImages) {
        final s = (u ?? '').toString().trim();
        if (s.isNotEmpty && s != 'null') images.add(s);
      }
    }
    final items = <Map<String, dynamic>>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map) items.add(Map<String, dynamic>.from(it));
      }
    }
    return FamilyOpening(message: msg, images: images, items: items);
  }
}

/// ★ 2026-10-07 家人分享轉述（長輩端）API 層。所有失敗一律回 null／false，不丟例外。
class ElderFamilyUpdatesApi {
  /// App 內訊號：Socket `family-share-new` 抵達且聊天分頁正開著 → 外殼遞增，
  /// 聊天頁監聽後立刻重取 opening（不放進 Signaling，避免顯示狀態旗標）。
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  /// 讀開場白；沒有要轉述的、或失敗都回 null。[elderId] 可用 4 碼 elder_id 或 user_id。
  static Future<FamilyOpening?> fetchOpening(Object elderId) async {
    try {
      final res =
          await ApiClient.get('/ai/family_updates/$elderId/opening');
      return FamilyOpening.tryParse(res);
    } catch (e) {
      debugPrint('⚠️ ElderFamilyUpdatesApi.fetchOpening error: $e');
      return null;
    }
  }

  /// 通知後端「已經顯示給長輩了」。成功 true；失敗 false（下次開聊天會再轉述一次）。
  static Future<bool> markRelayed(
      Object elderId, FamilyOpening opening) async {
    try {
      final res = await ApiClient.post(
        '/ai/family_updates/$elderId/relayed',
        {'message': opening.message, 'items': opening.items},
      );
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ ElderFamilyUpdatesApi.markRelayed error: $e');
      return false;
    }
  }

  /// 相對路徑（`/uploads/...`）補成完整網址；已是 http(s) 原樣回傳。
  static String imageUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiClient.serverRootUrl}${path.startsWith('/') ? '' : '/'}$path';
  }
}
