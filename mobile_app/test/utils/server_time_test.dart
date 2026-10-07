// ServerTime：後端沒帶時區的時間字串視為 UTC 再轉本地。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/server_time.dart';

void main() {
  test('沒帶時區 → 當成 UTC', () {
    final d = ServerTime.parse('2026-10-07T01:38:43')!;
    expect(d.isUtc, isFalse);
    expect(d.toUtc(), DateTime.utc(2026, 10, 7, 1, 38, 43));
  });

  test('空白分隔的 MySQL 格式也可以', () {
    expect(ServerTime.parse('2026-10-07 01:38:43')!.toUtc(),
        DateTime.utc(2026, 10, 7, 1, 38, 43));
  });

  test('已帶 Z 或 +08:00 照原樣解析', () {
    expect(ServerTime.parse('2026-10-07T01:38:43Z')!.toUtc(),
        DateTime.utc(2026, 10, 7, 1, 38, 43));
    expect(ServerTime.parse('2026-10-07T09:38:43+08:00')!.toUtc(),
        DateTime.utc(2026, 10, 7, 1, 38, 43));
  });

  test('空值與壞字串回 null', () {
    expect(ServerTime.parse(null), isNull);
    expect(ServerTime.parse(''), isNull);
    expect(ServerTime.parse('not a date'), isNull);
  });

  test('dateKey／clock 補零', () {
    final d = DateTime(2026, 1, 5, 7, 3);
    expect(ServerTime.dateKey(d), '2026-01-05');
    expect(ServerTime.clock(d), '07:03');
  });
}
