// lib/services/location_trail_processor.dart
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'api/location_api.dart';

/// 後端 `/trail` 回傳的單一原始定位點。
class TrailPoint {
  final LatLng position;
  final DateTime time;

  /// GPS 水平精確度（公尺），後端可能沒有這個欄位。
  final double? accuracyM;

  const TrailPoint({required this.position, required this.time, this.accuracyM});

  /// 座標或時間缺漏／無法解析時回傳 null（該點直接略過，不拋例外）。
  static TrailPoint? fromJson(Map p) {
    final lat = p['latitude'];
    final lng = p['longitude'];
    final time = LocationApi.parseRecordedAt(p['recorded_at']);
    if (lat is! num || lng is! num || time == null) return null;
    final acc = p['accuracy_m'];
    return TrailPoint(
      position: LatLng(lat.toDouble(), lng.toDouble()),
      time: time,
      accuracyM: acc is num ? acc.toDouble() : null,
    );
  }
}

/// 一段連續、有訊號的移動軌跡（已簡化）。
class TrailSegment {
  final List<LatLng> points;
  final DateTime start;
  final DateTime end;

  const TrailSegment({required this.points, required this.start, required this.end});
}

/// 兩段軌跡之間的訊號中斷（畫成虛線，不代表真的走過這條直線）。
class TrailGap {
  final LatLng from;
  final LatLng to;
  final DateTime fromTime;
  final DateTime toTime;

  const TrailGap({
    required this.from,
    required this.to,
    required this.fromTime,
    required this.toTime,
  });
}

/// 一次停留（長時間待在同一個地方）。
class StayPoint {
  final LatLng center;
  final DateTime start;
  final DateTime end;

  const StayPoint({required this.center, required this.start, required this.end});

  Duration get duration => end.difference(start);
}

/// 時間軸事件類型：出發、移動、停留、斷訊。
enum TrailEventType { depart, move, stay, gap }

/// 時間軸上的一個事件（依時間先後排列，供地圖畫面組成「今日行程」）。
class TrailEvent {
  final TrailEventType type;
  final DateTime start;
  final DateTime end;

  /// move：該段路線座標（含前一個錨點，未簡化）；stay／depart：[中心／位置]；
  /// gap：[斷訊前最後位置, 斷訊後第一個位置]。
  final List<LatLng> points;

  /// 僅 move 有值（沿 [points] 逐點累加的公尺數），其餘為 0。
  final double distanceMeters;

  /// 僅 stay 有值。
  final StayPoint? stay;

  const TrailEvent({
    required this.type,
    required this.start,
    required this.end,
    required this.points,
    this.distanceMeters = 0,
    this.stay,
  });

  Duration get duration => end.difference(start);
}

/// 同一個地方（例如住家、公園）的多次停留彙整。
class StayCluster {
  /// 成員停留中心的平均位置。
  final LatLng center;
  final List<StayPoint> stays;

  const StayCluster({required this.center, required this.stays});

  /// 所有停留時間加總。
  Duration get totalDuration =>
      stays.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// 停留次數。
  int get count => stays.length;
}

/// 處理完成的當日軌跡。
class ProcessedTrail {
  final List<TrailSegment> segments;
  final List<TrailGap> gaps;
  final List<StayPoint> stays;

  /// 依時間排序的事件：depart → (move / stay / gap)…。
  final List<TrailEvent> events;

  /// 相近位置的停留彙整（依首次出現順序）。
  final List<StayCluster> stayClusters;
  final TrailPoint? start;

  /// 各段 move 距離總和（簡化前、不含斷訊缺口）。
  final double totalDistanceMeters;
  final DateTime? firstTime;
  final DateTime? lastTime;

  const ProcessedTrail({
    this.segments = const [],
    this.gaps = const [],
    this.stays = const [],
    this.events = const [],
    this.stayClusters = const [],
    this.start,
    this.totalDistanceMeters = 0,
    this.firstTime,
    this.lastTime,
  });

  /// 所有需要被框進畫面的座標（供 CameraFit.bounds 使用）。
  List<LatLng> get allPoints {
    final pts = <LatLng>[
      for (final s in segments) ...s.points,
      for (final s in stays) s.center,
      for (final g in gaps) ...[g.from, g.to],
    ];
    final st = start;
    if (pts.isEmpty && st != null) pts.add(st.position);
    return pts;
  }

