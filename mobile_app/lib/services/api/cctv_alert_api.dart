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

/// CCTV 監視機串流推幀、跌倒測試、設備管理、緊急警報歷史與室內定位 (IPS) API
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

  /// 觸發與 YOLO 相同的跌倒警報派送路徑（測試用途）
  static Future<String?> triggerTestFall({
    required String elderId,
    required String deviceName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/cctv/test-fall'),
            headers: ApiClient.deviceTokenHeader,
            body: {'elder_id': elderId, 'device_name': deviceName},
          )
          .timeout(ApiClient.timeout);
      if (response.statusCode == 200) return null;
      String detail = '送出失敗（HTTP ${response.statusCode}）';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {}
      debugPrint('⚠️ triggerTestFall 被拒: ${response.statusCode} $detail');
      return detail;
    } catch (e) {
      debugPrint('⚠️ triggerTestFall error: $e');
      return '無法連線到後端，請確認網路狀態';
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
  static Future<Map<String, dynamic>?> markFalseAlarm({
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
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        final payload = data['data'];
        return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ markFalseAlarm error: $e');
      return null;
    }
  }

  /// 長輩跌倒／緊急警報的持久歷史記錄
  static Future<List<dynamic>> getEmergencyAlerts(
    String elderId, {
    required int userId,
    String? status,
    int limit = 20,
  }) async {
    try {
      final queryParameters = <String, String>{
        'user_id': userId.toString(),
        'limit': limit.toString(),
      };
      if (status != null && status.isNotEmpty) {
        queryParameters['status'] = status;
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
