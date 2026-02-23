import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 對於實機測試，請使用您電腦的區域網路 IP
  static const String baseUrl = 'http://192.168.31.209:5000/api';

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

  static Future<List<dynamic>> getPairedElders(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/elders'));
    return jsonDecode(response.body);
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
