import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 家人綁定、長輩解綁、監視機配對與 Setup 狀態管理 API
class PairingApi {
  /// 供 monitor_pairing_screen 顯示具體錯誤原因
  static String? lastResolveError;

  /// 為自主登入的全新長者向雲端申請獨立唯一帳號
  ///
  /// ⚠️ 第四十九輪 item 2：`elderName` 改為必填。原本帶預設值 '長輩朋友'，
  /// 但呼叫端（elder_pairing_display_screen.dart）從未實際傳入這個參數，
  /// 於是預設值被當成真正的姓名送進後端寫入 elder_profile——這正是正式庫
  /// 「長輩朋友」幽靈帳號的成因。後端現在也會拒絕空白或不像人名的值（400）。
  static Future<Map<String, dynamic>> createAutonomousElder({
    required String elderName,
    String gender = 'M',
    int age = 75,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/pairing/create_autonomous_elder'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'elder_name': elderName,
          'gender': gender,
          'age': age,
        }),
      ).timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '自主帳號建立連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestPairingCode([int? elderId]) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/pairing/request_code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (elderId != null) 'elder_id': elderId,
        }),
      ).timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> checkPairingStatus(String code) async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiClient.baseUrl}/pairing/check_status/$code'),
          )
          .timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> confirmPairing({
    required int familyId,
    required String code,
    required String elderName,
    required String gender,
    required int age,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'code': code,
              'elder_name': elderName,
              'gender': gender,
              'age': age,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> unbindElder(
    int familyId,
    Object elderId,
  ) async {
    try {
      final response = await http
          .delete(Uri.parse('${ApiClient.baseUrl}/pairing/$familyId/$elderId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'error': 'Failed to unbind elder: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> createMonitorSetup(
    int familyId,
    String elderId,
    String deviceName,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/monitor_setup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
              'device_name': deviceName,
            }),
          )
          .timeout(ApiClient.timeout);
      
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('📞 createMonitorSetup error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> resolveMonitorSetup(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/monitor_setup/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
            }),
          )
          .timeout(ApiClient.timeout);
      
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        lastResolveError = null;
        return data['data'];
      }

      final dynamic msg = data['detail'] ?? data['message'];
      lastResolveError =
          msg != null ? msg.toString() : '伺服器錯誤（HTTP ${response.statusCode}）';
      return null;
    } catch (e) {
      debugPrint('⚠️ resolveMonitorSetup error: $e');
      lastResolveError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getMonitorSetupStatus(
    String code, {
    required int userId,
  }) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/pairing/monitor_setup/status').replace(
        queryParameters: {
          'code': code,
          'user_id': userId.toString(),
        },
      );
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] != 'success') return null;
      final payload = data['data'];
      return payload is Map ? Map<String, dynamic>.from(payload) : null;
    } catch (e) {
      debugPrint('⚠️ getMonitorSetupStatus error: $e');
      return null;
    }
  }
}
