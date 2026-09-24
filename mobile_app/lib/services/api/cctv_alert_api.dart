import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// `POST /api/cctv/frame` 的簡化解析結果
class CctvPushResult {
  final bool detected;
  final String? reason;
  final String? loadError;

  const CctvPushResult({required this.detected, this.reason, this.loadError});

  static const String transportError = 'transport_error';

  factory CctvPushResult.failure() =>
      const CctvPushResult(detected: false, reason: transportError);
}

/// `resolveAlert` / `markFalseAlarm` 的結果：不再只回傳 `null` 淹沒失敗原因，
/// 而是把 HTTP 狀態碼與後端 `detail` 字串一起帶回，讓呼叫端能顯示「找不到這筆
/// 警報」／「尚未與這位長輩綁定」／「伺服器錯誤」等不同訊息，而不是塌成同一句
/// 「回報失敗，請稍後再試」。
/// ★ 第五十一輪：見 `routers/alert.py::mark_false_alarm` / `resolve_alert_endpoint`
/// ——兩者找不到警報或無綁定關係皆回 404、detail 固定為 "Alert not found"。
class AlertActionResult {
  final bool success;
  final int? statusCode;
  final String? detail;
  final Map<String, dynamic>? data;

  const AlertActionResult({
    required this.success,
    this.statusCode,
    this.detail,
    this.data,
  });

  /// 給使用者看的繁體中文原因；後端只在英文 debug 情境下才回英文 detail
  /// （見上方），所以依狀態碼映射成 elder-family 友善的說法，detail 僅作為
  /// 除錯備援（後端回傳非預期文字時仍有東西可顯示）。
  String get friendlyReason {
    switch (statusCode) {
      case 404:
        return '找不到這筆警報';
      case 403:
        return '尚未與這位長輩綁定';
      case 400:
        return detail ?? '請求資料不完整';
      case null:
        return detail ?? '無法連線到伺服器';
      default:
        return '伺服器錯誤${detail != null ? '（$detail）' : ''}';
    }
  }
}

