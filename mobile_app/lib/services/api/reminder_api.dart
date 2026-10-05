import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 遠端排程提醒 API
class ReminderApi {
  /// 讀取長輩的排程提醒。
  ///
  /// ⚠️ 失敗（網路錯誤、後端非 success）會**丟出例外**，不再回傳 `[]`——
  /// 否則呼叫端無法分辨「真的沒有提醒」與「讀取失敗」（曾造成首頁 0/0、我的 1/1）。
  /// 呼叫端必須自行 try/catch。
  static Future<List<dynamic>> getElderReminders(String elderId) async {
    try {
      final res = await ApiClient.get('/reminder/elder/$elderId');
      if (res != null && res['status'] == 'success' && res['data'] is List) {
        return res['data'];
      }
      throw Exception('getElderReminders: unexpected response');
    } catch (e) {
      debugPrint('⚠️ getElderReminders error: $e');
      rethrow;
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

  /// [requesterRole]＝'elder' 時，後端只允許刪除長輩自建的目標。
  static Future<bool> deleteElderReminder(int reminderId,
      {String? requesterRole, int? requesterUserId}) async {
    try {
      final q = <String>[
        if (requesterRole != null) 'requester_role=$requesterRole',
        if (requesterUserId != null) 'requester_user_id=$requesterUserId',
      ];
      final url = ApiClient.fullUrl(
          '/reminder/$reminderId${q.isEmpty ? '' : '?${q.join('&')}'}');
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

  /// 家屬端「今日打卡」：今天適用的提醒＋是否已完成。
  /// 回傳 `{date, items:[{id,title,category,time_str,completed,created_by_role}], done, total}`；
  /// 失敗**丟出例外**（呼叫端分辨「沒有安排」與「讀取失敗」）。
  static Future<Map<String, dynamic>> getTodayProgress(String elderId) async {
    try {
      final res = await ApiClient.get('/reminder/elder/$elderId/today-progress');
      if (res != null && res['status'] == 'success' && res['data'] is Map) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
      throw Exception('getTodayProgress: unexpected response');
    } catch (e) {
      debugPrint('⚠️ getTodayProgress error: $e');
      rethrow;
    }
  }
}
