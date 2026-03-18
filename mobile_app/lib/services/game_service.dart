import 'dart:convert';
import 'package:http/http.dart' as http;
import '../globals.dart';

class GameService {
  static const String baseUrl = 'http://10.0.2.2:5000/api/game'; // Adjust for your environment

  Future<Map<String, dynamic>> distributeAppearances({String? elderId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/distribute_appearances'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to distribute appearances: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/leaderboard/$elderId'));
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      throw Exception('Failed to fetch leaderboard: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> checkResetStepTotal() async {
    final response = await http.post(Uri.parse('$baseUrl/check_reset'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check reset: ${response.body}');
    }
  }
}
