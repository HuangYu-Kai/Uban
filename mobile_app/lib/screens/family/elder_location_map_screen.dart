// lib/screens/family/elder_location_map_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api/location_api.dart';

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
  List<LatLng> _trailPoints = [];
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
        _trailPoints = [];
      });
      return;
    }

    final point = currentResult['point'] as Map<String, dynamic>?;
    final pointsRaw = (trailResult['points'] as List?) ?? const [];
    final points = pointsRaw
        .whereType<Map>()
        .map((p) => LatLng(
              (p['latitude'] as num).toDouble(),
              (p['longitude'] as num).toDouble(),
            ))
        .toList();

    setState(() {
      _state = _LoadState.ready;
      _currentPoint = point;
      _currentRecordedAt =
          point != null ? LocationApi.parseRecordedAt(point['recorded_at']) : null;
      _staleAfterMs = currentResult['stale_after_ms'] as int?;
      _trailPoints = points;
    });

    if (point != null) {
      final target = LatLng(
        (point['latitude'] as num).toDouble(),
        (point['longitude'] as num).toDouble(),
      );
      try {
        _mapController.move(target, _mapController.camera.zoom);
      } catch (_) {
        // 地圖尚未 attach（例如首次載入時）——初始中心已由 MapOptions.initialCenter 處理。
      }
    }

    _schedulePolling();
  }

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

  Widget _buildMap() {
    final point = _currentPoint;
    final LatLng? currentLatLng = point != null
        ? LatLng((point['latitude'] as num).toDouble(), (point['longitude'] as num).toDouble())
        : null;

    if (_trailPoints.isEmpty && currentLatLng == null) {
      return _buildMessage(
        icon: Icons.route_rounded,
        title: '尚無定位資料',
        message: _isToday ? '長輩裝置尚未回報位置，請稍候再試' : '這一天沒有移動軌跡紀錄',
      );
    }

    final LatLng center = currentLatLng ?? _trailPoints.last;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flutter_application_1',
            ),
            if (_trailPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trailPoints,
                    strokeWidth: 4,
                    color: const Color(0xFF3B82F6),
                  ),
                ],
              ),
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
        if (currentLatLng != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildStatusBanner(),
          ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    final recordedAt = _currentRecordedAt;
    String text;
    if (recordedAt == null) {
      text = '尚無最新位置';
    } else {
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
      child: Row(
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
