import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../utils/reminder_schedule.dart';
import '../../pet_companion_studio/models/pet_food_item.dart';

/// 本週（週一到週日）其中一天的狀態。
class StreakWeekDay {
  /// 一～日。
  final String label;
  final bool done;
  final bool isToday;

  const StreakWeekDay({
    required this.label,
    required this.done,
    required this.isToday,
  });
}

/// 連勝卡要顯示的資料。
class StreakSnapshot {
  /// 連續天數：今天已完成就含今天；今天還沒完成就是「到昨天為止」的天數。
  final int days;
  final bool todayDone;

  /// 週一到週日共 7 筆。
  final List<StreakWeekDay> week;

  const StreakSnapshot({
    required this.days,
    required this.todayDone,
    required this.week,
  });
}

/// 慶祝畫面要用的資料（今天剛好全部完成、且今天還沒慶祝過才會產生）。
class StreakCelebration {
  /// 慶祝前的天數（不含今天）。
  final int fromDays;

  /// 慶祝後的天數（含今天）。
  final int toDays;

  /// 週條（今天已補上）。
  final List<StreakWeekDay> weekAfter;

  /// 今天打卡賺到的胡蘿蔔數（至少 1）。
  final int earnedCarrots;

  const StreakCelebration({
    required this.fromDays,
    required this.toDays,
    required this.weekAfter,
    required this.earnedCarrots,
  });

  /// 慶祝開始時的週條：同一週但今天還沒補上。
  List<StreakWeekDay> get weekBefore => [
        for (final d in weekAfter)
          StreakWeekDay(
            label: d.label,
            done: d.isToday ? false : d.done,
            isToday: d.isToday,
          ),
      ];
}

/// 連勝紀錄（新功能）：每天「所有提醒都完成」就算一天，連續天數往回數。
///
/// - 存 SharedPreferences `all_done_<yyyy-MM-dd>`（本機日期，與
///   `completed_tasks_<yyyy-MM-dd>` 同一種日期寫法）；`load` 傳入 elderId 時會再與後端
///   `all-done-dates` 取聯集（跨裝置），並把後端日期寫回本機鍵供離線顯示。
/// - `streak_celebrated_<yyyy-MM-dd>` 記錄今天是否已放過慶祝，避免同一天重複。
/// - 這個類別只做資料與判斷，不碰畫面、不改打卡本身的邏輯。
class StreakService {
  StreakService._();

  static const String allDonePrefix = 'all_done_';
  static const String celebratedPrefix = 'streak_celebrated_';
  static const List<String> weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  /// 每次寫入連勝紀錄後遞增，讓已建好的畫面（IndexedStack 保活的「我的」）重讀。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 本機日期 → `yyyy-MM-dd`。
  static String dayKey(DateTime d) {
    String p(int n, int w) => n.toString().padLeft(w, '0');
    return '${p(d.year, 4)}-${p(d.month, 2)}-${p(d.day, 2)}';
  }

  /// 往前（負）或往後（正）[delta] 天，用日曆日運算避開夏令時間的 24 小時誤差。
  static DateTime shiftDay(DateTime d, int delta) =>
      DateTime(d.year, d.month, d.day + delta);

  /// 今天的提醒是否「全部完成」：至少有一筆今天適用的提醒，且沒有任何一筆還沒做。
  /// 沒有提醒（total == 0）不算完成，否則沒設提醒的長輩會憑空獲得連勝。
  static bool allDoneToday(
    List<Map<String, dynamic>> reminders,
    Set<int> completedIds,
    DateTime now,
  ) {
    final g = groupByStatus(reminders, completedIds, now);
    return g.done.isNotEmpty && g.dueNow.isEmpty && g.later.isEmpty;
  }

  /// 純函式：由「已完成的日期集合」算出連勝卡資料（方便單元測試）。
  static StreakSnapshot buildSnapshot(Set<String> doneKeys, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final todayDone = doneKeys.contains(dayKey(today));

    var days = todayDone ? 1 : 0;
    var cursor = shiftDay(today, -1);
    // 上限 3650 天，防止異常資料造成無限迴圈。
    for (var i = 0; i < 3650 && doneKeys.contains(dayKey(cursor)); i++) {
      days++;
      cursor = shiftDay(cursor, -1);
    }

    // 本週：週一為第一天（DateTime.monday == 1）。
    final monday = shiftDay(today, -(today.weekday - DateTime.monday));
    final week = <StreakWeekDay>[
      for (var i = 0; i < 7; i++)
        () {
          final d = shiftDay(monday, i);
          return StreakWeekDay(
            label: weekLabels[i],
            done: doneKeys.contains(dayKey(d)),
            isToday: d == today,
          );
        }(),
    ];
    return StreakSnapshot(days: days, todayDone: todayDone, week: week);
  }

