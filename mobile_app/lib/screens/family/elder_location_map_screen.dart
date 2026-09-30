// lib/screens/family/elder_location_map_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api/location_api.dart';
import '../../services/location_trail_processor.dart';

/// 家屬端：長輩戶外 GPS 定位 + 指定日期完整移動軌跡。
///
/// 與 IPS「長輩所在位置」卡片（室內、攝影機式房間定位）是完全不同的子系統，
/// 不要混用。本畫面只依賴 `elderId`/`userId`，不吃 `FamilyMainScreen` 的
/// 任何共享狀態，因此刻意自行管理資料載入與輪詢，不透過父層注入。
class ElderLocationMapScreen extends StatefulWidget {
  final String elderId;
  final int userId;
  final String elderName;

  const ElderLocationMapScreen({
    super.key,
    required this.elderId,
    required this.userId,
    this.elderName = '長輩',
  });

  @override
  State<ElderLocationMapScreen> createState() => _ElderLocationMapScreenState();
}

enum _LoadState { loading, ready, sharingDisabled, unavailable }

class _ElderLocationMapScreenState extends State<ElderLocationMapScreen> {
  static const Duration _pollInterval = Duration(seconds: 45);

  DateTime _selectedDate = DateTime.now();
  _LoadState _state = _LoadState.loading;
  Map<String, dynamic>? _currentPoint;
  DateTime? _currentRecordedAt;
  int? _staleAfterMs;
  // 已清理／分段／簡化的當日軌跡（原始點由 LocationTrailProcessor 處理）
  ProcessedTrail _trail = const ProcessedTrail();
  // 除錯用：未經處理的原始點（依時間排序），僅供 debug 版疊圖比對
  List<TrailPoint> _rawPoints = const [];
  bool _showRaw = false;
  Timer? _pollTimer;
  final MapController _mapController = MapController();

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _isStale {
    final recordedAt = _currentRecordedAt;
    final staleAfterMs = _staleAfterMs;
    if (recordedAt == null || staleAfterMs == null) return false;
    return DateTime.now().difference(recordedAt).inMilliseconds > staleAfterMs;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePolling() {
    _pollTimer?.cancel();
    if (_isToday) {
      _pollTimer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _state = _LoadState.loading);

    final currentResult = await LocationApi.getCurrentLocation(
      elderId: widget.elderId,
      userId: widget.userId,
    );
    final trailResult = await LocationApi.getTrail(
      elderId: widget.elderId,
      userId: widget.userId,
      date: _selectedDate,
    );

    if (!mounted) return;

    if (currentResult == null || trailResult == null) {
      setState(() => _state = _LoadState.unavailable);
      return;
    }

    final bool sharingEnabled = currentResult['sharing_enabled'] == true;
    if (!sharingEnabled) {
      setState(() {
        _state = _LoadState.sharingDisabled;
        _currentPoint = null;
        _trail = const ProcessedTrail();
        _rawPoints = const [];
      });
      return;
    }

    final point = currentResult['point'] as Map<String, dynamic>?;
    final pointsRaw = (trailResult['points'] as List?) ?? const [];
    final raw = pointsRaw
        .whereType<Map>()
        .map(TrailPoint.fromJson)
        .whereType<TrailPoint>()
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final trail = LocationTrailProcessor.process(raw);
    if (kDebugMode && !silent) _debugPrintRawJumps(raw);

    setState(() {
      _state = _LoadState.ready;
      _currentPoint = point;
      _currentRecordedAt =
          point != null ? LocationApi.parseRecordedAt(point['recorded_at']) : null;
      _staleAfterMs = currentResult['stale_after_ms'] as int?;
      _trail = trail;
      _rawPoints = raw;
    });

    // 靜默輪詢（45 秒）絕不動鏡頭——家屬可能正在拖曳地圖；
    // 只有日期切換／下拉重新整理才把鏡頭框回整段軌跡。
    if (!silent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitWholeTrail());
    }

    _schedulePolling();
  }

  /// 除錯：印出原始點中距離最大的前 5 個相鄰跳躍（瀏覽器 console 可見）。
  void _debugPrintRawJumps(List<TrailPoint> raw) {
    final jumps = _rawJumps(raw)..sort((a, b) => b.meters.compareTo(a.meters));
    debugPrint('[TrailRaw] 原始 ${raw.length} 點，最大相鄰跳躍前 5：');
    for (final j in jumps.take(5)) {
      debugPrint(
        '[TrailRaw] ${_hhmm(j.from.time)} → ${_hhmm(j.to.time)} '
        '${j.seconds} 秒 / ${j.meters.round()} 公尺 '
        '誤差 ${j.from.accuracyM ?? '-'} → ${j.to.accuracyM ?? '-'}',
      );
    }
  }

  List<_RawJump> _rawJumps(List<TrailPoint> raw) {
    const dist = Distance();
    return [
      for (int i = 1; i < raw.length; i++)
        _RawJump(
          raw[i - 1],
          raw[i],
          dist(raw[i - 1].position, raw[i].position),
          raw[i].time.difference(raw[i - 1].time).inSeconds,
        ),
    ];
  }

