import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_application_1/services/location_trail_processor.dart';

// 約 1e-5 度 ≈ 1.1 公尺
const double _lat0 = 25.0418;
const double _lng0 = 121.5300;
const double _degPerM = 1e-5 / 1.11;

final DateTime _t0 = DateTime(2026, 9, 30, 10, 0);

TrailPoint _pt(double northM, double eastM, Duration at, {double? acc}) {
  return TrailPoint(
    position: LatLng(_lat0 + northM * _degPerM, _lng0 + eastM * _degPerM / math.cos(_lat0 * math.pi / 180)),
    time: _t0.add(at),
    accuracyM: acc,
  );
}

void main() {
  test('室內漂移：20 點 30 分鐘只產生 1 個停留，路線收斂成單點', () {
    final raw = <TrailPoint>[];
    for (int k = 0; k < 20; k++) {
      final r = 25 * (0.3 + 0.7 * ((k * 7 % 10) / 10));
      final a = k * 2.4;
      raw.add(_pt(r * math.sin(a), r * math.cos(a), Duration(seconds: k * 95)));
    }
    final t = LocationTrailProcessor.process(raw);
    expect(t.stays.length, 1);
    expect(t.segments.length, 1);
    expect(t.segments.first.points.length, 1);
    expect(t.gaps, isEmpty);
    expect(t.totalDistanceMeters, 0);
  });

  test('單一尖刺與速度離群點被剔除', () {
    final raw = <TrailPoint>[
      for (int k = 0; k < 10; k++) _pt(0, k * 80.0, Duration(minutes: k)),
    ];
    // 第 5 點側向偏移 400 公尺
    raw[5] = _pt(400, 5 * 80.0, const Duration(minutes: 5));
    var t = LocationTrailProcessor.process(raw);
    final maxNorth = t.allPoints
        .map((p) => (p.latitude - _lat0) / _degPerM)
        .reduce(math.max);
    expect(maxNorth, lessThan(20));
    expect(t.totalDistanceMeters, closeTo(9 * 80, 9 * 80 * 0.05));

    // 5 秒內跳 1 公里
    final raw2 = <TrailPoint>[
      for (int k = 0; k < 10; k++) _pt(0, k * 80.0, Duration(minutes: k)),
    ];
    raw2.insert(5, _pt(1000, 400, const Duration(minutes: 4, seconds: 5)));
    t = LocationTrailProcessor.process(raw2);
    final maxNorth2 = t.allPoints
        .map((p) => (p.latitude - _lat0) / _degPerM)
        .reduce(math.max);
    expect(maxNorth2, lessThan(20));
  });

  test('斷訊：走 10 分鐘、靜默 2 小時、到 3 公里外 -> 2 段 1 個缺口', () {
    final raw = <TrailPoint>[
      for (int k = 0; k <= 10; k++) _pt(0, k * 90.0, Duration(minutes: k)),
      for (int k = 0; k <= 10; k++)
        _pt(3000, 3000 + k * 90.0, Duration(hours: 2, minutes: 10 + k)),
    ];
    final t = LocationTrailProcessor.process(raw);
    expect(t.segments.length, 2);
    expect(t.gaps.length, 1);
    expect(t.stays, isEmpty);
  });

  test('同地長時間靜默：10:00 與 10:40 相距 20 公尺 -> 約 40 分鐘停留', () {
    final raw = [
      _pt(0, 0, Duration.zero),
      _pt(0, 20, const Duration(minutes: 40)),
    ];
    final t = LocationTrailProcessor.process(raw);
    expect(t.stays.length, 1);
    expect(t.stays.first.duration.inMinutes, 40);
    expect(t.gaps, isEmpty);
  });

  test('正常步行 100 點近乎共線：大幅簡化且距離保留', () {
    final raw = <TrailPoint>[
      for (int k = 0; k < 100; k++)
        _pt((k.isEven ? 1.0 : -1.0), k * 14.0, Duration(seconds: k * 10)),
    ];
    final t = LocationTrailProcessor.process(raw);
    expect(t.segments.length, 1);
    expect(t.segments.first.points.length, lessThan(10));
    final expected = 99 * 14.0;
    expect(t.totalDistanceMeters, closeTo(expected, expected * 0.05));
  });

  test('空輸入與單點輸入不會崩潰', () {
    final empty = LocationTrailProcessor.process([]);
    expect(empty.isEmpty, isTrue);
    expect(empty.allPoints, isEmpty);

    final one = LocationTrailProcessor.process([_pt(0, 0, Duration.zero)]);
    expect(one.isEmpty, isFalse);
    expect(one.allPoints.length, 1);
    expect(one.totalDistanceMeters, 0);
  });
}
