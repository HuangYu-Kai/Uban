import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // --- 動態伺服器 IP 設置 ---
  static const String _serverIp =
      String.fromEnvironment('SERVER_IP', defaultValue: 'localhost-0.tail5abf5e.ts.net');

  // 依據是否為 ngrok 自動切換 http/https 與 埠號
  static final String baseUrl = _serverIp.contains('ngrok') || _serverIp.contains('ts.net')
      ? 'https://$_serverIp/api'
      : 'http://$_serverIp:8000/api';

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Map<String, dynamic> _safeDecode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (e) {
      return {
        'status': 'error',
        'message': '伺服器回傳格式錯誤 (可能已離線)',
        'details': response.body.length > 50
            ? response.body.substring(0, 50)
            : response.body
      };
    }
  }

  static Future<Map<String, dynamic>> requestPairingCode() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pairing/request_code'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }

  static Future<Map<String, dynamic>> checkPairingStatus(String code) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/pairing/check_status/$code'),
          )
          .timeout(const Duration(seconds: 10));
      return _safeDecode(response);
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
    final response = await http.post(
      Uri.parse('$baseUrl/pairing/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'family_id': familyId,
        'code': code,
        'elder_name': elderName,
        'gender': gender,
        'age': age,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateElderInfo({
    required int familyId,
    required int elderId,
    String? userName,
    int? age,
    String? gender,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/profile/$elderId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (userName != null) 'user_name': userName,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getStatus(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/status/$userId'));
    return jsonDecode(response.body);
  }

  // AI 相關功能
  static Future<Map<String, dynamic>> aiChat(int userId, String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ai/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'message': message}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> logActivity(
    int userId,
    String type,
    String content, {
    Map<String, dynamic>? extraData,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ai/log_activity'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'event_type': type,
        'content': content,
        'extra_data': extraData != null ? jsonEncode(extraData) : null,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getElderData(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/user/$userId/elders'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> getPairedElders(int userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/user/$userId/elders'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getElderProfile(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/profile/$userId'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateElderProfile({
    required int userId,
    String? phone,
    String? location,
    String? appellation,
    int? aiEmotionTone,
    int? aiTextVerbosity,
    String? chronicDiseases,
    String? medicationNotes,
    String? interests,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/profile/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (phone != null) 'phone': phone,
        if (location != null) 'location': location,
        if (appellation != null) 'appellation': appellation,
        if (aiEmotionTone != null) 'ai_emotion_tone': aiEmotionTone,
        if (aiTextVerbosity != null) 'ai_text_verbosity': aiTextVerbosity,
        if (chronicDiseases != null) 'chronic_diseases': chronicDiseases,
        if (medicationNotes != null) 'medication_notes': medicationNotes,
        if (interests != null) 'interests': interests,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> unbindElder(
    int familyId,
    int elderId,
  ) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/pairing/$familyId/$elderId'))
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

  static Future<Map<String, dynamic>> uploadAvatar(
    int userId,
    String filePath,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/$userId/avatar'),
      );
      request.files.add(await http.MultipartFile.fromPath('avatar', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'error': 'Failed to upload avatar: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final rootUrl = baseUrl.replaceAll('/api', '');
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

  static Future<Map<String, dynamic>> testOidc({
    required String provider,
    required String email,
    required String uid,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/test_oidc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'provider': provider,
              'email': email,
              'uid': uid,
              'token': token,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return _safeDecode(response);
    } catch (e) {
      return {'status': 'error', 'message': '網路連線失敗: $e'};
    }
  }
}
