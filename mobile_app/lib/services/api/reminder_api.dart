import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 遠端排程提醒 API
class ReminderApi {
  static Future<List<dynamic>> getElderReminders(String elderId) async {
    try {
      final res = await ApiClient.get('/reminder/elder/$elderId');
      if (res != null && res['status'] == 'success' && res['data'] is List) {
        return res['data'];
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ getElderReminders error: $e');
      return [];
    }
  }

  static Future<bool> createElderReminder(Map<String, dynamic> body) async {
    try {
      final res = await ApiClient.post('/reminder/', body);
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ createElderReminder error: $e');
      return false;
    }
  }

  static Future<bool> toggleElderReminder(int reminderId) async {
    try {
      final url = ApiClient.fullUrl('/reminder/$reminderId/toggle');
      final res = await http.put(Uri.parse(url)).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(res);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ toggleElderReminder error: $e');
      return false;
    }
  }

  static Future<bool> deleteElderReminder(int reminderId) async {
    try {
      final url = ApiClient.fullUrl('/reminder/$reminderId');
      final res = await http.delete(Uri.parse(url)).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(res);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ deleteElderReminder error: $e');
      return false;
    }
  }

  static Future<bool> updateElderReminder(int reminderId, Map<String, dynamic> body) async {
    try {
      final res = await ApiClient.put('/reminder/$reminderId', body);
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ updateElderReminder error: $e');
      return false;
    }
  }

  static Future<bool> completeElderReminder(int reminderId) async {
    try {
      final res = await ApiClient.post('/reminder/$reminderId/complete', {});
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ completeElderReminder error: $e');
      return false;
    }
  }
}
