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
import 'package:flutter/services.dart';
import '../identification_screen.dart';
import '../../globals.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../widgets/google_assistant_overlay.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import '../pet_companion_studio/pet_studio_screen.dart';
import '../pet_companion_studio/widgets/animated_piglet_actor.dart';
import '../pet_companion_studio/widgets/hand_drawn_piglet_actor.dart';
import '../pet_companion_studio/widgets/pet_growth_scale_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/elder_reminder_manager.dart';

enum _PetMood {
  superHappy, // 活力滿滿 / 達標 / 任務100% / 摸摸
  walking,    // 散步走動中
  content,    // 悠哉陪伴中
  reminding,  // 子女排程待辦提醒
  sleeping,   // 休息睡眠中
}

class _PetHeartParticle {
  Offset position;
  Offset velocity;
  double scale;
  double opacity;
  Color color;

  _PetHeartParticle({
    required this.position,
    required this.velocity,
    required this.scale,
    required this.opacity,
    required this.color,
  });
}

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
  // ★ 切換為真實感測模式（關閉模擬假資料）
  static const bool _useMockRoute = false;
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

  // ── 🐾 零負擔守護小寵物狀態 ────────────────────────────
  int _petIntimacy = 88;
  int _walkFrame = 1;
  Timer? _petWalkTimer;
  late AnimationController _particleController;
  late AnimationController _petBounceController;
  final List<_PetHeartParticle> _petParticles = [];
  bool _isPetHappy = false;
  PetGrowthState? _petGrowthState;

  // ── 📋 子女排程生活任務 ──────────────────────────────────
  List<Map<String, dynamic>> _reminders = [];
  Set<int> _completedReminderIds = {};
  bool _isLoadingReminders = false;

  // ── 🎨 手作繪本對話與溫暖語錄 ──────────────────────────────
  String _speechText = '阿公～今天天氣真好，一起散步活動身體吧！🌿';
  Timer? _speechBubbleTimer;
  final List<String> _pigQuotes = [
    '阿公～有您天天陪我，小豬每天都好幸福喔！❤️',
    '記得要多喝溫水，小豬也陪您喝一杯！🍵',
    '今天走起路來很有精神呢，我們一起加油！💪',
    '摸摸我的圓滾肚子，把平安福氣都帶給您！✨',
    '中午要記得吃飽飽，休息一下再散步唷！🍙',
    '看到阿公笑瞇瞇的，小豬的心情最開心了！🌸',
  ];
  final int _quoteIndex = 0;


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/pet_stages/pig_stage_1.png'), context);
    precacheImage(const AssetImage('assets/images/pet_stages/pig_stage_2.png'), context);
    precacheImage(const AssetImage('assets/images/pet_stages/pig_stage_3.png'), context);
    precacheImage(const AssetImage('assets/images/pet_stages/pig_stage_4.png'), context);
    precacheImage(const AssetImage('assets/images/pet_stages/pig_stage_5.png'), context);
    precacheImage(const AssetImage('assets/images/pig_mascot.png'), context);
  }

  Future<void> _loadPetGrowthState() async {
    final state = await PetStorageService.loadState(currentSensorSteps: currentSteps);
    if (mounted) {
      setState(() {
        _petGrowthState = state;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    _particleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..addListener(_updateParticles);

    _petBounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _petWalkTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (!mounted) return;
      if (_movementState == _MovementState.walking || _isTracking) {
        setState(() {
          _walkFrame = _walkFrame == 1 ? 2 : 1;
        });
      }
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });

    _autoStartTracking();
    _startStepTracking();
    _loadElderReminders();
    ElderReminderManager.instance.addListener(_onReminderManagerUpdate);
    _loadPetGrowthState();
  }

  void _onReminderManagerUpdate() {
    if (mounted) {
      _loadElderReminders();
    }
  }

  @override
  void dispose() {
    ElderReminderManager.instance.removeListener(_onReminderManagerUpdate);
    _ctrl.dispose();
    _particleController.dispose();
    _petBounceController.dispose();
    _petWalkTimer?.cancel();
    _speechBubbleTimer?.cancel();
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
    final wasMock = prefs.getBool('is_mock_route_persisted') ?? false;

    if (dateStr != today || wasMock) {
      await prefs.remove('route_points');
      await prefs.setDouble('total_distance', 0.0);
      await prefs.setInt('session_pedometer_steps', 0);
      await prefs.setString('last_track_date', today);
      await prefs.setBool('is_mock_route_persisted', false);
      setState(() {
        _routePoints.clear();
        _totalDistance = 0.0;
        _sessionPedometerSteps = 0;
        _displayRouteCache.clear();
      });
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
    await prefs.setBool('is_mock_route_persisted', _useMockRoute);
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
            maxZoom: 17.0, // ★ 限制自動適應縮放最大為 17.0，避免在短距離或原地時地圖放超大
            minZoom: 12.0,
          ),
        );
      } catch (_) {}
      return;
    }
    if (_currentPosition != null && _mapController.camera.zoom != 0) {
      _mapController.move(_currentPosition!, 16.5);
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

  void _spawnHeartParticles() {
    _petParticles.clear();
    final rand = math.Random();
    const colors = [
      Color(0xFFFF6B8B),
      Color(0xFFFF8E53),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFFA855F7),
    ];
    for (int i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + (rand.nextDouble() - 0.5) * 1.4;
      final speed = 70.0 + rand.nextDouble() * 100.0;
      _petParticles.add(
        _PetHeartParticle(
          position: Offset(65.0 + (rand.nextDouble() - 0.5) * 36, 65.0),
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          scale: 0.8 + rand.nextDouble() * 0.6,
          opacity: 1.0,
          color: colors[rand.nextInt(colors.length)],
        ),
      );
    }
  }

  void _updateParticles() {
    if (_petParticles.isEmpty) return;
    final progress = _particleController.value;
    for (final p in _petParticles) {
      p.position += p.velocity * 0.016;
      p.opacity = (1.0 - progress).clamp(0.0, 1.0);
      p.scale = math.max(0.2, p.scale * 0.98);
    }
    setState(() {});
  }

  // ── 📋 載入子女排程生活任務 ──────────────────────────────────
  Future<void> _loadElderReminders() async {
    setState(() => _isLoadingReminders = true);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final completedList = prefs.getStringList('completed_tasks_$today') ?? [];
    _completedReminderIds =
        completedList.map((e) => int.tryParse(e) ?? -1).toSet();

    try {
      final list = await ApiService.getElderReminders(widget.userId.toString());
      if (mounted) {
        setState(() {
          if (list.isNotEmpty) {
            _reminders = List<Map<String, dynamic>>.from(list);
          } else {
            _reminders = [
              {
                'id': 101,
                'title': '早上按時服藥',
                'time_str': '08:30',
                'category': 'medication',
                'note': '飯後服用降血壓藥物',
                'is_active': true,
              },
              {
                'id': 102,
                'title': '補充溫開水 500cc',
                'time_str': '11:00',
                'category': 'water',
                'note': '多喝溫水促進代謝',
                'is_active': true,
              },
              {
                'id': 103,
                'title': '傍晚活力散步 20 分鐘',
                'time_str': '16:30',
                'category': 'exercise',
                'note': '到戶外走走活動筋骨',
                'is_active': true,
              },
            ];
          }
          _isLoadingReminders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingReminders = false);
      }
    }
  }

  // ── 🎯 任務打卡完成切換 ────────────────────────────────────
  Future<void> _toggleTaskCompletion(int reminderId) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final isAlreadyDone = _completedReminderIds.contains(reminderId);
    setState(() {
      if (isAlreadyDone) {
        _completedReminderIds.remove(reminderId);
      } else {
        _completedReminderIds.add(reminderId);
        _isPetHappy = true;
        _petIntimacy = math.min(100, _petIntimacy + 3);
        _speechText = '太棒了！生活排程打卡成功，小豬好開心！🎉';
        _spawnHeartParticles();
        _petBounceController.forward(from: 0.0);
        _particleController.forward(from: 0.0);
        _speechBubbleTimer?.cancel();
        _speechBubbleTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _isPetHappy = false;
              _speechText = _pigQuotes[_quoteIndex];
            });
          }
        });
      }
    });

    await prefs.setStringList(
      'completed_tasks_$today',
      _completedReminderIds.map((e) => e.toString()).toList(),
    );
  }

  // ── 🧠 寵物心情判定引擎（結合健康步數與子女任務）──────────────
  _PetMood _determinePetMood() {
    if (_isPetHappy) return _PetMood.superHappy;

    final hour = DateTime.now().hour;
    if (hour < 6 || hour >= 22) {
      return _PetMood.sleeping;
    }

    if (_movementState == _MovementState.walking || _isTracking) {
      return _PetMood.walking;
    }

    final double stepProgress = (currentSteps / dailyStepGoal).clamp(0.0, 1.0);
    final activeReminders =
        _reminders.where((r) => r['is_active'] != false).toList();
    final int totalTasks = activeReminders.length;
    final int completedTasks = activeReminders
        .where((r) => _completedReminderIds.contains(r['id']))
        .length;

    // 步數達成 100% 或 子女排程任務全部完成 -> 超開心
    if (stepProgress >= 1.0 || (totalTasks > 0 && completedTasks >= totalTasks)) {
      return _PetMood.superHappy;
    }

    // 中午後如果還有子女任務尚未打卡且完成率偏低 -> 貼心叮嚀
    if (totalTasks > 0 &&
        completedTasks < totalTasks &&
        hour >= 12 &&
        (completedTasks / totalTasks) < 0.5) {
      return _PetMood.reminding;
    }

    return _PetMood.content;
  }

  // ── 🐾 溫暖手作繪本厚塗油畫風：小豬夥伴生活舞台 ──────────────────────
  Future<void> _openPetStudio() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PetStudioScreen(
          initialSteps: currentSteps,
          userName: widget.userName,
        ),
      ),
    );
    _loadPetGrowthState();
  }

  Widget _buildStorybookPetStageCard({bool isLandscape = false}) {
    final mood = _determinePetMood();
    final activeReminders =
        _reminders.where((r) => r['is_active'] != false).toList();
    final int totalTasks = activeReminders.length;
    final int completedTasks = activeReminders
        .where((r) => _completedReminderIds.contains(r['id']))
        .length;
    final double stepProgress = (dailyStepGoal > 0)
        ? (currentSteps / dailyStepGoal).clamp(0.0, 1.0)
        : 0.0;

    String moodLabel;
    IconData moodIcon;
    Color moodThemeColor;

    switch (mood) {
      case _PetMood.superHappy:
        moodLabel = (totalTasks > 0 && completedTasks >= totalTasks)
            ? '任務全達標 🎉'
            : (stepProgress >= 1.0 ? '步數達成 👑' : '活力滿分 🌟');
        moodIcon = Icons.stars_rounded;
        moodThemeColor = const Color(0xFFF59E0B);
        break;
      case _PetMood.walking:
        moodLabel = '同行漫步中';
        moodIcon = Icons.directions_walk_rounded;
        moodThemeColor = const Color(0xFF0284C7);
        break;
      case _PetMood.sleeping:
        moodLabel = '乖乖休息中';
        moodIcon = Icons.bedtime_rounded;
        moodThemeColor = const Color(0xFF8B5CF6);
        break;
      case _PetMood.reminding:
        moodLabel = '生活待辦提醒';
        moodIcon = Icons.notifications_active_rounded;
        moodThemeColor = const Color(0xFFF97316);
        break;
      case _PetMood.content:
        moodLabel = '元氣陪伴中';
        moodIcon = Icons.favorite_rounded;
        moodThemeColor = const Color(0xFF059669);
        break;
    }

    final currentGrowthState = _petGrowthState ??
        const PetGrowthState(
          weightGrams: 28000,
          vitality: 88,
          todaySteps: 3500,
          fedFoodIds: {},
          lastDateStr: '',
          isCrownUnlocked: false,
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openPetStudio,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: EdgeInsets.all(isLandscape ? 16 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── A. 標頭列：夥伴名稱 ＋ 心情膠囊 ＋ 前往小豬的家標籤 ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🐽', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的元氣小豬夥伴',
                            style: GoogleFonts.notoSansTc(
                              fontSize: isLandscape ? 17 : 18,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF451A03),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // 心情標籤膠囊
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: moodThemeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(moodIcon, size: 13, color: moodThemeColor),
                                const SizedBox(width: 4),
                                Text(
                                  moodLabel,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: moodThemeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 🏡 小豬的家標籤（提示長輩點擊全卡片皆可進入）
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 12 : 14,
                        vertical: isLandscape ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🏡', style: TextStyle(fontSize: 15)),
                          const SizedBox(width: 5),
                          Text(
                            '小豬的家',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: Color(0xFF92400E),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: isLandscape ? 8 : 14),

                // ── B. 核心小豬正面手繪油畫舞台（移除點擊彈跳動畫，點擊全卡直接進入小豬的家）──
                IgnorePointer(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // 呼吸背景微暈
                      Container(
                        width: isLandscape ? 160 : 200,
                        height: isLandscape ? 160 : 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              moodThemeColor.withValues(alpha: 0.16),
                              moodThemeColor.withValues(alpha: 0.03),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),

                      // 愛心粒子噴發層（用於生活任務打卡慶祝）
                      if (_petParticles.isNotEmpty)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PetHeartPainter(_petParticles),
                          ),
                        ),

                      // 小豬油畫主角與對話氣泡
                      HandDrawnPigletActor(
                        size: isLandscape ? 165 : 195,
                        stage: currentGrowthState.stage,
                        mood: mood == _PetMood.superHappy
                            ? ActorMood.superHappy
                            : (mood == _PetMood.sleeping
                                ? ActorMood.sleeping
                                : (mood == _PetMood.reminding
                                    ? ActorMood.anticipating
                                    : ActorMood.idle)),
                        speechText: _speechText,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isLandscape ? 8 : 14),

                // ── C. 體重秤與成長階段卡（PetGrowthScaleCard，透過外層卡片統一跳轉）──
                IgnorePointer(
                  child: PetGrowthScaleCard(
                    growthState: currentGrowthState,
                    isCompact: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 🎯 今日健康活力雙環 ＆ 四合一指標卡片 ──────────────────────
  Widget _buildVitalityStepGoalsCard(double progress, {bool isLandscape = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 16 : 20,
        vertical: isLandscape ? 12 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: const Color(0xFF59B294).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 今日健康活力指標 Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Text('🎯', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Text(
                '今日健康活力雙環',
                style: GoogleFonts.notoSansTc(
                  fontSize: isLandscape ? 16 : 17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF451A03),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 8 : 10,
                  vertical: isLandscape ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EBE1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '目標 $dailyStepGoal 步',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 11.5 : 12.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF78350F),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: isLandscape ? 10 : 16),

          // ── 步數大圓環 ＋ 4-in-1 健康指標 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 步數圓環
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: isLandscape ? 86 : 110,
                    height: isLandscape ? 86 : 110,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: isLandscape ? 8 : 10,
                      backgroundColor: const Color(0xFFF1EBE1),
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
                          fontSize: isLandscape ? 10.5 : 12,
                          color: const Color(0xFF8C6D58),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        NumberFormat('#,###').format(currentSteps),
                        style: GoogleFonts.inter(
                          fontSize: isLandscape ? 18 : 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF451A03),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}% 達成',
                        style: GoogleFonts.notoSansTc(
                          fontSize: isLandscape ? 10 : 11.5,
                          color: const Color(0xFF59B294),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SizedBox(width: isLandscape ? 12 : 14),

              // 4-in-1 指標格
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStorybookStatTile(
                            icon: Icons.directions_walk_rounded,
                            iconColor: const Color(0xFF0284C7),
                            label: '步行距離',
                            value: '${_totalDistance.toStringAsFixed(2)} 公里',
                            isLandscape: isLandscape,
                          ),
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                        Expanded(
                          child: _buildStorybookStatTile(
                            icon: Icons.local_fire_department_rounded,
                            iconColor: const Color(0xFFF97316),
                            label: '消耗熱量',
                            value: '${(_totalDistance * 60).toInt()} 千卡',
                            isLandscape: isLandscape,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isLandscape ? 6 : 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStorybookStatTile(
                            icon: Icons.timer_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            label: '活動時間',
                            value:
                                '${(_totalDistance > 0 ? (_totalDistance / 3.2 * 60).toInt() : (currentSteps ~/ 100)).clamp(0, 180)} 分鐘',
                            isLandscape: isLandscape,
                          ),
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                        Expanded(
                          child: _buildStorybookStatTile(
                            icon: Icons.water_drop_rounded,
                            iconColor: const Color(0xFF06B6D4),
                            label: '溫水補充',
                            value: _completedReminderIds.contains(102)
                                ? '1,000 毫升'
                                : '500 毫升',
                            isLandscape: isLandscape,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorybookStatTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isLandscape = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 8 : 10,
        vertical: isLandscape ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(isLandscape ? 14 : 16),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isLandscape ? 5 : 6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: isLandscape ? 16 : 18),
          ),
          SizedBox(width: isLandscape ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 10.5 : 11.5,
                    color: const Color(0xFF78350F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: isLandscape ? 13 : 14.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF451A03),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 📋 今日生活排程與用藥打卡手帳（直接呈現在卡片上，支援大字體打卡）──
  Widget _buildTodayTasksHandmadeSection({bool isLandscape = false}) {
    final activeReminders =
        _reminders.where((r) => r['is_active'] != false).toList();
    final totalTasks = activeReminders.length;
    final completedTasks = activeReminders
        .where((r) => _completedReminderIds.contains(r['id']))
        .length;
    final bool isAllCompleted = totalTasks > 0 && completedTasks >= totalTasks;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 16 : 20,
        vertical: isLandscape ? 12 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標頭
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isLandscape ? 5 : 7),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: Text('📋', style: TextStyle(fontSize: isLandscape ? 15 : 18)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日生活排程與用藥',
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 16.5 : 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                      ),
                    ),
                    Text(
                      '點擊打卡即可完成，小豬陪您規律生活',
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 11.5 : 12.5,
                        color: const Color(0xFF8C6D58),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // 完成進度標籤
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 8 : 10,
                  vertical: isLandscape ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: isAllCompleted
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAllCompleted
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  isAllCompleted ? '全數達標 🌟' : '已完成 $completedTasks/$totalTasks',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 12 : 13,
                    fontWeight: FontWeight.w900,
                    color: isAllCompleted
                        ? const Color(0xFF047857)
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: isLandscape ? 8 : 14),

          if (_isLoadingReminders)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF59B294)),
              ),
            )
          else if (activeReminders.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                '今天尚無待辦事項，悠閒放鬆一下吧！🌸',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeReminders.length,
              separatorBuilder: (_, __) => SizedBox(height: isLandscape ? 6 : 10),
              itemBuilder: (context, index) {
                final r = activeReminders[index];
                final int rId = r['id'] as int;
                final bool isDone = _completedReminderIds.contains(rId);
                final String cat = (r['category'] ?? '').toString();

                String catEmoji = '⏰';
                Color catBg = const Color(0xFFF1F5F9);
                if (cat == 'medication') {
                  catEmoji = '💊';
                  catBg = const Color(0xFFFFE4E6);
                } else if (cat == 'water') {
                  catEmoji = '💧';
                  catBg = const Color(0xFFE0F2FE);
                } else if (cat == 'exercise') {
                  catEmoji = '👟';
                  catBg = const Color(0xFFFEF3C7);
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleTaskCompletion(rId),
                    borderRadius: BorderRadius.circular(isLandscape ? 16 : 20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isLandscape ? 6 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFAF7F2),
                        borderRadius: BorderRadius.circular(isLandscape ? 16 : 20),
                        border: Border.all(
                          color: isDone
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFEADBCE),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 類別 Emoji 圖標
                          Container(
                            width: isLandscape ? 38 : 44,
                            height: isLandscape ? 38 : 44,
                            decoration: BoxDecoration(
                              color: catBg,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                catEmoji,
                                style: TextStyle(fontSize: isLandscape ? 18 : 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 內容文字
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDone
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFF5EBE1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        r['time_str'] ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: isLandscape ? 11.5 : 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDone
                                              ? const Color(0xFF15803D)
                                              : const Color(0xFF78350F),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        r['title'] ?? '',
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: isLandscape ? 15 : 16.5,
                                          fontWeight: FontWeight.w900,
                                          color: isDone
                                              ? const Color(0xFF166534)
                                              : const Color(0xFF451A03),
                                          decoration: isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((r['note'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    r['note'],
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: isLandscape ? 11.5 : 13,
                                      color: isDone
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFF78350F),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // ── 大字體觸控打卡核選扭 ──
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isLandscape ? 10 : 12,
                              vertical: isLandscape ? 5 : 7,
                            ),
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFF10B981)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFF59E0B),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isDone
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.18),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle_rounded
                                      : Icons.touch_app_rounded,
                                  size: isLandscape ? 14 : 16,
                                  color: isDone
                                      ? Colors.white
                                      : const Color(0xFF92400E),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isDone ? '已打卡' : '打卡',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: isLandscape ? 12 : 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDone
                                        ? Colors.white
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          SizedBox(height: isLandscape ? 8 : 14),

          // 溫馨提示字卡
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 12 : 14,
              vertical: isLandscape ? 6 : 9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Text('💡', style: TextStyle(fontSize: isLandscape ? 13 : 15)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '定時服藥與多喝溫水，小豬會長得圓滾有元氣喔！',
                    style: GoogleFonts.notoSansTc(
                      fontSize: isLandscape ? 11.5 : 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 溫馨早午晚標頭 (手繪厚塗繪本風格) ──────────────────────────
  Widget _buildStorybookHeader(String greetingTitle, {bool isLandscape = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 18 : 20,
        vertical: isLandscape ? 9 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isLandscape ? 46 : 58,
            height: isLandscape ? 46 : 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF59B294).withValues(alpha: 0.15),
              border: Border.all(color: const Color(0xFF59B294), width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF59B294).withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text('👴', style: TextStyle(fontSize: isLandscape ? 26 : 32)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$greetingTitle，${widget.userName}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 21 : 25,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 8 : 10,
                        vertical: isLandscape ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌿', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            '守護中',
                            style: GoogleFonts.notoSansTc(
                              fontSize: isLandscape ? 11 : 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLandscape ? 1 : 3),
                Text(
                  '${DateTime.now().month}月${DateTime.now().day}日 · 今天也要開開心心地活動身體喔！✨',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 13 : 14.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8C6D58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              // ★ 2026-08-10 第二十輪：改走 SessionManager 統一釋放入口，
              //   除了原本清的 device_role_*／saved_is_cctv，
              //   也一併清掉 user_role，避免殘留 'elder' 造成下次冷啟動被誤判為長輩 session。
              // ★ 2026-08-25（本輪）：這是長輩自己主動按「登出」，不是家屬遠端強制
              //   解綁，帶 preserveQuickLogin: true 保留 last_elder_* 快速登入記憶鍵
              //   （護欄 G24），讓下次可以在配對頁「快速登入同一長輩」一鍵登回。
              await SessionManager.releaseSession(preserveQuickLogin: true);

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
    // ★ 語音喚醒總開關，長輩端預設啟用（true）。
    bool wakeWordEnabled = prefs.getBool(kWakeWordEnabledKey) ?? true;

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
              // ★ 2026-08-10 第二十輪（需求 6）：語音喚醒總開關。
              //   預設關閉——常駐監聽會讓麥克風不斷 acquire/release（系統指示燈
              //   一直閃），環境雜音也容易誤觸。需要免持喚醒的長輩再自行開啟。
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '🎙️ 語音喚醒（免持呼叫 AI）',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  wakeWordEnabled
                      ? '已開啟：麥克風全時待命，說出喚醒詞即可呼叫 AI（較耗電）'
                      : '已關閉：麥克風不會自動開啟，改由畫面上的按鈕呼叫 AI',
                  style: GoogleFonts.notoSansTc(fontSize: 12),
                ),
                value: wakeWordEnabled,
                activeThumbColor: const Color(0xFF38BDF8),
                onChanged: (val) {
                  setDialogState(() {
                    wakeWordEnabled = val;
                  });
                },
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
                // ★ 2026-08-10 第二十輪（需求 6）：寫入 prefs 後同步更新 notifier，
                //   讓 ElderHomeScreen 立刻啟動／停止監聽，不必重開 App。
                await prefs.setBool(kWakeWordEnabledKey, wakeWordEnabled);
                wakeWordEnabledNotifier.value = wakeWordEnabled;
                if (newAi.isNotEmpty) {
                  await prefs.setString('ai_assistant_name', newAi);
                  await prefs.setString('ai_name', newAi);
                }
                if (newUser.isNotEmpty) {
                  await prefs.setString('caregiver_name', newUser);
                  await prefs.setString('user_name', newUser);
                  await prefs.setString('elder_appellation', newUser);
                  try {
                    await ApiService.updateElderProfile(
                      userId: widget.userId,
                      appellation: newUser,
                    );
                  } catch (_) {}
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

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isLandscape = false,
  }) {
    return Material(
      color: const Color(0xFFFFFDF9),
      borderRadius: BorderRadius.circular(isLandscape ? 18 : 24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isLandscape ? 18 : 24),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 12 : 16,
            vertical: isLandscape ? 9 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isLandscape ? 18 : 24),
            border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF78350F).withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isLandscape ? 8 : 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: isLandscape ? 20 : 26),
              ),
              SizedBox(width: isLandscape ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 15.5 : 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isLandscape ? 1 : 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 12 : 13.5,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: isLandscape ? 13 : 15,
                color: const Color(0xFFD4C5B9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔄 方案 C：隨時後續補綁定家人對話框（Late-Binding）
  void _showFamilyPairingDialog() {
    HapticFeedback.lightImpact();
    final String elderCode = widget.userId.toString().padLeft(4, '0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.family_restroom_rounded,
                  color: Color(0xFFEA580C), size: 28),
            ),
            const SizedBox(width: 12),
            Text(
              '家人／照護者綁定',
              style: GoogleFonts.notoSansTc(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '請子女開啟手機上的 Uban App，掃描下方 QR Code 或輸入配對碼即可完成連線：',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFDBA74), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      elderCode,
                      style: GoogleFonts.inter(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFEA580C),
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: 'UBAN_PAIR:${widget.userId}:$elderCode',
                      version: QrVersions.auto,
                      size: 140.0,
                      backgroundColor: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF059669), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '綁定後，子女可遠端排定吃藥，並即時關心您的每日健康與小豬！',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13.5,
                          color: const Color(0xFF065F46),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '知道了',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF59B294),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    currentSteps = _computeFusedSteps();
    final double progress = (currentSteps / dailyStepGoal).clamp(0.0, 1.0);
    final hour = DateTime.now().hour;
    String greetingTitle = '早安';
    if (hour >= 12 && hour < 18) greetingTitle = '午安';
    if (hour >= 18 || hour < 5) greetingTitle = '晚安';
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width >= 720;

    return Container(
      color: const Color(0xFFFAF7F2), // 溫暖手作燕麥宣紙底色
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            18,
            isLandscape ? 10 : 16,
            18,
            isLandscape ? 106 : 110,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isLandscape) {
                // ── 橫屏模式（平板座充模式）：左右雙欄對稱飽滿排版（零滾動設計） ──
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 溫馨早午晚標頭
                    _buildStorybookHeader(greetingTitle, isLandscape: true),

                    const SizedBox(height: 10),

                    // 2. 雙欄核心內容區
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 👈 左欄：手繪小豬生活舞台 ＆ 成長里程碑 (佔 50%)
                        Expanded(
                          flex: 5,
                          child: _buildStorybookPetStageCard(isLandscape: true),
                        ),

                        const SizedBox(width: 14),

                        // 👉 右欄：今日生活用藥打卡手帳 ＆ 健康活力雙環 (佔 50%)
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTodayTasksHandmadeSection(isLandscape: true),
                              const SizedBox(height: 10),
                              _buildVitalityStepGoalsCard(progress, isLandscape: true),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 3. 底部快捷操作列
                    Row(
                      children: [
                        // 👨‍👩‍👧 家人綁定
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.family_restroom_rounded,
                            title: '家人綁定',
                            subtitle: '出示配對碼',
                            color: const Color(0xFFEA580C),
                            onTap: _showFamilyPairingDialog,
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 🤖 語音助理
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.assistant_rounded,
                            title: '語音助理',
                            subtitle: 'Hey 嘎蛙',
                            color: const Color(0xFF0284C7),
                            onTap: _showAiAssistantSettingsDialog,
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 🚪 切換身分
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.logout_rounded,
                            title: '切換身分',
                            subtitle: '登出系統',
                            color: const Color(0xFFEF4444),
                            onTap: _handleLogout,
                            isLandscape: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              } else {
                // ── 直屏模式：垂直手帳滑動流 ──
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 溫馨早午晚標頭
                    _buildStorybookHeader(greetingTitle),

                    const SizedBox(height: 16),

                    // 2. 小豬生活手繪舞台 ＆ 成長里程碑
                    _buildStorybookPetStageCard(),

                    const SizedBox(height: 16),

                    // 3. 今日生活排程與用藥打卡手帳
                    _buildTodayTasksHandmadeSection(),

                    const SizedBox(height: 16),

                    // 4. 今日健康活力雙環
                    _buildVitalityStepGoalsCard(progress),

                    const SizedBox(height: 16),

                    // 5. 底部快捷操作列
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.family_restroom_rounded,
                            title: '家人綁定',
                            subtitle: '出示配對碼',
                            color: const Color(0xFFEA580C),
                            onTap: _showFamilyPairingDialog,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.assistant_rounded,
                            title: '語音助理',
                            subtitle: 'Hey 嘎蛙',
                            color: const Color(0xFF0284C7),
                            onTap: _showAiAssistantSettingsDialog,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.logout_rounded,
                            title: '切換身分',
                            subtitle: '登出系統',
                            color: const Color(0xFFEF4444),
                            onTap: _handleLogout,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
            },
          ),
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

// ── 🐾 寵物摸摸愛心粒子繪製器 ──────────────────────────────────
class _PetHeartPainter extends CustomPainter {
  final List<_PetHeartParticle> particles;

  _PetHeartPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;
      _drawHeart(canvas, p.position, 16 * p.scale, paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final w = size;
    final h = size;
    final x = center.dx - w / 2;
    final y = center.dy - h / 2;

    path.moveTo(x + w / 2, y + h / 4);
    path.cubicTo(x + w / 2, y, x, y, x, y + h / 3);
    path.cubicTo(x, y + h / 2, x + w / 2, y + h * 0.8, x + w / 2, y + h);
    path.cubicTo(x + w / 2, y + h * 0.8, x + w, y + h / 2, x + w, y + h / 3);
    path.cubicTo(x + w, y, x + w / 2, y, x + w / 2, y + h / 4);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PetHeartPainter oldDelegate) => true;
}