  /// 清理後沒有任何定位點。
  bool get isEmpty => start == null;
}

/// 讀取端的軌跡清理：離群點剔除、停留偵測、斷訊分段、線條簡化。
///
/// 純函式、不碰 UI；原始資料照存於後端，調參只需要改這裡的常數。
class LocationTrailProcessor {
  LocationTrailProcessor._();

  /// 相鄰兩點推算速度上限（公尺／秒）；超過視為 GPS 跳點。
  static const double maxSpeedMps = 40;

  /// 精確度誤差超過此值（公尺）的點只用來判斷停留，不畫進線裡。
  static const double lineAccuracyMaxM = 35;

  /// 尖刺判斷的最短來回距離（公尺）；A→B、B→C 都要超過才可能是尖刺，
  /// 同時也是「時間差為 0 的跳點」的距離門檻。
  static const double spikeMinLegM = 80;

  /// 停留半徑（公尺）：與起點相距在此範圍內視為同一個地方。
  static const double stayRadiusM = 50;

  /// 停留最短時間：在半徑內待滿這麼久才算一次停留。
  static const Duration stayMinDuration = Duration(minutes: 5);

  /// 斷訊判定的最短間隔：相鄰兩點相隔超過這麼久才可能是斷訊或長時間靜止。
  static const Duration gapMinDuration = Duration(minutes: 10);

  /// 斷訊判定的最短距離（公尺）：長時間沒回報但位置沒變，是「停留」而非斷訊
  /// （長輩裝置只在移動時回報）。
  static const double gapMinDistanceM = 200;

  /// 停留聚合半徑（公尺）：停留中心與既有群集中心相距在此範圍內視為同一個地方
  /// （比 [stayRadiusM] 寬，容許同一地點多次停留的 GPS 中心有偏移）。
  static const double stayClusterRadiusM = 100;

  /// Douglas-Peucker 簡化容差（公尺）。
  static const double simplifyToleranceM = 8;

  static const Distance _dist = Distance();

  static double _d(LatLng a, LatLng b) => _dist(a, b);