/// CCTV 監視機串流推幀、設備管理、緊急警報歷史與室內定位 (IPS) API
class CctvAlertApi {
  /// CCTV 監視機推送單一影格給後端做 YOLO 跌倒偵測
  static Future<CctvPushResult> pushCctvFrame({
    required String elderId,
    required String deviceName,
    required Uint8List frameBytes,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/cctv/frame'),
      );
      request.headers.addAll(ApiClient.deviceTokenHeader);
      request.fields['elder_id'] = elderId;
      request.fields['device_name'] = deviceName;
      request.files.add(
        http.MultipartFile.fromBytes('frame', frameBytes, filename: 'frame.png'),
      );
      final streamed = await request.send().timeout(ApiClient.timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        debugPrint('⚠️ pushCctvFrame 非 200: ${response.statusCode}');
        return CctvPushResult.failure();
      }
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is Map) {
        return CctvPushResult(
          detected: data['detected'] == true,
          reason: data['reason'] as String?,
          loadError: data['load_error'] as String?,
        );
      }
      return CctvPushResult.failure();
    } catch (e) {
      debugPrint('⚠️ pushCctvFrame error: $e');
      return CctvPushResult.failure();
    }
  }

  /// 移除一台監視機設備（含其 FCM token）
  static Future<bool> deleteMonitorDevice({
    required String elderId,
    required String deviceName,
    int? userId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/pairing/monitor_device').replace(
        queryParameters: {
          'elder_id': elderId,
          'device_name': deviceName,
          if (userId != null) 'user_id': userId.toString(),
        },
      );
      final response = await http.delete(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ deleteMonitorDevice error: $e');
      return false;
    }
  }

  /// 以 HTTP 交叉驗證長輩名下的監視設備清單
  static Future<List<dynamic>> fetchMonitorDevices({
    required String elderId,
    required int userId,
  }) async =>
      await fetchMonitorDevicesOrNull(elderId: elderId, userId: userId) ??
      const [];

  /// 區分「查詢失敗」(null) 與「查到了、清單是空的」([])
  static Future<List<dynamic>?> fetchMonitorDevicesOrNull({
    required String elderId,
    required int userId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/pairing/monitor_devices').replace(
        queryParameters: {
          'elder_id': elderId,
          'user_id': userId.toString(),
        },
      );
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] != 'success') return null;
      final devices = (data['data'] ?? const {})['devices'];
      return devices is List ? devices : const [];
    } catch (e) {
      debugPrint('⚠️ fetchMonitorDevices error: $e');
      return null;
    }
  }

  /// 重新命名一台監視設備
  static Future<Map<String, dynamic>?> renameMonitorDevice({
    required String elderId,
    required int userId,
    required String oldDeviceName,
    required String newDeviceName,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse('${ApiClient.baseUrl}/pairing/monitor_device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'user_id': userId,
              'old_device_name': oldDeviceName,
              'new_device_name': newDeviceName,
            }),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] != 'success') {
        debugPrint('⚠️ renameMonitorDevice 被拒: ${response.statusCode} $data');
        return null;
      }
      final payload = data['data'];
      return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    } catch (e) {
      debugPrint('⚠️ renameMonitorDevice error: $e');
      return null;
    }
  }

  /// 開通／延長警報的音頻橋（30 分鐘單向音頻）
  static Future<Map<String, dynamic>?> openAudioBridge({
    required int alertId,
    required int fromId,
    required int toDeviceId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/alerts/$alertId/audio-bridge'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from_id': fromId,
              'to_device_id': toDeviceId,
            }),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        final payload = data['data'];
        return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ openAudioBridge error: $e');
      return null;
    }
  }

  /// 查詢某警報目前是否有有效的音頻橋
  static Future<Map<String, dynamic>?> checkAudioBridge(
    int alertId, {
    int? userId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/alerts/audio/$alertId').replace(
        queryParameters: userId == null ? null : {'user_id': '$userId'},
      );
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ checkAudioBridge error: $e');
      return null;
    }
  }

  /// 家屬把一筆警報標記為誤報（供統計儀表板排除誤報用）。
  /// 授權與冪等行為見後端 `routers/alert.py::mark_false_alarm`。
  ///
  /// ★ 第五十一輪：回傳型別由 `Map<String, dynamic>?` 改為
  /// [AlertActionResult]，把 HTTP 狀態碼與後端 `detail` 一併帶出，讓呼叫端
  /// （`alert_center_screen.dart`）能區分「找不到這筆警報」／「尚未與這位
  /// 長輩綁定」／「伺服器錯誤」，不再全部塌成一句「標記誤報失敗」。
  static Future<AlertActionResult> markFalseAlarm({
    required int alertId,
    required int userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/alerts/$alertId/false-alarm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(ApiClient.timeout);
      final decoded = ApiClient.safeDecode(response);
      if (response.statusCode == 200 && decoded['status'] == 'success') {
        final payload = decoded['data'];
        return AlertActionResult(
          success: true,
          statusCode: response.statusCode,
          data: payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{},
        );
      }
      return AlertActionResult(
        success: false,
        statusCode: response.statusCode,
        detail: decoded['detail']?.toString() ?? decoded['message']?.toString(),
      );
    } catch (e) {
      debugPrint('⚠️ markFalseAlarm error: $e');
      return AlertActionResult(success: false, detail: e.toString());
    }
  }

  /// ★ 第四十九輪 item 12：把某長輩／某監視機目前未結案的警報轉為「處理
  /// 中」。供 `family_main_screen.dart::_openMonitorViewForDevice()` 在
  /// 開啟監控畫面時 fire-and-forget 呼叫——呼叫端不關心細節，只在意「有
  /// 沒有噴例外」，故回傳值只用布林表示是否成功送達後端；找不到任何未
  /// 結案警報也算成功（後端本來就把這當合法情況，見端點 docstring）。
  static Future<bool> markAlertProcessing({
    required String elderId,
    required String deviceId,
    required int userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/alerts/mark-processing'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'device_id': deviceId,
              'user_id': userId,
            }),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ markAlertProcessing error: $e');
      return false;
    }
  }

  /// ★ 第四十九輪 item 12：家屬主動回報一筆警報「已處理完畢」（狀態機第三
  /// 態）。授權與冪等行為見後端 `routers/alert.py::resolve_alert_endpoint`。
  ///
  /// ★ 第五十一輪：同 [markFalseAlarm]，回傳型別改為 [AlertActionResult]
  /// 以攜帶狀態碼與 `detail`。
  static Future<AlertActionResult> resolveAlert({
    required int alertId,
    required int userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/alerts/$alertId/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(ApiClient.timeout);
      final decoded = ApiClient.safeDecode(response);
      if (response.statusCode == 200 && decoded['status'] == 'success') {
        final payload = decoded['data'];
        return AlertActionResult(
          success: true,
          statusCode: response.statusCode,
          data: payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{},
        );
      }
      return AlertActionResult(
        success: false,
        statusCode: response.statusCode,
        detail: decoded['detail']?.toString() ?? decoded['message']?.toString(),
      );
    } catch (e) {
      debugPrint('⚠️ resolveAlert error: $e');
      return AlertActionResult(success: false, detail: e.toString());
    }
  }

  /// 長輩跌倒／緊急警報的持久歷史記錄
  ///
  /// ★ 第五十二輪 F2：新增選填 `days`——只回傳 `detected_at` 在最近 N 天內
  /// 的紀錄，供家屬端警示中心「本週／本月／全部」時間篩選使用。對應後端
  /// `routers/alert.py::get_alerts` 的同名選填參數；`null`（預設）時完全
  /// 不帶這個查詢參數，後端維持既有的「不套時間篩選」行為，其餘既有呼叫
  /// 端不受影響。
  ///
  /// ★ 第五十三輪 familyfix53：新增選填 `startDate`／`endDate`（格式
  /// 'YYYY-MM-DD'，代表台灣日曆日）——供家屬端警示中心「自訂日期範圍」
  /// 查詢使用。對應後端同名新增參數；兩者必須成對提供，且**優先於**
  /// `days`（同時提供時 `days` 會被後端忽略，見該端點 docstring）。呼叫端
  /// （`alert_center_screen.dart`）已確保這三者不會同時帶入衝突的值——
  /// `_timeRange == custom` 時只送 `startDate`/`endDate`，其餘既有時間
  /// 篩選（本週／本月／全部）只送 `days`。
  static Future<List<dynamic>> getEmergencyAlerts(
    String elderId, {
    required int userId,
    String? status,
    int limit = 20,
    int? days,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParameters = <String, String>{
        'user_id': userId.toString(),
        'limit': limit.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParameters['status'] = status;
      }
      if (startDate != null && endDate != null) {
        queryParameters['start_date'] = startDate;
        queryParameters['end_date'] = endDate;
      } else if (days != null) {
        queryParameters['days'] = days.toString();
      }
      final uri = Uri.parse('${ApiClient.baseUrl}/alerts/$elderId')
          .replace(queryParameters: queryParameters);
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        final alerts = data['data']['alerts'];
        if (alerts is List) return alerts;
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getEmergencyAlerts error: $e');
      return [];
    }
  }

  /// IPS：讀取家屬為某監視機校準過的樓層區域（zone）多邊形設定
  static Future<List<dynamic>> getZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/ips/zones/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        final zones = data['data']['zones'];
        if (zones is List) return zones;
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getZoneConfig error: $e');
      return [];
    }
  }

  /// IPS：全量覆寫某監視機的樓層區域（zone）多邊形設定
  static Future<String?> saveZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
    required List<Map<String, dynamic>> zones,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/ips/zones/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'zones': zones}),
          )
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) return null;
      String detail = '儲存失敗（HTTP ${response.statusCode}）';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {}
      debugPrint('⚠️ saveZoneConfig 被拒: ${response.statusCode} $detail');
      return detail;
    } catch (e) {
      debugPrint('⚠️ saveZoneConfig error: $e');
      return '無法連線到後端，請確認網路狀態';
    }
  }

  /// IPS：查詢長輩目前所在的樓層區域（zone）與已停留秒數
  static Future<Map<String, dynamic>> getCurrentZone(
    String elderId, {
    required int userId,
    required int deviceId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/ips/current/$elderId').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'device_id': deviceId.toString(),
        },
      );
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data']);
      }
      return {};
    } catch (e) {
      debugPrint('⚠️ getCurrentZone error: $e');
      return {};
    }
  }

  /// IPS：組出監視機最近一次快照畫面的 URL
  static String zoneSnapshotUrl(
    String elderId, {
    required int userId,
    required int deviceId,
  }) {
    final uri = Uri.parse('${ApiClient.baseUrl}/ips/snapshot/$elderId').replace(
      queryParameters: {
        'user_id': userId.toString(),
        'device_id': deviceId.toString(),
      },
    );
    return uri.toString();
  }
}
