import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/elder_place.dart';
import 'api_client.dart';

/// 戶外 GPS 定位與每日移動軌跡 API。
///
/// 與 IPS（攝影機式室內房間定位）是完全不同的子系統，不要混用。
/// 對應後端 `Uban-api/routers/location.py`。
class LocationApi {
  /// 日期格式化成後端要的 `YYYY-MM-DD`（裝置本地日期）。
  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

  /// 長輩裝置回報「手機定位權限／定位服務」目前的狀態，讓家屬端看得到
  /// 「為什麼沒有位置」（而不是只看到一片空白）。
  ///
  /// [status] 必須是 `ok | permission_denied | permission_denied_forever |
  /// service_disabled | foreground_only`（見 `LocationDeviceStatus`）。
  /// 只有長輩本人可以呼叫；任何失敗一律回傳 `false`、不拋例外——這是
  /// 輔助資訊，絕不能影響定位本身。
  static Future<bool> reportDeviceStatus({
    required String elderId,
    required int userId,
    required String status,
  }) async {
    try {
      final result = await ApiClient.post('/location/device-status/$elderId', {
        'user_id': userId,
        'status': status,
      });
      return result != null && result['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ LocationApi.reportDeviceStatus error: $e');
      return false;
    }
  }

  /// 家屬（或長輩本人）讀取最新一筆位置。
  /// 回傳 `{sharing_enabled, point: {latitude, longitude, accuracy_m, recorded_at}?, stale_after_ms,
  /// device_status?, device_status_at?}`（後兩者僅在分享開啟時出現，`device_status_at` 帶 `Z`，
  /// 須經 [parseRecordedAt] 解析），
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
    final dateStr = date != null ? _formatDate(date) : null;
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

