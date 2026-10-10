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
    // ★ 第五十三輪 onboard53：年齡／居住地改為必填。家屬端註冊表單把這三欄
    //   併入同一張表單一次送出，後端 routers/auth.py::register() 仍會用
    //   services/taiwan_regions 白名單驗證一次，不因為是註冊流程就放寬。
    int? age,
    String? residenceCity,
    String? residenceDistrict,
    // Email 驗證碼（先呼叫 sendEmailCode(purpose: 'register') 取得）
    String? emailCode,
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
              if (age != null) 'age': age,
              if (residenceCity != null) 'residence_city': residenceCity,
              if (residenceDistrict != null) 'residence_district': residenceDistrict,
              if (emailCode != null) 'email_code': emailCode,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  /// 寄送 Email 驗證碼。purpose 為 'register'（註冊）或 'reset_password'（忘記密碼）。
  /// 成功 data：{expires_in: 600, resend_after: 60}。
  /// 409＝Email 已註冊（register）、429＝寄送太頻繁、503＝寄信失敗，皆帶中文 detail。
  static Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    required String purpose,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/auth/email-code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'purpose': purpose}),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  /// 以 Email 驗證碼重設密碼。400＝驗證碼錯誤／已過期或密碼格式不符。
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/auth/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
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
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
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
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
  }

  static Future<Map<String, dynamic>> verifyRecoveryCode(
    String code, {
    bool consume = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/pairing/verify_recovery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              // ★ 2026-10-06 登入流程審查：consume=false 只預覽姓名、不用掉代碼、不回 token；
              //   長輩按下確認後才以 consume=true 真正登入（預設 true，維持舊行為）。
              'consume': consume,
            }),
          )
          .timeout(ApiClient.timeout);
      return ApiClient.safeDecode(response);
    } on TimeoutException {
      return {'status': 'error', 'message': '連線逾時，請檢查網路'};
    } catch (e) {
      debugPrint('⚠️ [AuthApi] 網路錯誤: $e');
      return {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
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
