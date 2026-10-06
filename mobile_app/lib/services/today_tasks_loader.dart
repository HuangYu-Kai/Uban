import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'friend_service.dart';

/// 今日任務資料：排程提醒清單 + 今天已打卡的提醒 id。
class TodayTasksData {
  const TodayTasksData(this.reminders, this.completedIds);
  final List<Map<String, dynamic>> reminders;
  final Set<int> completedIds;
}

/// 長輩「首頁」與「我的」共用的今日任務讀取（避免兩邊用不同的 elder id 而出現 0/0 vs 1/1）。
///
/// 兩邊後續都以 `groupByStatus(reminders, completedIds, now)` 分組，
/// 只要讀到的資料一致，進度數字就一致。
class TodayTasksLoader {
  TodayTasksLoader._();

  /// 權威 elder_id：優先 `FriendService.resolveMyElderId(userId)`（後端 elder_profile），
  /// 解析不到才退回 [roomId]（長輩端 roomId 即 elder_id）。都沒有則回傳 null。
  static Future<String?> resolveElderId(int userId, {String? roomId}) async {
    final resolved = await FriendService.resolveMyElderId(userId);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    if (roomId != null && roomId.isNotEmpty) return roomId;
    return null;
  }

  /// 讀取今日已完成 id（本機）。
  static Future<Set<int>> loadCompletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final list = prefs.getStringList('completed_tasks_$today') ?? [];
    return list.map((e) => int.tryParse(e) ?? -1).toSet();
  }

  /// 純函式：本機完成集 ∪ 後端 `completed_ids`（跨裝置打卡）。
  /// 後端為「別台裝置完成」的權威；本機獨有的 id 可能是離線／尚未送出，不丟棄。
  static Set<int> mergeCompleted(Set<int> local, Object? serverIds) {
    final out = <int>{...local};
    if (serverIds is List) {
      for (final e in serverIds) {
        final v = e is int ? e : int.tryParse(e.toString());
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  /// 讀取提醒＋完成集。網路／後端失敗會**丟出例外**（不再當成「沒有提醒」）。
  ///
  /// 提醒讀成功後再嘗試向後端要今日進度並與本機取聯集（同一個 elder 的另一台裝置
  /// 打卡也看得到）；進度讀取失敗不丟例外，維持僅本機。聯集會寫回本機
  /// `completed_tasks_<today>`，離線時仍能顯示。
  static Future<TodayTasksData> load(String elderId) async {
    var completed = await loadCompletedIds();
    final list = await ApiService.getElderReminders(elderId);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final progress = await ApiService.getTodayProgress(elderId, date: today);
      final merged = mergeCompleted(completed, progress['completed_ids']);
      if (merged.length != completed.length) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('completed_tasks_$today',
            merged.map((e) => e.toString()).toList());
      }
      completed = merged;
    } catch (e) {
      debugPrint('⚠️ [TodayTasksLoader] 今日進度同步失敗，僅用本機: $e');
    }
    return TodayTasksData(List<Map<String, dynamic>>.from(list), completed);
  }
}
