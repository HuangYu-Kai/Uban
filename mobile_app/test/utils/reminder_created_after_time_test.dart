import 'package:flutter_application_1/utils/reminder_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 建立當天、提醒時間已過 → 從下一次開始算（與後端 _created_on_or_before 同規則）。
void main() {
  // 用本地時間建立再轉成 UTC 字串，測試與執行環境的時區無關。
  String utc(DateTime local) => local.toUtc().toIso8601String();

  Map<String, dynamic> r(String time, DateTime createdLocal) => {
        'id': 1,
        'time_str': time,
        'repeat_days': '每天',
        'created_at': utc(createdLocal),
      };

  final now = DateTime(2026, 10, 8, 22, 0);

  test('晚上才建立的「每天 9 點」今天不算，明天才算', () {
    final rem = r('09:00', DateTime(2026, 10, 8, 21, 52));
    expect(appliesToday(rem, now), isFalse);
    expect(appliesToday(rem, DateTime(2026, 10, 9, 8, 0)), isTrue);
  });

  test('早上建立、提醒時間還沒到 → 今天就算', () {
    expect(appliesToday(r('09:00', DateTime(2026, 10, 8, 8, 30)), now), isTrue);
    expect(appliesToday(r('09:00', DateTime(2026, 10, 8, 9, 0, 40)), now), isTrue);
  });

  test('以前建立的提醒不受影響；後端時間不帶 Z 也視為 UTC', () {
    expect(appliesToday(r('09:00', DateTime(2026, 10, 1, 23, 0)), now), isTrue);
    final noZone = {
      'id': 2,
      'time_str': '09:00',
      'repeat_days': '每天',
      'created_at': utc(DateTime(2026, 10, 8, 21, 52)).replaceAll('Z', ''),
    };
    expect(appliesToday(noZone, now), isFalse);
  });

  test('缺 created_at 或時間格式不對 → 維持舊行為（算今天）', () {
    expect(appliesToday({'id': 3, 'time_str': '09:00', 'repeat_days': '每天'}, now), isTrue);
    expect(
        appliesToday({
          'id': 4,
          'time_str': '早上',
          'repeat_days': '每天',
          'created_at': utc(DateTime(2026, 10, 8, 21, 0)),
        }, now),
        isTrue);
  });
}