  static ProcessedTrail process(List<TrailPoint> raw) {
    if (raw.isEmpty) return const ProcessedTrail();

    // 1. 依時間排序
    final sorted = [...raw]..sort((a, b) => a.time.compareTo(b.time));

    // 2. 速度離群點剔除
    final speedOk = <TrailPoint>[];
    int consecutiveDrops = 0;
    for (final p in sorted) {
      if (speedOk.isEmpty) {
        speedOk.add(p);
        continue;
      }
      final last = speedOk.last;
      final d = _d(last.position, p.position);
      final secs = p.time.difference(last.time).inMilliseconds / 1000.0;
      final outlier = secs <= 0 ? d > spikeMinLegM : d / secs > maxSpeedMps;
      // 連續丟掉 3 點以上，代表錨點本身可能才是壞點，改以目前的點當新錨點。
      if (outlier && consecutiveDrops < 3) {
        consecutiveDrops++;
        continue;
      }
      consecutiveDrops = 0;
      speedOk.add(p);
    }

    // 3. 尖刺剔除（一輪）
    final pts = <TrailPoint>[];
    for (int i = 0; i < speedOk.length; i++) {
      if (i == 0 || i == speedOk.length - 1) {
        pts.add(speedOk[i]);
        continue;
      }
      final a = pts.last.position;
      final b = speedOk[i].position;
      final c = speedOk[i + 1].position;
      final ab = _d(a, b);
      final bc = _d(b, c);
      final ac = _d(a, c);
      final isSpike = ab > spikeMinLegM &&
          bc > spikeMinLegM &&
          ac < 0.5 * math.min(ab, bc);
      if (!isSpike) pts.add(speedOk[i]);
    }

    final n = pts.length;

    // 4. 停留偵測（以索引區間表示）
    final ranges = <List<int>>[];
    int i = 0;
    while (i < n) {
      int j = i + 1;
      while (j < n && _d(pts[i].position, pts[j].position) <= stayRadiusM) {
        j++;
      }
      final last = j - 1;
      if (last > i && pts[last].time.difference(pts[i].time) >= stayMinDuration) {
        ranges.add([i, last]);
        i = last + 1;
      } else {
        i++;
      }
    }
    // 長時間沒回報但位置沒變：裝置只在移動時回報，所以是停留。
    for (int k = 0; k + 1 < n; k++) {
      final dt = pts[k + 1].time.difference(pts[k].time);
      if (dt > gapMinDuration &&
          _d(pts[k].position, pts[k + 1].position) <= gapMinDistanceM) {
        ranges.add([k, k + 1]);
      }
    }
    ranges.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r[0] <= merged.last[1]) {
        if (r[1] > merged.last[1]) merged.last[1] = r[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }

    final stays = <StayPoint>[];
    final stayAt = <int, int>{}; // 點索引 -> 停留序號
    for (int s = 0; s < merged.length; s++) {
      final r = merged[s];
      double lat = 0, lng = 0;
      for (int k = r[0]; k <= r[1]; k++) {
        lat += pts[k].position.latitude;
        lng += pts[k].position.longitude;
        stayAt[k] = s;
      }
      final cnt = r[1] - r[0] + 1;
      stays.add(StayPoint(
        center: LatLng(lat / cnt, lng / cnt),
        start: pts[r[0]].time,
        end: pts[r[1]].time,
      ));
    }

    // 5. 建立路線：停留區間只留一個停留中心；精確度差的點不進線
    final route = <_RoutePoint>[];
    final emittedStay = <int>{};
    for (int k = 0; k < n; k++) {
      final s = stayAt[k];
      if (s != null) {
        if (emittedStay.add(s)) {
          final st = stays[s];
          route.add(_RoutePoint(st.center, st.start, st.end, stay: st));
        }
        continue;
      }
      final acc = pts[k].accuracyM;
      if (acc != null && acc > lineAccuracyMaxM) continue;
      route.add(_RoutePoint(pts[k].position, pts[k].time, pts[k].time));
    }

    // 6. 斷訊分段，同時產生時間軸事件
    final rawSegments = <List<_RoutePoint>>[];
    final gaps = <TrailGap>[];
    final events = <TrailEvent>[
      TrailEvent(
        type: TrailEventType.depart,
        start: pts.first.time,
        end: pts.first.time,
        points: [pts.first.position],
      ),
    ];
    double total = 0;
    // 正在累積的 move：第一個點是錨點（前一個停留中心或同段前一點）。
    var moveAcc = <LatLng>[];
    var moveStart = pts.first.time;
    var moveEnd = pts.first.time;
    void flushMove() {
      if (moveAcc.length >= 2) {
        double d = 0;
        for (int k = 1; k < moveAcc.length; k++) {
          d += _d(moveAcc[k - 1], moveAcc[k]);
        }
        if (d > 0) {
          total += d;
          events.add(TrailEvent(
            type: TrailEventType.move,
            start: moveStart,
            end: moveEnd,
            points: moveAcc,
            distanceMeters: d,
          ));
        }
      }
      moveAcc = <LatLng>[];
    }

    for (final rp in route) {
      bool isGap = false;
      if (rawSegments.isEmpty) {
        rawSegments.add([rp]);
      } else {
        final prev = rawSegments.last.last;
        final dt = rp.time.difference(prev.endTime);
        if (dt > gapMinDuration && _d(prev.pos, rp.pos) > gapMinDistanceM) {
          isGap = true;
          gaps.add(TrailGap(
            from: prev.pos,
            to: rp.pos,
            fromTime: prev.endTime,
            toTime: rp.time,
          ));
          rawSegments.add([rp]);
        } else {
          rawSegments.last.add(rp);
        }
      }

      if (isGap) {
        final g = gaps.last;
        flushMove();
        events.add(TrailEvent(
          type: TrailEventType.gap,
          start: g.fromTime,
          end: g.toTime,
          points: [g.from, g.to],
        ));
      } else if (moveAcc.isNotEmpty) {
        moveAcc.add(rp.pos);
        moveEnd = rp.time;
      }

      final st = rp.stay;
      if (st != null) {
        // 走到停留中心為止算一段 move，接著是 stay，並以停留中心當下一段的錨點。
        flushMove();
        events.add(TrailEvent(
          type: TrailEventType.stay,
          start: st.start,
          end: st.end,
          points: [st.center],
          stay: st,
        ));
        moveAcc = [st.center];
        moveStart = st.end;
        moveEnd = st.end;
      } else if (moveAcc.isEmpty) {
        // 新分段（或第一個點）的起點。
        moveAcc = [rp.pos];
        moveStart = rp.time;
        moveEnd = rp.time;
      }
    }
    flushMove();

    // 停留聚合：依時間順序貪婪歸群，群集中心為成員中心平均。
    final clusterStays = <List<StayPoint>>[];
    final clusterCenters = <LatLng>[];
    for (final st in stays) {
      int found = -1;
      for (int c = 0; c < clusterCenters.length; c++) {
        if (_d(clusterCenters[c], st.center) <= stayClusterRadiusM) {
          found = c;
          break;
        }
      }
      if (found < 0) {
        clusterStays.add([st]);
        clusterCenters.add(st.center);
      } else {
        clusterStays[found].add(st);
        double lat = 0, lng = 0;
        for (final m in clusterStays[found]) {
          lat += m.center.latitude;
          lng += m.center.longitude;
        }
        final cnt = clusterStays[found].length;
        clusterCenters[found] = LatLng(lat / cnt, lng / cnt);
      }
    }
    final stayClusters = [
      for (int c = 0; c < clusterStays.length; c++)
        StayCluster(center: clusterCenters[c], stays: clusterStays[c]),
    ];

    // 7–8. 簡化（距離已於上方由各段 move 累加，簡化前、不含缺口）
    final segments = <TrailSegment>[];
    for (final seg in rawSegments) {
      final latlngs = seg.map((e) => e.pos).toList();
      segments.add(TrailSegment(
        points: _simplify(latlngs),
        start: seg.first.time,
        end: seg.last.endTime,
      ));
    }

    return ProcessedTrail(
      segments: segments,
      gaps: gaps,
      stays: stays,
      events: events,
      stayClusters: stayClusters,
      start: pts.first,
      totalDistanceMeters: total,
      firstTime: pts.first.time,
      lastTime: pts.last.time,
    );
  }

