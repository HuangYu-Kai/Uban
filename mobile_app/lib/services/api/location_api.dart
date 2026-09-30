import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// 戶外 GPS 定位與每日移動軌跡 API。
///
/// 與 IPS（攝影機式室內房間定位）是完全不同的子系統，不要混用。
/// 對應後端 `Uban-api/routers/location.py`。
class LocationApi {
  /// 解析後端回傳的 `recorded_at`，轉成裝置本地時間。
  ///
  /// 後端存的是 UTC；若字串沒有時區標記（舊版後端不帶 `Z`），`DateTime.parse`
  /// 會把它當成本地時間，台灣就會固定差 8 小時——所以缺時區時一律補 `Z`。
  static DateTime? parseRecordedAt(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    final normalized = hasZone ? raw : '${raw.replaceFirst(' ', 'T')}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  /// 長輩裝置回報一筆 GPS 座標。
  static Future<bool> sendPing({
    required String elderId,
    required int userId,
    required double latitude,
    required double longitude,
    double? accuracyM,
    DateTime? recordedAt,
  }) async {
    try {
      final result = await ApiClient.post('/location/ping/$elderId', {
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        'recorded_at': (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
      });
      return result != null && result['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ LocationApi.sendPing error: $e');
      return false;
    }
  }

  /// 家屬（或長輩本人）讀取最新一筆位置。
  /// 回傳 `{sharing_enabled, point: {latitude, longitude, accuracy_m, recorded_at}?, stale_after_ms}`，
  /// 查無權限（未配對）時回傳 `null`。
  static Future<Map<String, dynamic>?> getCurrentLocation({
    required String elderId,
    required int userId,
  }) async {
    final result = await ApiClient.get('/location/current/$elderId?user_id=$userId');
    if (result != null && result['status'] == 'success') {
      return result['data'] as Map<String, dynamic>;
    }
    return null;
  }

  /// 家屬（或長輩本人）讀取指定日期（省略則今天）的完整移動軌跡。
  /// 回傳 `{sharing_enabled, date, points: [...], cursor}`，查無權限時回傳 `null`。
  ///
  /// 增量查詢：帶 [sinceId]（上一次回應的 `cursor`）時，後端只回傳 `id > sinceId`
  /// 的新點；`cursor` 為本次回傳列的最大 id，沒有新點則原樣回傳 [sinceId]（未帶為 0）。
  /// 游標刻意用資料列 id 而非時間——避開時區問題，也能撈到離線佇列補傳、
  /// `recorded_at` 很舊的點。
  static Future<Map<String, dynamic>?> getTrail({
    required String elderId,
    required int userId,
    DateTime? date,
    int? sinceId,
  }) async {
    final dateStr = date != null
        ? '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : null;
    // 「某一天」是裝置本地的一天，帶上時區偏移讓後端換算成 UTC 區間。
    final tzOffset = (date ?? DateTime.now()).timeZoneOffset.inMinutes;
    final path = '/location/trail/$elderId?user_id=$userId&tz_offset=$tzOffset'
        '${dateStr != null ? '&date=$dateStr' : ''}'
        '${sinceId != null ? '&since_id=$sinceId' : ''}';
    final result = await ApiClient.get(path);
    if (result != null && result['status'] == 'success') {
      return result['data'] as Map<String, dynamic>;
    }
    return null;
  }

  /// 長輩本人讀取自己目前的分享開關狀態。
  static Future<bool?> getSharingEnabled({
    required String elderId,
    required int userId,
  }) async {
    final result = await ApiClient.get('/location/sharing/$elderId?user_id=$userId');
    if (result != null && result['status'] == 'success') {
      return result['data']?['location_sharing_enabled'] as bool?;
    }
    return null;
  }

  /// 長輩本人切換分享開關。
  static Future<bool> setSharingEnabled({
    required String elderId,
    required int userId,
    required bool enabled,
  }) async {
    try {
      final result = await ApiClient.put('/location/sharing/$elderId', {
        'user_id': userId,
        'enabled': enabled,
      });
      return result != null && result['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ LocationApi.setSharingEnabled error: $e');
      return false;
    }
  }
}