  /// 家屬（或長輩本人）讀取最近 [days] 天（7 或 30）的每日外出摘要，供「外出趨勢」畫面使用。
  /// 回傳 `{sharing_enabled}`（關閉分享時只有這一欄），或
  /// `{sharing_enabled: true, has_home, days: [{date, distance_m, outing_count, outside_minutes, point_count}]}`；
  /// `days` 由舊到新、剛好 [days] 筆、最後一筆是今天（統計中，非完整一天）。
  /// 沒設定「家」時 `outing_count`／`outside_minutes` 為 `null`。查無權限或請求失敗回傳 `null`。
  static Future<Map<String, dynamic>?> getDaily({
    required String elderId,
    required int userId,
    int days = 7,
  }) async {
    try {
      // 「每一天」是裝置本地的一天，帶上時區偏移讓後端換算成 UTC 區間。
      final tzOffset = DateTime.now().timeZoneOffset.inMinutes;
      final result = await ApiClient.get(
        '/location/daily/$elderId?user_id=$userId&days=$days&tz_offset=$tzOffset',
      );
      if (result != null && result['status'] == 'success') {
        return result['data'] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ LocationApi.getDaily error: $e');
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

  /// 讀取長輩的常去地點清單（長輩本人或已配對家屬；不受位置分享開關限制）。
  /// 失敗（含無權限）回傳 `null`；成功但沒有任何地點回傳空清單。
  static Future<List<ElderPlace>?> getPlaces({
    required String elderId,
    required int userId,
  }) async {
    try {
      final result = await ApiClient.get('/location/places/$elderId?user_id=$userId');
      if (result != null && result['status'] == 'success') {
        final raw = result['data']?['places'];
        if (raw is! List) return const [];
        final places = <ElderPlace>[];
        for (final p in raw) {
          if (p is! Map) continue;
          try {
            places.add(ElderPlace.fromJson(Map<String, dynamic>.from(p)));
          } catch (e) {
            // 單筆壞資料略過，不讓整份清單失效。
            debugPrint('⚠️ LocationApi.getPlaces skip invalid place: $e');
          }
        }
        return places;
      }
    } catch (e) {
      debugPrint('⚠️ LocationApi.getPlaces error: $e');
    }
    return null;
  }

  /// 家屬新增地點。成功回傳後端建立的 [ElderPlace]，失敗回傳 `null`。
  static Future<ElderPlace?> createPlace({
    required String elderId,
    required int userId,
    required String name,
    required double latitude,
    required double longitude,
    int? radiusM,
    bool? isHome,
  }) async {
    try {
      final result = await ApiClient.post('/location/places/$elderId', {
        'user_id': userId,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        if (radiusM != null) 'radius_m': radiusM,
        if (isHome != null) 'is_home': isHome,
      });
      return _parsePlace(result);
    } catch (e) {
      debugPrint('⚠️ LocationApi.createPlace error: $e');
      return null;
    }
  }

  /// 家屬修改地點（只送有傳入的欄位）。成功回傳更新後的 [ElderPlace]，失敗回傳 `null`。
  static Future<ElderPlace?> updatePlace({
    required String elderId,
    required int placeId,
    required int userId,
    String? name,
    double? latitude,
    double? longitude,
    int? radiusM,
    bool? isHome,
  }) async {
    try {
      final result = await ApiClient.put('/location/places/$elderId/$placeId', {
        'user_id': userId,
        if (name != null) 'name': name,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (radiusM != null) 'radius_m': radiusM,
        if (isHome != null) 'is_home': isHome,
      });
      return _parsePlace(result);
    } catch (e) {
      debugPrint('⚠️ LocationApi.updatePlace error: $e');
      return null;
    }
  }

  /// 家屬刪除地點。成功回傳 `true`。
  static Future<bool> deletePlace({
    required String elderId,
    required int placeId,
    required int userId,
  }) async {
    try {
      final result =
          await ApiClient.delete('/location/places/$elderId/$placeId?user_id=$userId');
      return result != null && result['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ LocationApi.deletePlace error: $e');
      return false;
    }
  }

  /// 讀取指定日期（省略則今天）的移動摘要。
  /// 回傳 `{sharing_enabled, date, has_home, distance_m, outing_count, outside_minutes,
  /// at_home, last_update, point_count, device_status?, device_status_at?}`；分享關閉時只有
  /// `{sharing_enabled: false, date}`。
  /// `outing_count`／`outside_minutes`／`at_home` 在沒設定「家」時為 `null`。
  /// 查無權限或失敗時回傳 `null`。時區處理與 [getTrail] 相同。
  static Future<Map<String, dynamic>?> getSummary({
    required String elderId,
    required int userId,
    DateTime? date,
  }) async {
    final d = date ?? DateTime.now();
    final tzOffset = d.timeZoneOffset.inMinutes;
    // 摘要一律明確帶日期（省略時用裝置今天），避免後端以 UTC 日期解讀「今天」。
    final path = '/location/summary/$elderId?user_id=$userId&tz_offset=$tzOffset'
        '&date=${_formatDate(d)}';
    try {
      final result = await ApiClient.get(path);
      if (result != null && result['status'] == 'success') {
        return result['data'] as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ LocationApi.getSummary error: $e');
    }
    return null;
  }

  /// 家屬讀取「安心提醒」設定。
  /// 回傳 `{settings: {late_return_enabled, late_return_time 'HH:MM', no_update_enabled,
  /// no_update_hours, no_update_start, no_update_end, far_enabled, far_km}, has_home}`；
  /// 查無權限或失敗時回傳 `null`。`has_home` 為 false 時，晚歸與遠離家提醒不會生效。
  static Future<Map<String, dynamic>?> getAlertSettings({
    required String elderId,
    required int userId,
  }) async {
    try {
      final result = await ApiClient.get('/location/alert-settings/$elderId?user_id=$userId');
      if (result != null && result['status'] == 'success') {
        final data = result['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('⚠️ LocationApi.getAlertSettings error: $e');
    }
    return null;
  }

  /// 家屬修改「安心提醒」設定（只送有改動的欄位，[changes] 的鍵同 [getAlertSettings]
  /// 的 `settings`）。成功回傳更新後的 `{settings}`，失敗回傳 `null`。
  static Future<Map<String, dynamic>?> updateAlertSettings({
    required String elderId,
    required int userId,
    required Map<String, dynamic> changes,
  }) async {
    try {
      final result = await ApiClient.put('/location/alert-settings/$elderId', {
        'user_id': userId,
        ...changes,
      });
      if (result != null && result['status'] == 'success') {
        final data = result['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('⚠️ LocationApi.updateAlertSettings error: $e');
    }
    return null;
  }

  /// 從 `{status, data: {place}}` 取出 [ElderPlace]；格式不符回傳 `null`。
  static ElderPlace? _parsePlace(Map<String, dynamic>? result) {
    if (result == null || result['status'] != 'success') return null;
    final raw = result['data']?['place'];
    if (raw is! Map) return null;
    try {
      return ElderPlace.fromJson(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('⚠️ LocationApi._parsePlace error: $e');
      return null;
    }
  }
}
