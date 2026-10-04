// lib/screens/family/elder_location_map_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/map_tiles.dart';
import '../../models/elder_place.dart';
import '../../services/api/location_api.dart';
import '../../services/location_device_status.dart';
import '../../services/location_trail_processor.dart';
import 'elder_places_screen.dart';

/// 家屬端：長輩戶外 GPS 定位 + 指定日期完整移動軌跡。
///
/// 與 IPS「長輩所在位置」卡片（室內、攝影機式房間定位）是完全不同的子系統，
/// 不要混用。本畫面只依賴 `elderId`/`userId`，不吃 `FamilyMainScreen` 的
/// 任何共享狀態，因此刻意自行管理資料載入與輪詢，不透過父層注入。
class ElderLocationMapScreen extends StatefulWidget {
  final String elderId;
  final int userId;
  final String elderName;

  /// 開啟時要顯示哪一天的軌跡（只取年月日）；省略則為今天。
  /// 「外出趨勢」點某一天的長條時使用。
  final DateTime? initialDate;

  const ElderLocationMapScreen({
    super.key,
    required this.elderId,
    required this.userId,
    this.elderName = '長輩',
    this.initialDate,
  });

  @override
  State<ElderLocationMapScreen> createState() => _ElderLocationMapScreenState();
}

enum _LoadState { loading, ready, sharingDisabled, unavailable }

class _ElderLocationMapScreenState extends State<ElderLocationMapScreen> {
  static const Duration _pollInterval = Duration(seconds: 45);

  late DateTime _selectedDate;
  _LoadState _state = _LoadState.loading;
  Map<String, dynamic>? _currentPoint;
  DateTime? _currentRecordedAt;
  int? _staleAfterMs;
  // 長輩手機的定位權限／服務狀態（`/current` 的 device_status／device_status_at，
  // 值見 LocationDeviceStatus）；分享關閉或後端未提供時為 null。
  String? _deviceStatus;
  DateTime? _deviceStatusAt;
  // 已清理／分段／簡化的當日軌跡（原始點由 LocationTrailProcessor 處理）
  ProcessedTrail _trail = const ProcessedTrail();
  // 除錯用：未經處理的原始點（依時間排序），僅供 debug 版疊圖比對
  List<TrailPoint> _rawPoints = const [];
  bool _showRaw = false;
  // 長輩的常去地點（家、公園…）；不受位置分享開關限制，載入失敗時保留舊值。
  List<ElderPlace> _places = const [];
  // 增量查詢游標（後端回傳的 `cursor`＝目前已取得的最大資料列 id）；
  // null 代表尚未取得，下一次載入（含靜默輪詢）一律做完整查詢。
  int? _cursor;
  // 每次 _load 遞增；await 回來後若序號已被更新的載入取代就丟棄結果，
  // 避免切換日期時舊請求的資料覆蓋新日期。
  int _loadSeq = 0;
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
    final initial = widget.initialDate;
    _selectedDate = initial != null
        ? DateTime(initial.year, initial.month, initial.day)
        : DateTime.now();
    MapTiles.warnIfFallback();
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
    final seq = ++_loadSeq;
    if (!silent && mounted) setState(() => _state = _LoadState.loading);

    // 靜默輪詢且已有游標 → 只撈新點（id > cursor）再併入既有原始點；
    // 非靜默（首次／換日期／下拉重新整理）或尚無游標 → 完整查詢。
    final int? sinceId = silent ? _cursor : null;
    final bool incremental = sinceId != null;

    // 常去地點與定位同時載入（僅非靜默：輪詢不需要重抓，編輯後另行重載）。
    final placesFuture = silent
        ? null
        : LocationApi.getPlaces(elderId: widget.elderId, userId: widget.userId);

    final currentResult = await LocationApi.getCurrentLocation(
      elderId: widget.elderId,
      userId: widget.userId,
    );
    final trailResult = await LocationApi.getTrail(
      elderId: widget.elderId,
      userId: widget.userId,
      date: _selectedDate,
      sinceId: sinceId,
    );

    final loadedPlaces = await placesFuture;

    if (!mounted || seq != _loadSeq) return;
    // 地點與分享開關無關，早於下方各分支先更新（失敗回傳 null 則保留舊值）。
    if (loadedPlaces != null) _places = loadedPlaces;

    if (currentResult == null || trailResult == null) {
      if (silent) {
        // 靜默輪詢暫時失敗不清掉畫面，下次輪詢再試
        _schedulePolling();
        return;
      }
      setState(() => _state = _LoadState.unavailable);
      return;
    }