  /// 除錯：原始點疊圖是否生效（只在 debug 版）。
  bool get _rawOn => kDebugMode && _showRaw && _rawPoints.isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    _pollTimer?.cancel();
    setState(() => _selectedDate = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.elderName} 的移動軌跡',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(dateLabel, style: GoogleFonts.notoSansTc()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return ListView(
          children: const [
            SizedBox(height: 200),
            Center(child: CircularProgressIndicator()),
          ],
        );
      case _LoadState.unavailable:
        return _buildMessage(
          icon: Icons.link_off_rounded,
          title: '無法讀取位置資料',
          message: '請確認已完成與長輩的配對，或稍後再試一次',
        );
      case _LoadState.sharingDisabled:
        return _buildMessage(
          icon: Icons.location_off_rounded,
          title: '長輩已關閉位置分享',
          message: '長輩可隨時在自己「我的」分頁重新開啟分享',
        );
      case _LoadState.ready:
        return _buildMap();
    }
  }

  LatLng? get _currentLatLng {
    final point = _currentPoint;
    if (point == null) return null;
    return LatLng(
      (point['latitude'] as num).toDouble(),
      (point['longitude'] as num).toDouble(),
    );
  }

  /// 軌跡所有點 + 目前位置，供鏡頭框選。
  List<LatLng> _boundsPoints() {
    final cur = _currentLatLng;
    return [..._trail.allPoints, if (cur != null) cur];
  }

  /// 至少要有 2 個不同的點才能框選（單點用 initialCenter + zoom 16）。
  bool _hasDistinctPoints(List<LatLng> pts) {
    if (pts.length < 2) return false;
    return pts.any(
      (p) => p.latitude != pts.first.latitude || p.longitude != pts.first.longitude,
    );
  }

  CameraFit _trailFit(List<LatLng> pts) => CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        // 底部留白給摘要列與右側按鈕
        padding: const EdgeInsets.fromLTRB(48, 48, 48, 160),
        maxZoom: 17,
      );

  void _fitWholeTrail() {
    final pts = _boundsPoints();
    if (!_hasDistinctPoints(pts)) return;
    try {
      _mapController.fitCamera(_trailFit(pts));
    } catch (_) {
      // 地圖尚未 attach——初始鏡頭已由 MapOptions.initialCameraFit 處理。
    }
  }

  void _moveToCurrent() {
    final cur = _currentLatLng;
    if (cur == null) return;
    try {
      _mapController.move(cur, 17);
    } catch (_) {
      // 地圖尚未 attach，忽略。
    }
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    if (mins < 60) return '$mins 分鐘';
    final rest = mins % 60;
    return rest == 0 ? '${mins ~/ 60} 小時' : '${mins ~/ 60} 小時 $rest 分鐘';
  }

  void _showStay(StayPoint stay) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${_hhmm(stay.start)}–${_hhmm(stay.end)} 停留 ${_formatDuration(stay.duration)}',
          style: GoogleFonts.notoSansTc(),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildMap() {
    final currentLatLng = _currentLatLng;

    if (_trail.isEmpty && currentLatLng == null) {
      return _buildMessage(
        icon: Icons.route_rounded,
        title: '尚無定位資料',
        message: _isToday ? '長輩裝置尚未回報位置，請稍候再試' : '這一天沒有移動軌跡紀錄',
      );
    }

    final boundsPts = _boundsPoints();
    final bool canFit = _hasDistinctPoints(boundsPts);
    final LatLng center = currentLatLng ?? boundsPts.last;
    final startPoint = _trail.start;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            // 有 2 個以上不同的點時框住整段軌跡
            initialCameraFit: canFit ? _trailFit(boundsPts) : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flutter_application_1',
            ),
            // 斷訊缺口畫在最底層：淡色虛線，不代表真的走過這條直線
            if (_trail.gaps.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final g in _trail.gaps)
                    Polyline(
                      points: [g.from, g.to],
                      strokeWidth: 3,
                      color: const Color(0xFF94A3B8),
                      pattern: StrokePattern.dashed(segments: const [8, 8]),
                    ),
                ],
              ),
            // 每段軌跡：白色外框 + 由淺到深漸層（淺 = 較早、深 = 較晚）
            PolylineLayer(
              polylines: [
                for (final seg in _trail.segments)
                  if (seg.points.length >= 2)
                    Polyline(
                      points: seg.points,
                      strokeWidth: 5,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                      gradientColors: const [Color(0xFF93C5FD), Color(0xFF1D4ED8)],
                    ),
              ],
            ),
            // 除錯：原始點疊圖（在處理後軌跡之上、標記之下）
            if (_rawOn) ...[
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [for (final p in _rawPoints) p.position],
                    strokeWidth: 1.5,
                    color: const Color(0x99616161),
                  ),
                ],
              ),
              CircleLayer(
                circles: [
                  for (final p in _rawPoints)
                    CircleMarker(
                      point: p.position,
                      radius: 3,
                      color: (p.accuracyM == null ||
                              p.accuracyM! <= LocationTrailProcessor.lineAccuracyMaxM)
                          ? const Color(0xFF616161)
                          : const Color(0xFFF97316),
                    ),
                ],
              ),
            ],
            MarkerLayer(
              markers: [
                if (startPoint != null)
                  Marker(
                    point: startPoint.position,
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                for (final stay in _trail.stays)
                  Marker(
                    point: stay.center,
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _showStay(stay),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.access_time_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // 目前位置最後畫，永遠在最上層
            if (currentLatLng != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLatLng,
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.location_on,
                      color: _isStale ? Colors.grey : const Color(0xFFEF4444),
                      size: 44,
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 110,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kDebugMode) ...[
                FloatingActionButton.small(
                  heroTag: 'elder_map_debug_raw',
                  tooltip: '顯示原始點（除錯）',
                  backgroundColor: _showRaw ? Colors.orange : null,
                  onPressed: () => setState(() => _showRaw = !_showRaw),
                  child: const Icon(Icons.scatter_plot_rounded),
                ),
                if (currentLatLng != null || canFit) const SizedBox(height: 8),
              ],
              if (currentLatLng != null)
                FloatingActionButton.small(
                  heroTag: 'elder_map_my_location',
                  tooltip: '回到目前位置',
                  onPressed: _moveToCurrent,
                  child: const Icon(Icons.my_location_rounded),
                ),
              if (currentLatLng != null && canFit) const SizedBox(height: 8),
              if (canFit)
                FloatingActionButton.small(
                  heroTag: 'elder_map_fit_trail',
                  tooltip: '顯示整段軌跡',
                  onPressed: _fitWholeTrail,
                  child: const Icon(Icons.zoom_out_map_rounded),
                ),
            ],
          ),
        ),
        // 兩行都不會顯示時不畫空白外框（例如查看過去日期且當日無軌跡）
        if ((_isToday && currentLatLng != null) || !_trail.isEmpty || _rawOn)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildStatusBanner(),
          ),
      ],
    );
  }

  String _summaryText() {
    final parts = <String>[];
    final m = _trail.totalDistanceMeters;
    parts.add(m < 1000 ? '移動 ${m.round()} 公尺' : '移動 ${(m / 1000).toStringAsFixed(1)} 公里');
    parts.add('停留 ${_trail.stays.length} 處');
    final first = _trail.firstTime;
    final last = _trail.lastTime;
    if (first != null && last != null) {
      parts.add('${_hhmm(first)}–${_hhmm(last)}');
    }
    var text = parts.join(' ・ ');
    if (_trail.gaps.isNotEmpty) text += ' ・ 虛線為訊號中斷';
    return text;
  }

  /// 除錯：原始點統計（總數、誤差過大點數、最大間隔）。
  String _rawDebugText() {
    final over = _rawPoints
        .where((p) =>
            p.accuracyM != null && p.accuracyM! > LocationTrailProcessor.lineAccuracyMaxM)
        .length;
    var text = '原始 ${_rawPoints.length} 點 ・ 誤差>35m $over 點';
    final jumps = _rawJumps(_rawPoints);
    if (jumps.isNotEmpty) {
      final max = jumps.reduce((a, b) => a.meters >= b.meters ? a : b);
      text += ' ・ 最大間隔 ${max.seconds} 秒 / ${max.meters.round()} 公尺 @ ${_hhmm(max.from.time)}';
    }
    return text;
  }

  Widget _buildStatusBanner() {
    final recordedAt = _currentRecordedAt;
    // 「最後更新」只在查看今天且有目前位置時顯示
    final bool showLastUpdate = _isToday && _currentPoint != null;
    String text = '尚無最新位置';
    if (recordedAt != null) {
      final diff = DateTime.now().difference(recordedAt);
      if (diff.inMinutes < 1) {
        text = '最後更新：剛剛';
      } else if (diff.inMinutes < 60) {
        text = '最後更新：${diff.inMinutes} 分鐘前';
      } else if (diff.inHours < 24) {
        text = '最後更新：${diff.inHours} 小時前';
      } else {
        text = '最後更新：${diff.inDays} 天前';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLastUpdate)
            Row(
              children: [
                Icon(
                  _isStale ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                  color: _isStale ? Colors.orange : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isStale ? '$text（已過期，可能不是即時位置）' : text,
                    style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (showLastUpdate && !_trail.isEmpty) const SizedBox(height: 4),
          if (!_trail.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _summaryText(),
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (_rawOn) ...[
            if (showLastUpdate || !_trail.isEmpty) const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _rawDebugText(),
                    style: GoogleFonts.notoSansTc(fontSize: 11, color: Colors.orange[800]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage({required IconData icon, required String title, required String message}) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 除錯用：相鄰兩個原始點之間的跳躍。
class _RawJump {
  final TrailPoint from;
  final TrailPoint to;
  final double meters;
  final int seconds;

  const _RawJump(this.from, this.to, this.meters, this.seconds);
}
