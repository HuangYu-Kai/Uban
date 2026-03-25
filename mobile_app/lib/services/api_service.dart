import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // 動態讀取 .env 中的 IP
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000'}/api';

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
    String gender = 'M',
    int age = 20,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'role': role,
        'gender': gender,
        'age': age,
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

  static Future<Map<String, dynamic>> requestPairingCode() async {
    final response = await http.post(
      Uri.parse('$baseUrl/pairing/request_code'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> checkPairingStatus(String code) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pairing/check_status/$code'),
    );
    return jsonDecode(response.body);
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
      Uri.parse('$baseUrl/user/update_elder'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'family_id': familyId,
        'elder_id': elderId,
        'user_name': userName,
        'age': age,
        'gender': gender,
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
    final response = await http.get(Uri.parse('$baseUrl/get_elder_data?user_id=$userId'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['elders'] as List<dynamic>;
      }
    }
    return [];
  }

  static Future<List<dynamic>> getPairedElders(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/elders'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getElderProfile(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/profile/$userId'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateElderProfile({
    required int userId,
    String? phone,
    String? location,
    String? aiPersona,
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
        if (aiPersona != null) 'ai_persona': aiPersona,
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
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
