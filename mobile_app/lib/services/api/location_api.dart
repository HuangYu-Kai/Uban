import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// 戶外 GPS 定位與每日移動軌跡 API。
///
/// 與 IPS（攝影機式室內房間定位）是完全不同的子系統，不要混用。
/// 對應後端 `Uban-api/routers/location.py`。
class LocationApi {
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
  /// 回傳 `{sharing_enabled, date, points: [...]}`，查無權限時回傳 `null`。
  static Future<Map<String, dynamic>?> getTrail({
    required String elderId,
    required int userId,
    DateTime? date,
  }) async {
    final dateStr = date != null
        ? '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : null;
    final path = '/location/trail/$elderId?user_id=$userId'
        '${dateStr != null ? '&date=$dateStr' : ''}';
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
