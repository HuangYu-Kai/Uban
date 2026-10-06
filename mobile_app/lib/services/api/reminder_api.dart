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

  /// 長輩打卡。[localDate] 為「裝置本機日期」`yyyy-MM-dd`（與 `completed_tasks_<date>`
  /// 同一種寫法）；省略時取今天。後端冪等，重送不會重複記錄。
  static Future<bool> completeElderReminder(int reminderId,
      {String? localDate}) async {
    try {
      final res = await ApiClient.post('/reminder/$reminderId/complete',
          {'local_date': localDate ?? localDateKey()});
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ completeElderReminder error: $e');
      return false;
    }
  }

  /// 取消打卡（undo）。失敗回傳 false，呼叫端負責回退樂觀更新。
  static Future<bool> uncompleteElderReminder(int reminderId,
      {String? localDate}) async {
    try {
      final url = ApiClient.fullUrl(
          '/reminder/$reminderId/complete?local_date=${localDate ?? localDateKey()}');
      final res = await http.delete(Uri.parse(url)).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(res);
      return data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ uncompleteElderReminder error: $e');
      return false;
    }
  }

  /// 裝置本機今天的 `yyyy-MM-dd`。
  static String localDateKey([DateTime? d]) {
    final t = d ?? DateTime.now();
    String p(int n, int w) => n.toString().padLeft(w, '0');
    return '${p(t.year, 4)}-${p(t.month, 2)}-${p(t.day, 2)}';
  }

  /// 打卡進度：今天適用的提醒＋是否已完成。
  /// 回傳 `{date, items:[{id,title,category,time_str,completed,created_by_role}], completed_ids, done, total}`；
  /// [date] 為裝置本機日期（長輩端必帶；家屬端省略則用後端預設）。
  /// 失敗**丟出例外**（呼叫端分辨「沒有安排」與「讀取失敗」）。
  static Future<Map<String, dynamic>> getTodayProgress(String elderId,
      {String? date}) async {
    try {
      final q = date == null ? '' : '?date=$date';
      final res =
          await ApiClient.get('/reminder/elder/$elderId/today-progress$q');
      if (res != null && res['status'] == 'success' && res['data'] is Map) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
      throw Exception('getTodayProgress: unexpected response');
    } catch (e) {
      debugPrint('⚠️ getTodayProgress error: $e');
      rethrow;
    }
  }

  /// 「全部完成」的日期清單（`yyyy-MM-dd`），供連勝紀錄跨裝置合併。
  /// 失敗**丟出例外**。
  static Future<List<String>> getAllDoneDates(String elderId,
      {required String until, int days = 60}) async {
    try {
      final res = await ApiClient.get(
          '/reminder/elder/$elderId/all-done-dates?until=$until&days=$days');
      if (res != null && res['status'] == 'success' && res['data'] is Map) {
        final dates = (res['data'] as Map)['dates'];
        if (dates is List) return [for (final d in dates) d.toString()];
      }
      throw Exception('getAllDoneDates: unexpected response');
    } catch (e) {
      debugPrint('⚠️ getAllDoneDates error: $e');
      rethrow;
    }
  }
}
