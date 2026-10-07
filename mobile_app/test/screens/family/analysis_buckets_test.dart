import 'package:flutter_application_1/screens/family/home/models/analysis_buckets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 7);

  test('lastDays 回傳舊到新共 7 天', () {
    final d = AnalysisBuckets.lastDays(today);
    expect(d.length, 7);
    expect(d.first, DateTime(2026, 10, 1));
    expect(d.last, today);
  });

  test('bucketDaily 缺的日子是 null，不補 0', () {
    final r = AnalysisBuckets.bucketDaily([
      {'date': '2026-10-05', 'steps': 4000},
      {'date': '2026-10-06', 'steps': null},
      {'date': '2026-10-07T00:00:00', 'steps': 2000},
    ], 'steps', today);
    expect(r.length, 7);
    expect(r[4].value, 4000);
    expect(r[5].value, isNull);
    expect(r[6].value, 2000);
    expect(r[0].value, isNull);
  });

  test('stepsSummary 平均只算有資料的日子並標出最多的一天', () {
    final r = AnalysisBuckets.bucketDaily([
      {'date': '2026-10-05', 'steps': 4000},
      {'date': '2026-10-07', 'steps': 6000},
    ], 'steps', today);
    expect(AnalysisBuckets.stepsSummary(r), '有資料的 2 天平均 5,000 步，最多 10/7 6,000 步');
    expect(AnalysisBuckets.stepsSummary(AnalysisBuckets.bucketDaily([], 'steps', today)), isNull);
  });

  test('outingSummary 有家 / 沒家', () {
    final r = AnalysisBuckets.bucketDaily([
      {'date': '2026-10-05', 'outing_count': 2},
      {'date': '2026-10-06', 'outing_count': 0},
      {'date': '2026-10-07', 'outing_count': 1},
    ], 'outing_count', today);
    expect(AnalysisBuckets.outingSummary(r, hasHome: true), '這 7 天外出 2 天，共 3 次');
    expect(AnalysisBuckets.outingSummary(r, hasHome: false), contains('還沒設定'));
  });

  test('bucketEvents 依當地日期分桶、略過壞資料', () {
    String z(int d, int h) => DateTime(2026, 10, d, h).toUtc().toIso8601String();
    final r = AnalysisBuckets.bucketEvents([
      {'timestamp': z(7, 9)},
      {'timestamp': z(7, 15)},
      {'timestamp': z(5, 12)},
      {'timestamp': z(1, 12) .replaceFirst('2026-10-01', '2026-09-20')},
      {'timestamp': 'garbage'},
    ], today);
    expect(r.last.value, 2);
    expect(r[4].value, 1);
    expect(r[5].value, 0);
    expect(AnalysisBuckets.emotionSummary(r, 4), '這 7 天有 3 次需要關心的情緒；已珍藏 4 篇人生故事');
  });
}
