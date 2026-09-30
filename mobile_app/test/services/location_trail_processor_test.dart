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

  group('時間軸事件與停留群集', () {
    // 在 (north, east) 附近停留，每分鐘一點、數公尺抖動。
    List<TrailPoint> stayAt(double north, double east, int fromMin, int toMin) {
      return [
        for (int m = fromMin; m <= toMin; m++)
          _pt(north + (m.isEven ? 3 : -3), east + (m % 3 - 1) * 3.0, Duration(minutes: m)),
      ];
    }

    List<TrailPoint> scenario() => [
          // 走 5 分鐘
          for (int k = 0; k < 5; k++) _pt(0, k * 90.0, Duration(minutes: k)),
          // 停留 7 分鐘
          ...stayAt(0, 450, 5, 12),
          // 再走
          for (int k = 0; k < 5; k++) _pt(0, 540 + k * 90.0, Duration(minutes: 13 + k)),
          // 靜默 2 小時後出現在 3 公里外，再走
          for (int k = 0; k < 4; k++)
            _pt(3000, 3000 + k * 90.0, Duration(hours: 2, minutes: 20 + k)),
        ];

    test('事件順序：depart, move, stay, move, gap, move', () {
      final t = LocationTrailProcessor.process(scenario());
      expect(t.events.map((e) => e.type).toList(), [
        TrailEventType.depart,
        TrailEventType.move,
        TrailEventType.stay,
        TrailEventType.move,
        TrailEventType.gap,
        TrailEventType.move,
      ]);
      expect(t.events[2].stay, same(t.stays.first));
      expect(t.events[1].points.length, greaterThanOrEqualTo(2));
      expect(t.events[3].points.length, greaterThanOrEqualTo(2));
      expect(t.events[4].points.length, 2);
    });

    test('所有 move 距離加總 = totalDistanceMeters', () {
      final t = LocationTrailProcessor.process(scenario());
      final sum = t.events
          .where((e) => e.type == TrailEventType.move)
          .fold<double>(0, (a, e) => a + e.distanceMeters);
      expect(sum, greaterThan(0));
      expect(sum, closeTo(t.totalDistanceMeters, 1));
    });

    test('同地三次停留（相距不超過 80 公尺）-> 1 個群集', () {
      final raw = <TrailPoint>[
        ...stayAt(0, 0, 0, 6),
        _pt(0, 100, const Duration(minutes: 7)),
        _pt(0, 200, const Duration(minutes: 8)),
        _pt(0, 300, const Duration(minutes: 9)),
        _pt(0, 200, const Duration(minutes: 10)),
        _pt(0, 130, const Duration(minutes: 11)),
        ...stayAt(0, 60, 12, 18),
        _pt(40, 160, const Duration(minutes: 19)),
        _pt(40, 260, const Duration(minutes: 20)),
        _pt(40, 200, const Duration(minutes: 21)),
        _pt(40, 130, const Duration(minutes: 22)),
        ...stayAt(40, 0, 23, 29),
      ];
      final t = LocationTrailProcessor.process(raw);
      expect(t.stays.length, 3);
      expect(t.stayClusters.length, 1);
      final c = t.stayClusters.first;
      expect(c.count, 3);
      final sum = t.stays.fold<Duration>(Duration.zero, (a, s) => a + s.duration);
      expect(c.totalDuration, sum);
    });

    test('兩個停留相距 1 公里 -> 2 個群集', () {
      final raw = <TrailPoint>[
        ...stayAt(0, 0, 0, 6),
        for (int k = 1; k <= 9; k++) _pt(0, k * 100.0, Duration(minutes: 6 + k)),
        ...stayAt(0, 1000, 16, 22),
      ];
      final t = LocationTrailProcessor.process(raw);
      expect(t.stays.length, 2);
      expect(t.stayClusters.length, 2);
    });

    test('空輸入：events 與 stayClusters 皆為空', () {
      final t = LocationTrailProcessor.process([]);
      expect(t.events, isEmpty);
      expect(t.stayClusters, isEmpty);
    });
  });
}