  /// 今天打卡賺到的胡蘿蔔數：沿用胡蘿蔔帳本的規則（1 次打卡 1 根、每日上限 5，
  /// 見 `PetFoodItem.earnedCountFor`），不打後端；慶祝畫面至少顯示 1。
  static int carrotsEarned(int checkinsToday) {
    var n = checkinsToday.clamp(0, 5);
    for (final f in PetFoodItem.milestoneMenu) {
      if (f.id == 'carrot' && f.isEarnedQuantity) {
        n = f.earnedCountFor(steps: 0, checkins: checkinsToday);
        break;
      }
    }
    return n < 1 ? 1 : n;
  }

  static Future<Set<String>> _readDoneKeys(SharedPreferences prefs) async {
    final out = <String>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith(allDonePrefix) && prefs.getBool(k) == true) {
        out.add(k.substring(allDonePrefix.length));
      }
    }
    return out;
  }

  /// 讀取連勝卡資料。
  ///
  /// 有 [elderId] 時額外向後端要「全部完成」的日期，與本機取聯集並寫回本機
  /// `all_done_` 鍵；後端失敗只用本機。[fetchServerDates] 供單元測試注入。
  static Future<StreakSnapshot> load({
    DateTime? now,
    String? elderId,
    Future<List<String>> Function(String elderId, String until)?
        fetchServerDates,
  }) async {
    final t = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    var keys = await _readDoneKeys(prefs);
    if (elderId != null && elderId.isNotEmpty) {
      try {
        final until = dayKey(t);
        final fetch = fetchServerDates ??
            (id, u) => ApiService.getAllDoneDates(id, until: u, days: 60);
        final server = await fetch(elderId, until);
        final fresh = mergeServerDates(keys, server);
        for (final d in fresh) {
          await prefs.setBool('$allDonePrefix$d', true);
        }
        if (fresh.isNotEmpty) keys = {...keys, ...fresh};
      } catch (e) {
        debugPrint('⚠️ [StreakService] 後端連勝日期讀取失敗，僅用本機: $e');
      }
    }
    return buildSnapshot(keys, t);
  }

  /// 純函式：後端日期中「本機還沒有」且格式合法的部分（需寫回本機）。
  static Set<String> mergeServerDates(
      Set<String> local, Iterable<String> server) {
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return {
      for (final d in server)
        if (re.hasMatch(d) && !local.contains(d)) d,
    };
  }

  /// 打卡「成功之後」呼叫：依今天的提醒完成狀況更新紀錄。
  ///
  /// - 全部完成：寫入 `all_done_<今天>`；若今天尚未慶祝過，回傳 [StreakCelebration]
  ///   並標記已慶祝。
  /// - 尚未全部完成（含取消打卡）：移除今天的 `all_done`，連勝才不會被取消後的
  ///   狀態灌水；慶祝旗標不清除，避免反覆取消／重打製造重複慶祝。
  /// 任何 SharedPreferences 例外都吞掉並回傳 null——連勝是附加功能，不能影響打卡。
  static Future<StreakCelebration?> syncToday({
    required List<Map<String, dynamic>> reminders,
    required Set<int> completedIds,
    DateTime? now,
  }) async {
    try {
      final t = now ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final key = '$allDonePrefix${dayKey(t)}';
      final allDone = allDoneToday(reminders, completedIds, t);

      if (!allDone) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          changes.value++;
        }
        return null;
      }

      final wasMarked = prefs.getBool(key) == true;
      await prefs.setBool(key, true);
      if (!wasMarked) changes.value++;

      final celebratedKey = '$celebratedPrefix${dayKey(t)}';
      if (prefs.getBool(celebratedKey) == true) return null;
      await prefs.setBool(celebratedKey, true);

      final snap = buildSnapshot(await _readDoneKeys(prefs), t);
      final checkins = groupByStatus(reminders, completedIds, t).done.length;
      return StreakCelebration(
        fromDays: snap.days - 1,
        toDays: snap.days,
        weekAfter: snap.week,
        earnedCarrots: carrotsEarned(checkins),
      );
    } catch (e) {
      debugPrint('⚠️ [StreakService] syncToday 失敗（不影響打卡）: $e');
      return null;
    }
  }
}
