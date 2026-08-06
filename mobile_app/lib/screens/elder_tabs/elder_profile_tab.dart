import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../identification_screen.dart';
import '../../widgets/google_assistant_overlay.dart';

class ElderProfileTab extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderProfileTab({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderProfileTab> createState() => _ElderProfileTabState();
}

class _ElderProfileTabState extends State<ElderProfileTab>
    with TickerProviderStateMixin {
  static const bool _useMockRoute = true;
  static const double _maxAccuracyMeters = 35.0;
  static const double _minPointDistanceMeters = 2.0;
  static const double _maxReasonableJumpMeters = 120.0;
  static const double _maxWalkingSpeedMps = 3.2;
  static const double _vehicleSpeedMps = 7.0;
  static const double _simplifyToleranceMeters = 4.0;
  static const Duration _minSampleInterval = Duration(seconds: 1);
  static const double _cleanCoordThresholdMeters = 1.0;
  static const bool _enableSplineSmoothing = true;

  // ── 數據 ───────────────────────────────────────────────
  final int dailyStepGoal = 8000;
  int currentSteps = 0; // Will be calculated from distance or fetched

  // ── 步數動畫 ──────────────────────────────────────────────
  late AnimationController _ctrl;

  // ── GPS 追蹤 ──────────────────────────────────────────────
  bool _isTracking = false;
  final List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();
  List<LatLng> _displayRouteCache = [];
  DateTime? _lastAcceptedTime;
  double _totalDistance = 0.0; // 公里
  LatLng? _currentPosition;
  StreamSubscription<StepCount>? _stepCountStream;
  int _hardwareBaseSteps = -1;
  int _sessionPedometerSteps = 0;
  double _estimatedStrideMeters = 0.72;
  bool _stepCounterUnavailable = false;
  _MovementState _movementState = _MovementState.stationary;
  _CoordinateKalmanFilter? _latFilter;
  _CoordinateKalmanFilter? _lngFilter;
  // 台北 101 作為預設中心點

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });

    _autoStartTracking();
    _startStepTracking();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _positionStream?.cancel();
    _stepCountStream?.cancel();
    super.dispose();
  }

  // ── 自動啟動追蹤與持久化初始化 ──────────────────────────────
  Future<void> _autoStartTracking() async {
    if (_useMockRoute) {
      _loadMockDemoRoute();
      await _persistRoute();
    } else {
      await _loadPersistedRoute();
    }
    await _startTracking();
  }

  // ── 載入持久化路徑 ──────────────────────────────────────────
  Future<void> _loadPersistedRoute() async {
    final prefs = await SharedPreferences.getInstance();

    final dateStr = prefs.getString('last_track_date') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (dateStr != today) {
      await prefs.remove('route_points');
      await prefs.setDouble('total_distance', 0.0);
      await prefs.setInt('session_pedometer_steps', 0);
      await prefs.setString('last_track_date', today);
      if (_useMockRoute) {
        _loadMockDemoRoute();
        await _persistRoute();
      }
      return;
    }

    final pointsJson = prefs.getString('route_points');
    if (pointsJson != null) {
      final List<dynamic> decoded = jsonDecode(pointsJson);
      setState(() {
        _routePoints.addAll(
          decoded.map((p) => LatLng(p['lat'], p['lng'])).toList(),
        );
        _totalDistance = prefs.getDouble('total_distance') ?? 0.0;
        _sessionPedometerSteps = prefs.getInt('session_pedometer_steps') ?? 0;
        _recomputeDisplayRoute();
      });
    }
    if (_useMockRoute && _routePoints.isEmpty) {
      _loadMockDemoRoute();
    }
  }

  // ── 儲存當前點位與里程 ──────────────────────────────────────
  Future<void> _persistRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final pointsJson = jsonEncode(
      _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    );
    await prefs.setString('route_points', pointsJson);
    await prefs.setDouble('total_distance', _totalDistance);
    await prefs.setInt('session_pedometer_steps', _sessionPedometerSteps);
  }

  List<LatLng> get _displayRoutePoints {
    if (_displayRouteCache.isEmpty && _routePoints.isNotEmpty) {
      _recomputeDisplayRoute();
    }
    return _displayRouteCache;
  }

  // ── [展示用] 載入中正紀念堂到北商的假路徑 ───────────────────
  void _loadMockDemoRoute() {
    final mockPoints = [
      // 中正紀念堂園區繞行一圈
      const LatLng(25.0346, 121.5218),
      const LatLng(25.0350, 121.5231),
      const LatLng(25.0340, 121.5238),
      const LatLng(25.0328, 121.5231),
      const LatLng(25.0329, 121.5215),
      const LatLng(25.0338, 121.5207),
      const LatLng(25.0351, 121.5210),
      const LatLng(25.0354, 121.5224),
      // 沿著可步行主幹道往北商方向
      const LatLng(25.0362, 121.5225),
      const LatLng(25.0372, 121.5226),
      const LatLng(25.0382, 121.5228),
      const LatLng(25.0391, 121.5231),
      const LatLng(25.0400, 121.5234),
      const LatLng(25.0410, 121.5239),
      const LatLng(25.0418, 121.5245),
      const LatLng(25.0423, 121.5249), // 抵達北商附近
    ];
    setState(() {
      _routePoints.clear();
      _routePoints.addAll(mockPoints);
      _currentPosition = mockPoints.last;
      _totalDistance = _calculateRouteDistanceKm(mockPoints);
      _recomputeDisplayRoute();
    });
  }

  double _calculateRouteDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0;
    double meters = 0;
    for (var i = 1; i < points.length; i++) {
      meters += _distance(points[i - 1], points[i]);
    }
    return meters / 1000.0;
  }

  // ── 請求位置權限 ────────────────────────────────────────
  Future<bool> _requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<void> _startStepTracking() async {
    try {
      final permission = await Permission.activityRecognition.request();
      if (!permission.isGranted) return;

      _stepCountStream = Pedometer.stepCountStream.listen(
        (event) {
          if (!mounted) return;
          if (_hardwareBaseSteps == -1) {
            _hardwareBaseSteps = event.steps;
            return;
          }

          final delta = event.steps - _hardwareBaseSteps;
          if (delta <= 0) return;

          _hardwareBaseSteps = event.steps;
          _sessionPedometerSteps += delta;
          _refreshStrideEstimate();
          setState(() {});
          unawaited(_persistRoute());
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _stepCounterUnavailable = true;
          });
        },
        cancelOnError: false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stepCounterUnavailable = true;
      });
    }
  }

  void _refreshStrideEstimate() {
    final meters = _totalDistance * 1000.0;
    if (meters < 100 || _sessionPedometerSteps < 150) return;
    final stride = meters / _sessionPedometerSteps;
    _estimatedStrideMeters = stride.clamp(0.55, 0.9);
  }

  int _computeFusedSteps() {
    final gpsSteps = (_totalDistance * 1000.0 / _estimatedStrideMeters).round();
    if (_stepCounterUnavailable) return gpsSteps;
    return math.max(_sessionPedometerSteps, gpsSteps);
  }

  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 6,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Uban 背景軌跡記錄中',
          notificationText: '正在持續追蹤今日步行路線',
          enableWakeLock: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 6,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: true,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 6,
    );
  }

  // ── 開始 GPS 追蹤 ───────────────────────────
  Future<void> _startTracking() async {
    if (_isTracking) return;
    final granted = await _requestPermission();
    if (!granted) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(_onPosition);

    setState(() {
      _isTracking = true;
    });
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    if (pos.accuracy <= 0 || pos.accuracy > _maxAccuracyMeters) return;
    if (_isTooFrequent(pos.timestamp)) return;

    final filteredPoint = _applyKalman(pos);

    if (_routePoints.isEmpty) {
      setState(() {
        _routePoints.add(filteredPoint);
        _currentPosition = filteredPoint;
        _movementState = _MovementState.stationary;
        _recomputeDisplayRoute();
      });
      _lastAcceptedTime = pos.timestamp;
      unawaited(_persistRoute());
      _focusCamera();
      return;
    }

    final lastPoint = _routePoints.last;
    final distanceMeters = _distance(lastPoint, filteredPoint);
    if (distanceMeters < _minPointDistanceMeters) {
      _updateMovementState(pos.speed);
      setState(() {
        _currentPosition = filteredPoint;
      });
      return;
    }
    if (distanceMeters > _maxReasonableJumpMeters) {
      _movementState = _MovementState.fastTransit;
      setState(() {});
      return;
    }

    final now = pos.timestamp;
    final previous = _lastAcceptedTime ?? now;
    final elapsedSeconds = now.difference(previous).inMilliseconds / 1000.0;
    final computedSpeed =
        elapsedSeconds <= 0 ? 0.0 : distanceMeters / elapsedSeconds;
    final speedMps = pos.speed > 0 ? pos.speed : computedSpeed;
    _updateMovementState(speedMps);

    if (_movementState == _MovementState.fastTransit ||
        speedMps > _maxWalkingSpeedMps) {
      setState(() {});
      return;
    }

    _lastAcceptedTime = now;
    _totalDistance += distanceMeters / 1000.0;
    _refreshStrideEstimate();

    setState(() {
      _routePoints.add(filteredPoint);
      _currentPosition = filteredPoint;
      _recomputeDisplayRoute();
    });
    unawaited(_persistRoute());
    _focusCamera();
  }

  bool _isTooFrequent(DateTime? timestamp) {
    if (timestamp == null || _lastAcceptedTime == null) return false;
    return timestamp.difference(_lastAcceptedTime!).abs() < _minSampleInterval;
  }

  LatLng _applyKalman(Position pos) {
    final measurementNoise = math.max(3.0, pos.accuracy);
    _latFilter ??= _CoordinateKalmanFilter(pos.latitude,
        measurementNoise: measurementNoise);
    _lngFilter ??= _CoordinateKalmanFilter(pos.longitude,
        measurementNoise: measurementNoise);

    return LatLng(
      _latFilter!.update(pos.latitude, measurementNoise: measurementNoise),
      _lngFilter!.update(pos.longitude, measurementNoise: measurementNoise),
    );
  }

  void _updateMovementState(double rawSpeed) {
    final speed = rawSpeed.isFinite ? rawSpeed : 0.0;
    if (speed >= _vehicleSpeedMps) {
      _movementState = _MovementState.fastTransit;
      return;
    }
    if (speed >= 0.5 && speed <= _maxWalkingSpeedMps) {
      _movementState = _MovementState.walking;
      return;
    }
    _movementState = _MovementState.stationary;
  }

  void _focusCamera() {
    final displayPoints = _displayRoutePoints;
    if (displayPoints.length > 1) {
      final bounds = LatLngBounds.fromPoints(displayPoints);
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(80.0),
          ),
        );
      } catch (_) {}
      return;
    }
    if (_currentPosition != null && _mapController.camera.zoom != 0) {
      _mapController.move(_currentPosition!, 18.0);
    }
  }

  List<LatLng> _simplifyRoute(List<LatLng> points, double epsilonMeters) {
    if (points.length < 3) return List<LatLng>.from(points);
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    _markDouglasPeucker(points, 0, points.length - 1, epsilonMeters, keep);
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  void _recomputeDisplayRoute() {
    final cleaned = _cleanCoords(_routePoints);
    final simplified = cleaned.length < 3
        ? List<LatLng>.from(cleaned)
        : _simplifyRoute(cleaned, _simplifyToleranceMeters);
    _displayRouteCache =
        _enableSplineSmoothing ? _bezierLikeSpline(simplified) : simplified;
  }

  List<LatLng> _cleanCoords(List<LatLng> points) {
    if (points.length < 2) return List<LatLng>.from(points);
    final cleaned = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final previous = cleaned.last;
      final current = points[i];
      final d = _distance(previous, current);
      if (d >= _cleanCoordThresholdMeters) {
        cleaned.add(current);
      }
    }
    return cleaned;
  }

  List<LatLng> _bezierLikeSpline(List<LatLng> points) {
    if (points.length < 4) return points;
    final smoothed = <LatLng>[points.first];
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[(i + 2) < points.length ? (i + 2) : i + 1];

      for (var j = 1; j <= 3; j++) {
        final t = j / 4.0;
        final tt = t * t;
        final ttt = tt * t;
        final lat = 0.5 *
            ((2 * p1.latitude) +
                (-p0.latitude + p2.latitude) * t +
                (2 * p0.latitude -
                        5 * p1.latitude +
                        4 * p2.latitude -
                        p3.latitude) *
                    tt +
                (-p0.latitude +
                        3 * p1.latitude -
                        3 * p2.latitude +
                        p3.latitude) *
                    ttt);
        final lng = 0.5 *
            ((2 * p1.longitude) +
                (-p0.longitude + p2.longitude) * t +
                (2 * p0.longitude -
                        5 * p1.longitude +
                        4 * p2.longitude -
                        p3.longitude) *
                    tt +
                (-p0.longitude +
                        3 * p1.longitude -
                        3 * p2.longitude +
                        p3.longitude) *
                    ttt);
        smoothed.add(LatLng(lat, lng));
      }
      smoothed.add(p2);
    }
    return smoothed;
  }

  void _markDouglasPeucker(
    List<LatLng> points,
    int start,
    int end,
    double epsilonMeters,
    List<bool> keep,
  ) {
    if (end - start < 2) return;

    double maxDistance = 0.0;
    int index = -1;
    for (var i = start + 1; i < end; i++) {
      final distance =
          _distancePointToSegmentMeters(points[i], points[start], points[end]);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (index != -1 && maxDistance > epsilonMeters) {
      keep[index] = true;
      _markDouglasPeucker(points, start, index, epsilonMeters, keep);
      _markDouglasPeucker(points, index, end, epsilonMeters, keep);
    }
  }

  double _distancePointToSegmentMeters(LatLng point, LatLng start, LatLng end) {
    final meanLatRad =
        ((start.latitude + end.latitude) / 2.0) * math.pi / 180.0;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(meanLatRad);

    final sx = start.longitude * metersPerDegLng;
    final sy = start.latitude * metersPerDegLat;
    final ex = end.longitude * metersPerDegLng;
    final ey = end.latitude * metersPerDegLat;
    final px = point.longitude * metersPerDegLng;
    final py = point.latitude * metersPerDegLat;

    final dx = ex - sx;
    final dy = ey - sy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      return math.sqrt((px - sx) * (px - sx) + (py - sy) * (py - sy));
    }

    final t = (((px - sx) * dx) + ((py - sy) * dy)) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final projX = sx + clampedT * dx;
    final projY = sy + clampedT * dy;
    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
  }

  // ── 🆕 今日目標圓環 (取代舊的週報表) ──────────────────────
  Widget _buildDailyGoalRing() {
    final double progress = (currentSteps / dailyStepGoal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 16,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF59B294)),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '今日步數',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22, // Increased from 18
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    NumberFormat('#,###').format(currentSteps),
                    style: GoogleFonts.inter(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    '目標 $dailyStepGoal 步',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20, // Increased from 16
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat(
                  '步行距離', '${_totalDistance.toStringAsFixed(2)} 公里'),
              _buildSimpleStat('消耗熱量', '${(_totalDistance * 60).toInt()} 千卡'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 20, // Increased from 16
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.notoSansTc(
            fontSize: 24, // Increased from 20
            fontWeight: FontWeight.bold,
            color: const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '切換身分',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text('確定要登出並回到身分辨識頁面嗎？', style: GoogleFonts.notoSansTc()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');
              // ★ Issue 2 配套：登出後清除裝置角色記憶與監控旗標，
              //   確保下次重新配對時能重新判定通話機／監控機角色。
              await prefs.remove('saved_is_cctv');
              final deviceRoleKeys = prefs
                  .getKeys()
                  .where((k) => k.startsWith('device_role_'))
                  .toList();
              for (final key in deviceRoleKeys) {
                await prefs.remove(key);
              }

              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: Text(
              '登出',
              style: GoogleFonts.notoSansTc(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAiAssistantSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentAiName = prefs.getString('ai_assistant_name') ??
        prefs.getString('ai_name') ??
        '嘎蛙';
    final currentUserName = prefs.getString('caregiver_name') ??
        prefs.getString('user_name') ??
        prefs.getString('elder_name') ??
        (widget.userName.isNotEmpty ? widget.userName : '宇璿');
    bool isPortableMode = prefs.getBool('is_portable_mode') ?? true;

    final aiNameController = TextEditingController(text: currentAiName);
    final userNameController = TextEditingController(text: currentUserName);

    if (!mounted) return;

    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.assistant, color: Color(0xFF38BDF8)),
              const SizedBox(width: 10),
              Text(
                'AI 語音助理設定',
                style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '呼叫喚醒詞：Hey [AI名稱]\n例如："Hey 嘎蛙"',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: aiNameController,
                decoration: const InputDecoration(
                  labelText: 'AI 助理名稱',
                  hintText: '例如：嘎蛙',
                  prefixIcon: Icon(Icons.smart_toy),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: userNameController,
                decoration: const InputDecoration(
                  labelText: '長輩(設備主人)稱呼',
                  hintText: '例如：宇璿',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '📱 隨身攜帶省電模式',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  isPortableMode
                      ? '已開啟：1秒輪詢間隔（保持全時背景與休眠緊急監聽）'
                      : '已關閉：0.4秒極速回應（保持全時背景與休眠緊急監聽）',
                  style: GoogleFonts.notoSansTc(fontSize: 12),
                ),
                value: isPortableMode,
                activeThumbColor: const Color(0xFF38BDF8),
                onChanged: (val) {
                  setDialogState(() {
                    isPortableMode = val;
                  });
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  GoogleAssistantOverlay.show(
                    parentContext,
                    userName: userNameController.text.trim().isNotEmpty
                        ? userNameController.text.trim()
                        : '宇璿',
                    aiName: aiNameController.text.trim().isNotEmpty
                        ? aiNameController.text.trim()
                        : '嘎蛙',
                    userId: widget.userId,
                  );
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('測試呼叫 "Hey 嘎蛙"'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
                final navigator = Navigator.of(dialogCtx);
                final newAi = aiNameController.text.trim();
                final newUser = userNameController.text.trim();
                await prefs.setBool('is_portable_mode', isPortableMode);
                if (newAi.isNotEmpty) {
                  await prefs.setString('ai_assistant_name', newAi);
                  await prefs.setString('ai_name', newAi);
                }
                if (newUser.isNotEmpty) {
                  await prefs.setString('caregiver_name', newUser);
                  await prefs.setString('user_name', newUser);
                }
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('已儲存 AI 語音助理設定！')),
                );
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    currentSteps = _computeFusedSteps();
    final hour = DateTime.now().hour;
    String greetingTitle = '早安';
    if (hour >= 12 && hour < 18) greetingTitle = '午安';
    if (hour >= 18 || hour < 5) greetingTitle = '晚安';

    return Container(
      color: const Color(0xFFFDFCF9),
      width: double.infinity,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 溫馨標頭 (Header) ───────────────────────────
                    Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF59B294).withValues(alpha: 0.1),
                      border:
                          Border.all(color: const Color(0xFF59B294), width: 2),
                    ),
                    child: const Icon(Icons.person_rounded,
                        size: 40, color: Color(0xFF59B294)),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greetingTitle，${widget.userName}',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '今天也要開心地活動身體喔！',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                    const SizedBox(height: 32),

                    // ── 今日成就圓環 ───────────────────────────
                    _buildDailyGoalRing(),
                  ],
                ),
              ),
            ),

            // ── 登出（固定最底，留出浮動導覽列高度）─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.assistant_rounded,
                      title: 'AI 語音助理設定 (Hey 嘎蛙)',
                      color: const Color(0xFF38BDF8),
                      onTap: _showAiAssistantSettingsDialog,
                    ),
                    const Divider(height: 1, indent: 20, endIndent: 20),
                    _buildSettingsTile(
                      icon: Icons.logout_rounded,
                      title: '切換身分 / 登出',
                      color: Colors.redAccent,
                      onTap: _handleLogout,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 20),
            Text(
              title,
              style: GoogleFonts.notoSansTc(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.grey.shade300, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── 大頭貼位置點（目前位置） ────────────────────────────────
class _AvatarPin extends StatefulWidget {
  const _AvatarPin();

  @override
  State<_AvatarPin> createState() => _AvatarPinState();
}

class _AvatarPinState extends State<_AvatarPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceOffsetY;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bounceOffsetY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -7,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -7,
          end: 3,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 3,
          end: -1.5,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -1.5,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
    ]).animate(_bounceController);
    _bounceController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceOffsetY,
      builder: (context, child) {
        final dy = _bounceOffsetY.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 頭像（上方）
            Positioned(
              top: 4 + dy,
              left: 12,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE0E0E0),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const ClipOval(
                  child: Icon(Icons.person, size: 28, color: Color(0xFF757575)),
                ),
              ),
            ),
            // 倒三角（中間）
            Positioned(
              top: 57 + dy,
              left: 26,
              child: SizedBox(
                width: 20,
                height: 14,
                child: CustomPaint(
                  painter: _PinPointerPainter(),
                ),
              ),
            ),
            // 綠色圓環（所在地錨點）
            Positioned(
              left: 29,
              top: 74,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF59B294), width: 3),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PinPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pointerPath = _buildRoundedTrianglePath(size);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.save();
    canvas.translate(0, 1);
    canvas.drawPath(pointerPath, shadowPaint);
    canvas.restore();

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(pointerPath, fillPaint);
  }

  Path _buildRoundedTrianglePath(Size size) {
    const baseRadius = 2.6;
    final a = const Offset(0, 0);
    final b = Offset(size.width, 0);
    final c = Offset(size.width / 2, size.height);
    final radius = math.min(
      baseRadius,
      math.min(size.width, size.height) / 4,
    );

    final aIn = _pointToward(a, c, radius);
    final aOut = _pointToward(a, b, radius);
    final bIn = _pointToward(b, a, radius);
    final bOut = _pointToward(b, c, radius);
    final cIn = _pointToward(c, b, radius);
    final cOut = _pointToward(c, a, radius);

    return Path()
      ..moveTo(aOut.dx, aOut.dy)
      ..lineTo(bIn.dx, bIn.dy)
      ..quadraticBezierTo(b.dx, b.dy, bOut.dx, bOut.dy)
      ..lineTo(cIn.dx, cIn.dy)
      ..quadraticBezierTo(c.dx, c.dy, cOut.dx, cOut.dy)
      ..lineTo(aIn.dx, aIn.dy)
      ..quadraticBezierTo(a.dx, a.dy, aOut.dx, aOut.dy)
      ..close();
  }

  Offset _pointToward(Offset from, Offset to, double distance) {
    final vector = to - from;
    final length = vector.distance;
    if (length == 0) return from;
    final safeDistance = math.min(distance, length / 2);
    return from + (vector / length) * safeDistance;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 步數泡泡下方小三角 ──────────────────────────────────────
class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

enum _MovementState { stationary, walking, fastTransit }

class _CoordinateKalmanFilter {
  double _estimate;
  double _errorCovariance;
  final double _processNoise;

  _CoordinateKalmanFilter(
    this._estimate, {
    double processNoise = 1e-6,
    double measurementNoise = 5.0,
  })  : _processNoise = processNoise,
        _errorCovariance = measurementNoise;

  double update(double measurement, {required double measurementNoise}) {
    _errorCovariance += _processNoise;
    final kalmanGain = _errorCovariance / (_errorCovariance + measurementNoise);
    _estimate += kalmanGain * (measurement - _estimate);
    _errorCovariance *= (1.0 - kalmanGain);
    return _estimate;
  }
}