    final bool sharingEnabled = currentResult['sharing_enabled'] == true;
    if (!sharingEnabled) {
      setState(() {
        _state = _LoadState.sharingDisabled;
        _currentPoint = null;
        _deviceStatus = null;
        _deviceStatusAt = null;
        _trail = const ProcessedTrail();
        _rawPoints = const [];
        _cursor = null;
      });
      return;
    }

    final point = currentResult['point'] as Map<String, dynamic>?;
    final pointsRaw = (trailResult['points'] as List?) ?? const [];
    final parsed = pointsRaw
        .whereType<Map>()
        .map(TrailPoint.fromJson)
        .whereType<TrailPoint>()
        .toList();
    // 增量：新點附加到既有原始點後再依時間排序（id 游標保證不會重複，不需去重）。
    final List<TrailPoint> raw = incremental ? [..._rawPoints, ...parsed] : parsed;
    raw.sort((a, b) => a.time.compareTo(b.time));
    // 增量查詢沒有新點時軌跡不變，省下重算。
    final trail = (incremental && parsed.isEmpty)
        ? _trail
        : LocationTrailProcessor.process(raw);
    if (kDebugMode && !silent) _debugPrintRawJumps(raw);

    final newCursor = (trailResult['cursor'] as num?)?.toInt();

    setState(() {
      _state = _LoadState.ready;
      _currentPoint = point;
      _currentRecordedAt =
          point != null ? LocationApi.parseRecordedAt(point['recorded_at']) : null;
      _staleAfterMs = currentResult['stale_after_ms'] as int?;
      final rawStatus = currentResult['device_status'];
      _deviceStatus = rawStatus is String ? rawStatus : null;
      _deviceStatusAt = LocationApi.parseRecordedAt(currentResult['device_status_at']);
      _trail = trail;
      _rawPoints = raw;
      _cursor = newCursor ?? (incremental ? _cursor : null);
    });

