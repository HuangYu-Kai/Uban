// 連勝紀錄（StreakService）單元測試：連續天數、跨週、中斷歸零、全部完成判斷、
// 慶祝只放一次、取消打卡移除當天紀錄、胡蘿蔔數。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/streak/streak_service.dart';

// 2026-10-01 是星期四；本週一是 09-28，週日是 10-04。
final DateTime _thu = DateTime(2026, 10, 1, 9, 30);

List<Map<String, dynamic>> _reminders(int n) => [
      for (var i = 1; i <= n; i++)
        <String, dynamic>{
          'id': i,
          'title': '提醒$i',
          'time_str': '00:0$i',
          'repeat_days': '每天',
        },
    ];

void main() {
  group('buildSnapshot 連續天數', () {
    test('完全沒有紀錄：0 天、週條全空', () {
      final s = StreakService.buildSnapshot({}, _thu);
      expect(s.days, 0);
      expect(s.todayDone, isFalse);
      expect(s.week.length, 7);
      expect(s.week.map((d) => d.label).join(), '一二三四五六日');
      expect(s.week.where((d) => d.done), isEmpty);
      expect(s.week.where((d) => d.isToday).single.label, '四');
    });

    test('今天沒做、前三天連續：天數為 3（到昨天為止）', () {
      final s = StreakService.buildSnapshot(
          {'2026-09-30', '2026-09-29', '2026-09-28'}, _thu);
      expect(s.days, 3);
      expect(s.todayDone, isFalse);
    });

    test('今天也做完：天數含今天', () {
      final s = StreakService.buildSnapshot(
          {'2026-10-01', '2026-09-30', '2026-09-29'}, _thu);
      expect(s.days, 3);
      expect(s.todayDone, isTrue);
    });

    test('只有今天做完：1 天', () {
      expect(StreakService.buildSnapshot({'2026-10-01'}, _thu).days, 1);
    });

    test('跨週：連續天數不受週一切換影響，週條只顯示本週', () {
      // 09-26(六)、09-27(日) 在上週；本週一 09-28、二 09-29、三 09-30、今天四 10-01。
      final done = {
        '2026-09-26',
        '2026-09-27',
        '2026-09-28',
        '2026-09-29',
        '2026-09-30',
        '2026-10-01',
      };
      final s = StreakService.buildSnapshot(done, _thu);
      expect(s.days, 6);
      expect(s.week.map((d) => d.done).toList(),
          [true, true, true, true, false, false, false]);
    });

    test('跨月：9/30 → 10/1 仍連續', () {
      final s = StreakService.buildSnapshot({'2026-09-30', '2026-10-01'}, _thu);
      expect(s.days, 2);
    });

    test('中斷歸零：昨天沒做，今天也沒做 → 0；前天以前的紀錄不算', () {
      final s =
          StreakService.buildSnapshot({'2026-09-29', '2026-09-28'}, _thu);
      expect(s.days, 0);
    });

    test('中斷後重新開始：只算中斷之後', () {
      // 09-27 做、09-28 沒做、09-29/09-30 做 → 到昨天連續 2 天。
      final s = StreakService.buildSnapshot(
          {'2026-09-27', '2026-09-29', '2026-09-30'}, _thu);
      expect(s.days, 2);
    });

    test('週日當天：週條最後一格是今天', () {
      final sun = DateTime(2026, 10, 4, 20);
      final s = StreakService.buildSnapshot({'2026-10-04'}, sun);
      expect(s.week.last.label, '日');
      expect(s.week.last.isToday, isTrue);
      expect(s.week.last.done, isTrue);
    });

    test('dayKey 補零', () {
      expect(StreakService.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('allDoneToday', () {
    test('沒有提醒不算完成（避免憑空連勝）', () {
      expect(StreakService.allDoneToday([], {}, _thu), isFalse);
    });

    test('全部完成才算', () {
      final r = _reminders(2);
      expect(StreakService.allDoneToday(r, {1}, _thu), isFalse);
      expect(StreakService.allDoneToday(r, {1, 2}, _thu), isTrue);
    });
  });

  group('carrotsEarned（沿用胡蘿蔔帳本：1 次打卡 1 根、上限 5，至少顯示 1）', () {
    test('各數量', () {
      expect(StreakService.carrotsEarned(0), 1);
      expect(StreakService.carrotsEarned(1), 1);
      expect(StreakService.carrotsEarned(3), 3);
      expect(StreakService.carrotsEarned(5), 5);
      expect(StreakService.carrotsEarned(9), 5);
    });
  });

  group('syncToday（讀寫 SharedPreferences）', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('還沒全部完成：不寫入、不慶祝', () async {
      final c = await StreakService.syncToday(
          reminders: _reminders(2), completedIds: {1}, now: _thu);
      expect(c, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('all_done_2026-10-01'), isFalse);
    });

    test('全部完成：寫入 all_done、回傳慶祝；同一天第二次不再慶祝', () async {
      SharedPreferences.setMockInitialValues({
        'all_done_2026-09-30': true,
        'all_done_2026-09-29': true,
      });
      final first = await StreakService.syncToday(
          reminders: _reminders(3), completedIds: {1, 2, 3}, now: _thu);
      expect(first, isNotNull);
      expect(first!.fromDays, 2);
      expect(first.toDays, 3);
      expect(first.earnedCarrots, 3);
      expect(first.weekAfter.where((d) => d.isToday).single.done, isTrue);
      expect(first.weekBefore.where((d) => d.isToday).single.done, isFalse,
          reason: '慶祝開始時今天那格還沒補上');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('all_done_2026-10-01'), isTrue);

      final second = await StreakService.syncToday(
          reminders: _reminders(3), completedIds: {1, 2, 3}, now: _thu);
      expect(second, isNull, reason: '今天已慶祝過');
    });

    test('取消打卡：移除當天 all_done，連勝同步減少，且之後重打不會再慶祝', () async {
      await StreakService.syncToday(
          reminders: _reminders(2), completedIds: {1, 2}, now: _thu);
      var snap = await StreakService.load(now: _thu);
      expect(snap.todayDone, isTrue);

      final undone = await StreakService.syncToday(
          reminders: _reminders(2), completedIds: {1}, now: _thu);
      expect(undone, isNull);
      snap = await StreakService.load(now: _thu);
      expect(snap.todayDone, isFalse);
      expect(snap.days, 0);

      final again = await StreakService.syncToday(
          reminders: _reminders(2), completedIds: {1, 2}, now: _thu);
      expect(again, isNull, reason: '慶祝旗標不清除，避免反覆取消／重打製造重複慶祝');
      snap = await StreakService.load(now: _thu);
      expect(snap.todayDone, isTrue, reason: '但連勝紀錄會恢復');
    });

    test('寫入後 changes 通知遞增', () async {
      final before = StreakService.changes.value;
      await StreakService.syncToday(
          reminders: _reminders(1), completedIds: {1}, now: _thu);
      expect(StreakService.changes.value, greaterThan(before));
    });
  });
}
