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
/// - **後端是權威**：`GET /reminder/elder/{id}/all-done-dates` 回傳最近 [serverWindowDays]
///   天的「全部完成」日（後端在打卡當下寫快照，事後停用／刪除提醒不會回溯改寫）。
///   後端讀得到時，窗口內本機有、後端沒有的日期一律刪掉——過去只增不減，幽靈天會永久存在。
/// - 本機 SharedPreferences `all_done_<elderId>_<yyyy-MM-dd>` 只是離線快取與窗口外的延續；
///   鍵帶 elderId，同一支手機換過長輩帳號不會繼承別人的天數。舊的不帶 elderId 的鍵
///   （`all_done_<date>`／`streak_celebrated_<date>`）在 [load] 時清掉、不再採用。
/// - `streak_celebrated_<elderId>_<yyyy-MM-dd>` 記錄今天是否已放過慶祝，避免同一天重複。
/// - 這個類別只做資料與判斷，不碰畫面、不改打卡本身的邏輯。
class StreakService {
  StreakService._();

  static const String allDonePrefix = 'all_done_';
  static const String celebratedPrefix = 'streak_celebrated_';
  static const int serverWindowDays = 60;
  static const List<String> weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  static final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// 每次寫入連勝紀錄後遞增，讓已建好的畫面（IndexedStack 保活的「我的」）重讀。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 本機日期 → `yyyy-MM-dd`。
  static String dayKey(DateTime d) {
    String p(int n, int w) => n.toString().padLeft(w, '0');
    return '${p(d.year, 4)}-${p(d.month, 2)}-${p(d.day, 2)}';
  }

  static String doneKey(String elderId, String day) =>
      '$allDonePrefix${elderId}_$day';

  static String celebratedKey(String elderId, String day) =>
      '$celebratedPrefix${elderId}_$day';

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

  static Set<String> _readDoneKeys(SharedPreferences prefs, String elderId) {
    final prefix = '$allDonePrefix${elderId}_';
    final out = <String>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith(prefix) && prefs.getBool(k) == true) {
        final d = k.substring(prefix.length);
        if (_dateRe.hasMatch(d)) out.add(d);
      }
    }
    return out;
  }

  /// 清掉舊版不帶 elderId 的鍵（`all_done_<date>`／`streak_celebrated_<date>`）：
  /// 它們分不出是哪位長輩的，繼續採用就會把別人的天數算進來。
  static Future<void> _purgeLegacyKeys(SharedPreferences prefs) async {
    for (final k in prefs.getKeys().toList()) {
      for (final prefix in const [allDonePrefix, celebratedPrefix]) {
        if (k.startsWith(prefix) && _dateRe.hasMatch(k.substring(prefix.length))) {
          await prefs.remove(k);
        }
      }
    }
  }

  /// 讀取連勝卡資料。
  ///
  /// 沒有 [elderId]（還沒解析出長輩）時回傳 0 天、不讀本機——等 id 出來再讀。
  /// 後端讀取成功：窗口內以後端為準（同步增刪本機鍵）；失敗才只用本機。
  /// [fetchServerDates] 供單元測試注入。
  static Future<StreakSnapshot> load({
    DateTime? now,
    String? elderId,
    Future<List<String>> Function(String elderId, String until)?
        fetchServerDates,
  }) async {
    final t = now ?? DateTime.now();
    if (elderId == null || elderId.isEmpty) return buildSnapshot({}, t);
    final prefs = await SharedPreferences.getInstance();
    await _purgeLegacyKeys(prefs);
    var keys = _readDoneKeys(prefs, elderId);
    try {
      final until = dayKey(t);
      final fetch = fetchServerDates ??
          (id, u) =>
              ApiService.getAllDoneDates(id, until: u, days: serverWindowDays);
      final server = await fetch(elderId, until);
      final r = reconcileWithServer(keys, server, t);
      for (final d in r.add) {
        await prefs.setBool(doneKey(elderId, d), true);
      }
      for (final d in r.remove) {
        await prefs.remove(doneKey(elderId, d));
      }
      keys = {...keys.difference(r.remove), ...r.add};
    } catch (e) {
      debugPrint('⚠️ [StreakService] 後端連勝日期讀取失敗，僅用本機: $e');
    }
    return buildSnapshot(keys, t);
  }

  /// 純函式：後端在窗口（今天往回 [serverWindowDays] 天）內是權威。
  /// 回傳要寫入本機的日期（後端有、本機沒有、格式合法）與要刪掉的日期
  /// （窗口內本機有、後端沒有）。窗口外的本機日期保留，讓超過 60 天的連勝能延續。
  static ({Set<String> add, Set<String> remove}) reconcileWithServer(
      Set<String> local, Iterable<String> server, DateTime now) {
    final serverSet = {
      for (final d in server)
        if (_dateRe.hasMatch(d)) d,
    };
    final today = DateTime(now.year, now.month, now.day);
    final windowStart = dayKey(shiftDay(today, -(serverWindowDays - 1)));
    final until = dayKey(today);
    return (
      add: serverSet.difference(local),
      remove: {
        for (final d in local)
          if (d.compareTo(windowStart) >= 0 &&
              d.compareTo(until) <= 0 &&
              !serverSet.contains(d))
            d,
      },
    );
  }

  /// 打卡「成功之後」呼叫：依今天的提醒完成狀況更新紀錄。
  ///
  /// - 全部完成：寫入今天的 `all_done`；若今天尚未慶祝過，**以後端校正後的天數**
  ///   （[load]）組成 [StreakCelebration] 回傳並標記已慶祝——慶祝畫面上的「連續 N 天」
  ///   與「我的」分頁連勝卡是同一個數字。後端若說今天其實沒全部完成，就不慶祝。
  /// - 尚未全部完成（含取消打卡）：移除今天的 `all_done`，連勝才不會被取消後的
  ///   狀態灌水；慶祝旗標不清除，避免反覆取消／重打製造重複慶祝。
  /// - 沒有 [elderId] 不寫也不慶祝。
  /// 任何例外都吞掉並回傳 null——連勝是附加功能，不能影響打卡。
  static Future<StreakCelebration?> syncToday({
    required List<Map<String, dynamic>> reminders,
    required Set<int> completedIds,
    required String? elderId,
    DateTime? now,
    Future<List<String>> Function(String elderId, String until)?
        fetchServerDates,
  }) async {
    try {
      if (elderId == null || elderId.isEmpty) return null;
      final t = now ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final key = doneKey(elderId, dayKey(t));
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

      final celebrated = celebratedKey(elderId, dayKey(t));
      if (prefs.getBool(celebrated) == true) {
        if (!wasMarked) changes.value++;
        return null;
      }

      final snap = await load(
          now: t, elderId: elderId, fetchServerDates: fetchServerDates);
      changes.value++;
      if (!snap.todayDone) return null;
      await prefs.setBool(celebrated, true);

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