    // 靜默輪詢（45 秒）絕不動鏡頭——家屬可能正在拖曳地圖；
    // 只有日期切換／下拉重新整理才把鏡頭框回整段軌跡。
    if (!silent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitWholeTrail());
    }

    _schedulePolling();
  }

  /// 編輯地點後重新載入（失敗時保留舊清單）。
  Future<void> _reloadPlaces() async {
    final places = await LocationApi.getPlaces(
      elderId: widget.elderId,
      userId: widget.userId,
    );
    if (!mounted || places == null) return;
    setState(() => _places = places);
  }

  /// 該座標所在的常去地點名稱；不在任何地點範圍內回傳 null。
  String? _placeNameAt(LatLng p) => matchPlace(p, _places)?.name;

  /// 新增地點（長按地圖或由停留點建立）；成功後重載地點。
  Future<void> _createPlaceAt(LatLng position, {bool presetHome = false}) async {
    final saved = await showPlaceEditorDialog(
      context,
      elderId: widget.elderId,
      userId: widget.userId,
      position: position,
      presetHome: presetHome,
    );
    if (saved) await _reloadPlaces();
  }

  Future<void> _editPlace(ElderPlace place) async {
    final saved = await showPlaceEditorDialog(
      context,
      elderId: widget.elderId,
      userId: widget.userId,
      existing: place,
    );
    if (saved) await _reloadPlaces();
  }

  Future<void> _openPlaces() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ElderPlacesScreen(
          elderId: widget.elderId,
          userId: widget.userId,
          elderName: widget.elderName,
        ),
      ),
    );
    if (changed == true) await _reloadPlaces();
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

  /// 可查詢的最早日期（與日期選擇器的 90 天上限一致，只看年月日）。
  DateTime get _earliestDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - 90);
  }

  bool get _atEarliestDate {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return !d.isAfter(_earliestDate);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _earliestDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    _changeDate(picked);
  }

  /// 切換日期：停掉輪詢、重設增量游標，並以完整查詢重新載入。
  void _changeDate(DateTime d) {
    _pollTimer?.cancel();
    setState(() {
      _selectedDate = d;
      _cursor = null;
    });
    _load();
  }

  void _shiftDate(int days) {
    _changeDate(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + days));
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${_selectedDate.month}/${_selectedDate.day}';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.elderName} 的移動軌跡',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 窄螢幕（360dp）空間有限：標題靠左貼齊、按鈕一律 compact，標題由 Text 自行省略。
        titleSpacing: 0,
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '常去地點',
            onPressed: _openPlaces,
            icon: const Icon(Icons.bookmark_border_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '前一天',
            onPressed: _atEarliestDate ? null : () => _shiftDate(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(dateLabel, style: GoogleFonts.notoSansTc()),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '後一天',
            onPressed: _isToday ? null : () => _shiftDate(1),
            icon: const Icon(Icons.chevron_right_rounded),
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

  // 底部留白給摘要列與右側按鈕
  static const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(48, 48, 48, 160);

  CameraFit _trailFit(List<LatLng> pts) => CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: _fitPadding,
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

  /// 短格式（標記膠囊用）：`35 分`、`1 時 20 分`、`<1 分`。
  String _formatDurationShort(Duration d) {
    final mins = d.inMinutes;
    if (mins < 1) return '<1 分';
    if (mins < 60) return '$mins 分';
    final rest = mins % 60;
    return rest == 0 ? '${mins ~/ 60} 時' : '${mins ~/ 60} 時 $rest 分';
  }

  String _formatDistance(double m) =>
      m < 1000 ? '${m.round()} 公尺' : '${(m / 1000).toStringAsFixed(1)} 公里';

  /// 目前仍在進行中的停留：查看今天、有目前位置、最後一個事件是停留，
  /// 且目前位置仍在該停留半徑內。否則回傳 null。
  StayPoint? get _ongoingStay {
    if (!_isToday) return null;
    final cur = _currentLatLng;
    if (cur == null) return null;
    final events = _trail.events;
    if (events.isEmpty) return null;
    final last = events.last;
    final stay = last.stay;
    if (last.type != TrailEventType.stay || stay == null) return null;
    final d = const Distance()(cur, stay.center);
    return d <= LocationTrailProcessor.stayRadiusM ? stay : null;
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // 無法開啟外部瀏覽器時忽略，版權文字仍然可讀。
    }
  }

  /// 停留群集標記：琥珀色膠囊（時鐘 + 總停留時間 + 多次停留的 ×N）。
  Marker _buildClusterMarker(StayCluster cluster) {
    final durationLabel = _formatDurationShort(cluster.totalDuration) +
        (cluster.count > 1 ? ' ×${cluster.count}' : '');
    // 已命名的地點：膠囊前面加上名稱（最多 4 字），例如「公園 35 分」。
    final placeName = _placeNameAt(cluster.center);
    final prefix = placeName == null ? '' : _truncateName(placeName, 4);
    final label = prefix.isEmpty ? durationLabel : '$prefix $durationLabel';
    // 依字數估算寬度，避免文字被截斷（時間部分每字以 8 估算；名稱是中文字較寬，
    // 每字以 13 估算；再加圖示與內距）。
    final nameWidth = prefix.isEmpty ? 0 : 13 * prefix.runes.length + 4;
    final width =
        (30 + 8 * durationLabel.length + nameWidth).clamp(56, 180).toDouble();
    return Marker(
      point: cluster.center,
      width: width,
      height: 28,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _showClusterSheet(cluster),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取前 [max] 個字（以 Unicode 字元計，不會切壞 emoji）。
  String _truncateName(String name, int max) {
    final runes = name.runes.toList();
    return runes.length <= max ? name : String.fromCharCodes(runes.take(max));
  }

  /// 停留點底部面板：停留資訊 + 命名／設為家／編輯地點。
  ///
  /// 單次停留與多次停留共用（取代原本單次停留的 SnackBar）；每一次停留都列出時段。
  void _showClusterSheet(StayCluster cluster) {
    final place = matchPlace(cluster.center, _places);
    final String title;
    if (cluster.count == 1) {
      title = place != null ? '在${place.name}' : '停留地點';
    } else {
      final where = place != null ? '在${place.name}' : '此處';
      title = '$where停留 ${cluster.count} 次，共 ${_formatDuration(cluster.totalDuration)}';
    }
    final Color iconColor = place == null
        ? const Color(0xFFF59E0B)
        : (place.isHome ? const Color(0xFF22C55E) : const Color(0xFF6366F1));
    final IconData icon = place == null
        ? Icons.access_time_rounded
        : (place.isHome ? Icons.home_rounded : Icons.place_rounded);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in cluster.stays)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_hhmm(s.start)}–${_hhmm(s.end)}  停留 ${_formatDuration(s.duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansTc(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (place != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editPlace(place);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(
                      '編輯「${place.name}」',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _createPlaceAt(cluster.center);
                    },
                    icon: const Icon(Icons.place_rounded, size: 18),
                    label: Text(
                      '命名這個地點',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _createPlaceAt(cluster.center, presetHome: true);
                    },
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: Text(
                      '設為家',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 常去地點名稱標籤：白底圓角膠囊（圖示 + 名稱），錨在地點圓心正上方。
  Marker _buildPlaceLabelMarker(ElderPlace place) {
    final color = place.isHome ? const Color(0xFF22C55E) : const Color(0xFF6366F1);
    // 依字數估算寬度（中文字每字以 12 估算，加上圖示與內距），限制在 60～160。
    final width = (30 + 12 * place.name.runes.length).clamp(60, 160).toDouble();
    return Marker(
      point: place.position,
      width: width,
      height: 24,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _editPlace(place),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                place.isHome ? Icons.home_rounded : Icons.place_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final currentLatLng = _currentLatLng;

    final String? deviceWarning = _deviceWarningText();

    if (_trail.isEmpty && currentLatLng == null) {
      // 長輩手機沒開定位時，「尚未回報位置，請稍候再試」會誤導家屬一直等；
      // 改直接說明真正原因與該怎麼做。
      final bool warnNow = deviceWarning != null && _isToday;
      return _buildMessage(
        icon: warnNow ? Icons.location_disabled_rounded : Icons.route_rounded,
        title: '尚無定位資料',
        message: warnNow
            ? deviceWarning
            : (_isToday ? '長輩裝置尚未回報位置，請稍候再試' : '這一天沒有移動軌跡紀錄'),
      );
    }

    final boundsPts = _boundsPoints();
    final bool canFit = _hasDistinctPoints(boundsPts);
    final LatLng center = currentLatLng ?? boundsPts.last;
    final startPoint = _trail.start;
    final ongoing = _ongoingStay;
    final bool showBanner =
        (_isToday && currentLatLng != null) || !_trail.isEmpty || _rawOn;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            // 有 2 個以上不同的點時框住整段軌跡
            initialCameraFit: canFit ? _trailFit(boundsPts) : null,
            // 長按地圖任一點：在該處新增常去地點
            onLongPress: (tapPos, latLng) => _createPlaceAt(latLng),
          ),
          children: [
            TileLayer(
              urlTemplate: MapTiles.urlTemplate,
              userAgentPackageName: MapTiles.userAgentPackageName,
            ),
            // 常去地點範圍（以公尺為單位的圓）：畫在軌跡之下；家用綠色、其他用靛色
            if (_places.isNotEmpty)
              CircleLayer(
                circles: [
                  for (final p in _places)
                    CircleMarker(
                      point: p.position,
                      radius: p.radiusM.toDouble(),
                      useRadiusInMeter: true,
                      color: p.isHome ? const Color(0x2622C55E) : const Color(0x1A6366F1),
                      borderColor:
                          p.isHome ? const Color(0xFF22C55E) : const Color(0xFF6366F1),
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
            // 斷訊缺口畫在軌跡底層：淡色虛線，不代表真的走過這條直線
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
            // 地點名稱標籤：在軌跡之上、停留膠囊之下
            if (_places.isNotEmpty)
              MarkerLayer(
                markers: [for (final p in _places) _buildPlaceLabelMarker(p)],
              ),
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
                for (final cluster in _trail.stayClusters)
                  // 長輩目前正待在這個單次停留上：紅色定位針就在那裡，不重複畫膠囊。
                  if (!(ongoing != null &&
                      cluster.count == 1 &&
                      identical(cluster.stays.first, ongoing)))
                    _buildClusterMarker(cluster),
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
            // 版權標示放左下角（右下是按鈕列），並避開底部資訊列。
            Padding(
              padding: EdgeInsets.only(bottom: showBanner ? 100 : 0),
              child: RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                popupBackgroundColor: Colors.white,
                attributions: [
                  for (final a in MapTiles.attributions)
                    TextSourceAttribution(
                      a.label,
                      prependCopyright: false,
                      onTap: () => _openUrl(a.url),
                    ),
                ],
              ),
            ),
          ],
        ),
        // 長輩手機定位沒開：醒目警示卡放在最上方，家屬一進來就看到原因。
        if (deviceWarning != null)
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: _buildDeviceWarningCard(deviceWarning),
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
        if (showBanner)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildStatusBanner(),
          ),
      ],
    );
  }

  /// 長輩手機定位有問題時的完整警示文字（含「N 分鐘前回報」）；沒問題回傳 null。
  String? _deviceWarningText() {
    final base = LocationDeviceStatus.familyMessage(_deviceStatus);
    if (base == null) return null;
    final ago = LocationDeviceStatus.reportedAgoText(_deviceStatusAt);
    return ago.isEmpty ? base : '$base$ago';
  }

  /// 警示卡：圖示 + 可收縮的多行文字（內容為動態字串，鐵律 #14）。
  Widget _buildDeviceWarningCard(String text) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: Material(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFB45309), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C2D12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summaryText() {
    final parts = <String>[];
    parts.add('移動 ${_formatDistance(_trail.totalDistanceMeters)}');
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
    final ongoing = _ongoingStay;
    if (ongoing != null) {
      // 長輩目前仍待在最後一次停留的範圍內：改顯示已停留多久。
      final placeName = _placeNameAt(ongoing.center);
      final dur = _formatDuration(DateTime.now().difference(ongoing.start));
      text = placeName != null ? '目前在$placeName・已停留 $dur' : '目前已在此停留 $dur';
    } else if (recordedAt != null) {
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
    final bool hasTimeline = _trail.events.isNotEmpty;
    // 外層只負責陰影與圓角；白底與水波紋交給 Material + InkWell，
    // 否則水波紋會被 Container 的底色蓋住。
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: hasTimeline ? _showTimelineSheet : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      // 提示可點開「今日行程」
                      if (hasTimeline)
                        Icon(Icons.expand_less_rounded, size: 22, color: Colors.grey[600]),
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
          ),
        ),
      ),
    );
  }

  // ───────────────────────── 行程時間軸 ─────────────────────────

  static const Color _depColor = Color(0xFF22C55E);
  static const Color _moveColor = Color(0xFF3B82F6);
  static const Color _stayColor = Color(0xFFF59E0B);
  static const Color _gapColor = Color(0xFF94A3B8);

  IconData _eventIcon(TrailEventType t) {
    switch (t) {
      case TrailEventType.depart:
        return Icons.flag_rounded;
      case TrailEventType.move:
        return Icons.directions_walk_rounded;
      case TrailEventType.stay:
        return Icons.access_time_rounded;
      case TrailEventType.gap:
        return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
    }
  }

  Color _eventColor(TrailEventType t) {
    switch (t) {
      case TrailEventType.depart:
        return _depColor;
      case TrailEventType.move:
        return _moveColor;
      case TrailEventType.stay:
        return _stayColor;
      case TrailEventType.gap:
        return _gapColor;
    }
  }

  String _eventTime(TrailEvent e) => e.type == TrailEventType.depart
      ? _hhmm(e.start)
      : '${_hhmm(e.start)}–${_hhmm(e.end)}';

  String _eventDescription(TrailEvent e, {required bool ongoing}) {
    switch (e.type) {
      case TrailEventType.depart:
        return '出發';
      case TrailEventType.move:
        final dist = '移動 ${_formatDistance(e.distanceMeters)}';
        // 不到 1 分鐘的移動不補時間，避免出現「（0 分鐘）」。
        return e.duration.inMinutes < 1 ? dist : '$dist（${_formatDuration(e.duration)}）';
      case TrailEventType.stay:
        final stay = e.stay;
        final placeName = stay != null ? _placeNameAt(stay.center) : null;
        final where = placeName != null ? '在$placeName・' : '';
        return ongoing
            ? '$where停留中・已 ${_formatDuration(DateTime.now().difference(e.start))}'
            : '$where停留 ${_formatDuration(e.duration)}';
      case TrailEventType.gap:
        return '訊號中斷 ${_formatDuration(e.duration)}';
    }
  }

  void _showTimelineSheet() {
    final events = _trail.events;
    if (events.isEmpty) return;
    final ongoing = _ongoingStay;
    final title = _isToday ? '今日行程' : '${_selectedDate.month}/${_selectedDate.day} 行程';
    final summary = _summaryText();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final e = events[i];
                    final isOngoing =
                        ongoing != null && i == events.length - 1 && identical(e.stay, ongoing);
                    return _buildTimelineRow(sheetContext, e, isOngoing);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineRow(BuildContext sheetContext, TrailEvent e, bool ongoing) {
    final color = _eventColor(e.type);
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        // 等底部面板收起後再動鏡頭，避免與轉場動畫同時進行。
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusEvent(e));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                _eventTime(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
            ),
            Icon(_eventIcon(e.type), size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _eventDescription(e, ongoing: ongoing),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: ongoing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 點選時間軸事件：移動／斷訊框住整段路線，出發／停留則拉近到該點。
  void _focusEvent(TrailEvent e) {
    if (e.points.isEmpty) return;
    try {
      final bool routeLike = e.type == TrailEventType.move || e.type == TrailEventType.gap;
      if (routeLike && _hasDistinctPoints(e.points)) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(e.points),
            padding: _fitPadding,
            maxZoom: 17,
          ),
        );
      } else {
        _mapController.move(e.points.first, 17);
      }
    } catch (_) {
      // 地圖尚未 attach，忽略。
    }
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