  /// Douglas-Peucker；以區域等距圓柱投影換算成公尺。
  static List<LatLng> _simplify(List<LatLng> pts) {
    if (pts.length <= 2) return List.of(pts);
    final lat0 = pts.first.latitude;
    final lng0 = pts.first.longitude;
    final cosLat = math.cos(lat0 * math.pi / 180);
    const mPerDeg = 111320.0;
    final xs = [for (final p in pts) (p.longitude - lng0) * cosLat * mPerDeg];
    final ys = [for (final p in pts) (p.latitude - lat0) * mPerDeg];

    final keep = List<bool>.filled(pts.length, false);
    keep[0] = true;
    keep[pts.length - 1] = true;
    final stack = <List<int>>[
      [0, pts.length - 1]
    ];
    while (stack.isNotEmpty) {
      final range = stack.removeLast();
      final s = range[0], e = range[1];
      if (e <= s + 1) continue;
      double maxD = -1;
      int idx = -1;
      final dx = xs[e] - xs[s];
      final dy = ys[e] - ys[s];
      final len2 = dx * dx + dy * dy;
      for (int k = s + 1; k < e; k++) {
        double d;
        if (len2 == 0) {
          d = math.sqrt(math.pow(xs[k] - xs[s], 2) + math.pow(ys[k] - ys[s], 2));
        } else {
          final t = (((xs[k] - xs[s]) * dx + (ys[k] - ys[s]) * dy) / len2).clamp(0.0, 1.0);
          final px = xs[s] + t * dx;
          final py = ys[s] + t * dy;
          d = math.sqrt(math.pow(xs[k] - px, 2) + math.pow(ys[k] - py, 2));
        }
        if (d > maxD) {
          maxD = d;
          idx = k;
        }
      }
      if (maxD > simplifyToleranceM) {
        keep[idx] = true;
        stack.add([s, idx]);
        stack.add([idx, e]);
      }
    }
    return [
      for (int k = 0; k < pts.length; k++)
        if (keep[k]) pts[k]
    ];
  }
}

/// 路線上的一個點；停留中心的 [time]～[endTime] 是整段停留時間。
class _RoutePoint {
  final LatLng pos;
  final DateTime time;
  final DateTime endTime;

  /// 非 null 代表這個點是停留中心。
  final StayPoint? stay;

  const _RoutePoint(this.pos, this.time, this.endTime, {this.stay});
}
