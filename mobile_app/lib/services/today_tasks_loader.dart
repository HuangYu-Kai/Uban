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
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final list = prefs.getStringList('completed_tasks_$today') ?? [];
    return list.map((e) => int.tryParse(e) ?? -1).toSet();
  }

  /// 讀取提醒＋完成集。網路／後端失敗會**丟出例外**（不再當成「沒有提醒」）。
  static Future<TodayTasksData> load(String elderId) async {
    final completed = await loadCompletedIds();
    final list = await ApiService.getElderReminders(elderId);
    return TodayTasksData(List<Map<String, dynamic>>.from(list), completed);
  }
}
