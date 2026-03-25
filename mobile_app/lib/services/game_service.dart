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

  Future<Map<String, dynamic>> getElderStatus(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/elder_status/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch elder status: ${response.body}');
    }
  }

  // --- New Admin & Elder Endpoints ---
  
  Future<Map<String, dynamic>> getElderCollection(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/elder/collection/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch elder collection: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateSteps(String elderId, int deltaSteps) async {
    final response = await http.post(
      Uri.parse('$baseUrl/elder/update_steps'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'elder_id': elderId,
        'delta_steps': deltaSteps,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update steps: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getAdminElderInfo(String elderId) async {
    final response = await http.get(Uri.parse('$baseUrl/admin/elder_info/$elderId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch admin elder info: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> assignAppearance(String elderId, int gawaId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/assign_appearance'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId, 'gawa_id': gawaId}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to assign appearance: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> setDistributionTime(String isoTimeStr) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/set_distribution_time'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'distribution_time': isoTimeStr}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to set distribution time: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> saveSteps(String elderId, int steps) async {
    final response = await http.post(
      Uri.parse('$baseUrl/save_steps'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'elder_id': elderId, 'steps': steps}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to save steps: ${response.body}');
    }
  }
}
