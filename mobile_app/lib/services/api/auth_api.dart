import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 身份驗證、帳號管理、訂閱與健康檢查 API
class AuthApi {
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'email': email,
              'password': password,
              'role': role,
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

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> testOidc({
    required String provider,
    required String email,
    required String uid,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/auth/test_oidc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'provider': provider,
              'email': email,
              'uid': uid,
              'token': token,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return ApiClient.safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final rootUrl = ApiClient.baseUrl.replaceAll('/api', '');
      final response = await http
          .get(Uri.parse(rootUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return {'status': 'ok'};
      }
      return {'error': '伺服器狀態異常: ${response.statusCode}'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> generateRecoveryLink({
    required int familyId,
    required String elderId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/generate_recovery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'elder_id': elderId,
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

  static Future<Map<String, dynamic>> verifyRecoveryCode(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/verify_recovery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
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

  static Future<bool> releaseSession({
    required String fcmToken,
    int? userId,
    String? roomId,
  }) async {
    try {
      final Map<String, dynamic> body = {'fcm_token': fcmToken};
      if (userId != null) body['user_id'] = userId;
      if (roomId != null) body['room_id'] = roomId;

      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/session/release'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(ApiClient.timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('⚠️ [AuthApi] releaseSession error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getSubscriptionTier(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/subscription/tier/$userId'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ getSubscriptionTier error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getSubscriptionRecords(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/subscription/records/$userId'))
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } catch (e) {
      debugPrint('⚠️ getSubscriptionRecords error: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
