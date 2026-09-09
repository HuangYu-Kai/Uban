import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 家人綁定、長輩解綁、監視機配對與 Setup 狀態管理 API
class PairingApi {
  /// 供 monitor_pairing_screen 顯示具體錯誤原因
  static String? lastResolveError;

  static Future<Map<String, dynamic>> requestPairingCode() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/pairing/request_code'),
        headers: {'Content-Type': 'application/json'},
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

  static Future<Map<String, dynamic>> ensureYuxuanDemoElder() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/pairing/dev/ensure-yuxuan-demo'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> ensureGawaDemoElder() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/pairing/dev/ensure-gawa-demo'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiClient.timeout);
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
