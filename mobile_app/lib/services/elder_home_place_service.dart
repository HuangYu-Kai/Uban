import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/elder_place.dart';
import 'api/location_api.dart';

/// 長輩端「帶我回家」用的「家」地點：本機快取 + 背景同步 + 開啟導航。
///
/// 快取的目的是離線／網路慢時仍能立刻顯示按鈕——長輩迷路時通常也是訊號最差的時候。
/// 所有方法都是靜態、不拋例外（失敗時回傳 `null`／`false`）。
class ElderHomePlaceService {
  ElderHomePlaceService._();

  /// SharedPreferences 鍵：存 `{"elder_id": ..., "place": [ElderPlace.toJson]}` 的 JSON 字串。
  ///
  /// v2 起連同 elder_id 一起存——同一支手機切換長輩帳號時，不能把前一位長輩的家
  /// 顯示給下一位。
  static const String cacheKey = 'elder_home_place_v2';

  /// 舊版（v1，未記錄 elder_id）的鍵；讀取或寫入 v2 時一併清除，避免殘留。
  static const String legacyCacheKey = 'elder_home_place_v1';

  /// 讀取本機快取的「家」；沒有快取、內容損毀，或快取屬於其他長輩時回傳 `null`。
  static Future<ElderPlace?> loadCached({required String elderId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(legacyCacheKey)) await prefs.remove(legacyCacheKey);
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['elder_id']?.toString() != elderId) return null;
      final place = decoded['place'];
      if (place is! Map) return null;
      return ElderPlace.fromJson(Map<String, dynamic>.from(place));
    } catch (e) {
      debugPrint('⚠️ ElderHomePlaceService.loadCached error: $e');
      return null;
    }
  }

  /// 向後端抓最新地點清單並更新快取，回傳目前的「家」（沒有則 `null`）。
  ///
  /// - 抓取成功且有 `is_home` 地點 → 以該 [elderId] 覆寫快取；成功但沒有 → 清除快取
  ///   （家屬可能已刪除）。
  /// - 抓取失敗（離線、無權限）→ 保留既有快取不動，回傳該長輩的快取內容。
  static Future<ElderPlace?> refresh({
    required String elderId,
    required int userId,
  }) async {
    final places = await LocationApi.getPlaces(elderId: elderId, userId: userId);
    if (places == null) return loadCached(elderId: elderId);
    ElderPlace? home;
    for (final p in places) {
      if (p.isHome) {
        home = p;
        break;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(legacyCacheKey);
      if (home == null) {
        await prefs.remove(cacheKey);
      } else {
        await prefs.setString(
          cacheKey,
          jsonEncode({'elder_id': elderId, 'place': home.toJson()}),
        );
      }
    } catch (e) {
      debugPrint('⚠️ ElderHomePlaceService.refresh cache error: $e');
    }
    return home;
  }

  /// Google 地圖「步行導航到 [home]」的網址。
  static Uri navigationUri(ElderPlace home) => Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${home.latitude},${home.longitude}&travelmode=walking',
      );

  /// 以外部 App（Google 地圖）開啟導航；無法開啟回傳 `false`。
  static Future<bool> openNavigation(ElderPlace home) async {
    try {
      return await launchUrl(
        navigationUri(home),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('⚠️ ElderHomePlaceService.openNavigation error: $e');
      return false;
    }
  }
}
