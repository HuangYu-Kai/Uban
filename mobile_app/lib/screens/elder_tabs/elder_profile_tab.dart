import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../identification_screen.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import '../pet_companion_studio/pet_studio_screen.dart';
import '../../services/elder_reminder_manager.dart';
import '../../services/memoir_service.dart';

// 模組化子元件與彈窗
import 'profile/models/pet_mood.dart';
import 'profile/utils/coordinate_kalman_filter.dart';
import 'profile/dialogs/elder_share_story_dialog.dart';
import 'profile/dialogs/family_pairing_dialog.dart';
import 'profile/dialogs/ai_assistant_settings_dialog.dart';
import 'profile/widgets/storybook_header_card.dart';
import 'profile/widgets/storybook_stage_card.dart';
import 'profile/widgets/elder_story_prompt_banner.dart';
import 'profile/widgets/vitality_step_goals_card.dart';
import 'profile/widgets/today_tasks_handmade_section.dart';
import 'profile/widgets/friend_id_card.dart';
import 'profile/widgets/profile_action_card.dart';

class ElderProfileTab extends StatefulWidget {
  final int userId;
  final String userName;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。由
  //   上層 ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  final GlobalKey? petKey;
  final GlobalKey? tasksKey;
  final GlobalKey? familyPairingKey;
  final GlobalKey? aiAssistantKey;

  const ElderProfileTab({
    super.key,
    required this.userId,
    required this.userName,
    this.petKey,
    this.tasksKey,
    this.familyPairingKey,
    this.aiAssistantKey,
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
  CoordinateKalmanFilter? _latFilter;
  CoordinateKalmanFilter? _lngFilter;

  // ── 🐾 零負擔守護小寵物狀態 ────────────────────────────
  int _petIntimacy = 88;
  int _walkFrame = 1;
  Timer? _petWalkTimer;
  late AnimationController _particleController;
  late AnimationController _petBounceController;
  final List<PetHeartParticle> _petParticles = [];
  bool _isPetHappy = false;
  PetGrowthState? _petGrowthState;

  // ★ 第四十一輪（item 3）：朋友圈好友 ID（見 _buildMyFriendIdCard）。null 代表
  // 尚未載入完成或載入失敗，卡片自己處理 loading／錯誤態，不影響本畫面其餘邏輯。
  String? _myFriendElderId;

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

  // ── 🎙️ AI 人生故事膠囊提問引導 ──────────────────────────────
  String? _activeMemoirPrompt;
  bool _isMemoirPromptFromChild = false;

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

  // ★ 第四十一輪（item 3）：讀取朋友圈好友 ID。權威來源是後端 elder_profile
  // 表（見 FriendService.resolveMyElderId 的說明），不可用 userId 補零臆測。
  Future<void> _loadMyFriendElderId() async {
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (mounted) {
      setState(() => _myFriendElderId = id);
      // ★ 第四十三輪修復：_loadElderReminders 讀取排程提醒的權威鍵就是這裡解析
      // 出的 elder_id（見該函式說明）。initState 呼叫 _loadElderReminders 時
      // 本欄位通常還沒載入完成而被暫緩，這裡載入完成後補發一次真正的讀取。
      _loadElderReminders();
      _loadMemoirPrompt();
    }
  }

  void _onMemoirServiceUpdate() {
    if (mounted) {
      _loadMemoirPrompt();
    }
  }

  Future<void> _loadMemoirPrompt() async {
    final elderKey = _myFriendElderId ?? 'elder_${widget.userId}';
    final pending = await MemoirService.instance.getPendingPrompts(elderKey);
    if (!mounted) return;
    if (pending.isNotEmpty) {
      setState(() {
        _activeMemoirPrompt = pending.first.question;
        _isMemoirPromptFromChild = true;
        _speechText = '阿公～兒女有悄悄話想問你：「${pending.first.question}」🎙️';
      });
    } else {
      final q = await MemoirService.instance.getNextPromptQuestion(elderKey);
      if (!mounted) return;
      setState(() {
        _activeMemoirPrompt = q;
        _isMemoirPromptFromChild = false;
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
    MemoirService.instance.addListener(_onMemoirServiceUpdate);
    _loadMemoirPrompt();
    _loadPetGrowthState();
    _loadMyFriendElderId();
  }

  void _onReminderManagerUpdate() {
    if (mounted) {
      _loadElderReminders();
    }
  }

  @override
  void dispose() {
    ElderReminderManager.instance.removeListener(_onReminderManagerUpdate);
    MemoirService.instance.removeListener(_onMemoirServiceUpdate);
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
    _latFilter ??= CoordinateKalmanFilter(pos.latitude,
        measurementNoise: measurementNoise);
    _lngFilter ??= CoordinateKalmanFilter(pos.longitude,
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
        PetHeartParticle(
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
    // ★ 第四十三輪修復：排程提醒送達失敗的根因之一是讀寫用了兩把不同的鍵——
    // 家屬端寫入 `remote_reminders.elder_id` 用的是 elder_profile 的 4 碼房號
    // （見 alert_center_screen.dart:20-23 的既定寫法），這裡卻讀 widget.userId
    // （DB 整數 PK）。後端 main.py::check_remote_reminders_job 組 Socket 房名
    //／查 FCM token 都是用前者，兩把鍵對不上時，觸發會送到沒人在的房間、
    // FCM 也查無 token——長輩端前景背景兩者皆完全收不到。
    // 權威鍵與「我的好友 ID」（_myFriendElderId，見 _loadMyFriendElderId）
    // 一致，兩者都是後端 elder_profile 表解析出的同一個 4 碼 elder_id。
    // initState 會在 _myFriendElderId 尚未載入完成前先呼叫一次本函式；此時
    // 寧可暫緩本次讀取、維持讀取中畫面，也不能退回 widget.userId 兜底——那樣
    // 讀到的會是另一把鍵，等同沒修。_loadMyFriendElderId 載入完成後會再呼叫
    // 一次本函式補讀正確資料。
    final elderKey = _myFriendElderId;
    if (elderKey == null) {
      if (mounted) setState(() => _isLoadingReminders = true);
      return;
    }

    setState(() => _isLoadingReminders = true);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final completedList = prefs.getStringList('completed_tasks_$today') ?? [];
    _completedReminderIds =
        completedList.map((e) => int.tryParse(e) ?? -1).toSet();

    try {
      final list = await ApiService.getElderReminders(elderKey);
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
  PetMood _determinePetMood() {
    if (_isPetHappy) return PetMood.superHappy;

    final hour = DateTime.now().hour;
    if (hour < 6 || hour >= 22) {
      return PetMood.sleeping;
    }

    if (_movementState == _MovementState.walking || _isTracking) {
      return PetMood.walking;
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
      return PetMood.superHappy;
    }

    // 中午後如果還有子女任務尚未打卡且完成率偏低 -> 貼心叮嚀
    if (totalTasks > 0 &&
        completedTasks < totalTasks &&
        hour >= 12 &&
        (completedTasks / totalTasks) < 0.5) {
      return PetMood.reminding;
    }

    return PetMood.content;
  }

  // ── 🐾 溫暖手作繪本厚塗油畫風：小豬夥伴生活舞台 ──────────────────────
  Future<void> _openPetStudio() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PetStudioScreen(
          initialSteps: currentSteps,
          userName: widget.userName,
          userId: widget.userId,
        ),
      ),
    );
    _loadPetGrowthState();
  }

  void _showElderShareStoryDialog(BuildContext context, String prompt) {
    showElderShareStoryDialog(
      context: context,
      promptQuestion: prompt,
      isFromChild: _isMemoirPromptFromChild,
      elderId: _myFriendElderId ?? 'elder_${widget.userId}',
      onSaved: () {
        _spawnHeartParticles();
        _petBounceController.forward(from: 0.0);
        _particleController.forward(from: 0.0);
        setState(() {
          _isPetHappy = true;
          _speechText = '太棒了！阿公的故事小豬好好珍藏在回憶錄裡囉！🐽✨';
        });
        _loadMemoirPrompt();
      },
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
    final mood = _determinePetMood();
    final activeReminders =
        _reminders.where((r) => r['is_active'] != false).toList();
    final int totalTasks = activeReminders.length;
    final int completedTasks = activeReminders
        .where((r) => _completedReminderIds.contains(r['id']))
        .length;

    return Container(
      color: const Color(0xFFFAF7F2), // 溫暖手作燕麥宣紙底色
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            isLandscape ? 6 : 16,
            16,
            isLandscape ? 104 : 110,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isLandscape) {
                // ── 橫屏模式（平板座充模式）：左右雙欄對稱飽滿排版（零滾動設計） ──
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 溫馨早午晚標頭
                    StorybookHeaderCard(
                      greetingTitle: greetingTitle,
                      userName: widget.userName,
                      isLandscape: true,
                    ),

                    SizedBox(height: isLandscape ? 6 : 10),

                    // 2. 雙欄核心內容區（左：夥伴與健康雙環，右：排程打卡與快捷操作）
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 👈 左欄：手繪小豬生活舞台 ＆ 今日健康活力雙環 (佔 50%)
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              StorybookStageCard(
                                key: widget.petKey,
                                isLandscape: true,
                                petMood: mood,
                                stepProgress: (dailyStepGoal > 0)
                                    ? (currentSteps / dailyStepGoal).clamp(0.0, 1.0)
                                    : 0.0,
                                totalTasks: totalTasks,
                                completedTasks: completedTasks,
                                petGrowthState: _petGrowthState,
                                speechText: _speechText,
                                petParticles: _petParticles,
                                onTap: _openPetStudio,
                              ),
                              if (_activeMemoirPrompt != null) ...[
                                const SizedBox(height: 8),
                                ElderStoryPromptBanner(
                                  isLandscape: true,
                                  prompt: _activeMemoirPrompt ?? '跟小豬說說你年輕時的故事好不好？',
                                  isFromChild: _isMemoirPromptFromChild,
                                  onTap: () => _showElderShareStoryDialog(
                                    context,
                                    _activeMemoirPrompt ?? '跟小豬說說你年輕時的故事好不好？',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              VitalityStepGoalsCard(
                                progress: progress,
                                currentSteps: currentSteps,
                                dailyStepGoal: dailyStepGoal,
                                totalDistance: _totalDistance,
                                completedReminderIds: _completedReminderIds,
                                isLandscape: true,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // 👉 右欄：今日生活用藥打卡手帳 ＆ 底部快捷操作列 (佔 50%)
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TodayTasksHandmadeSection(
                                key: widget.tasksKey,
                                reminders: _reminders,
                                completedReminderIds: _completedReminderIds,
                                isLoadingReminders: _isLoadingReminders,
                                onToggleTask: _toggleTaskCompletion,
                                isLandscape: true,
                              ),
                              const SizedBox(height: 8),
                              // 底部快捷操作列（橫排三鍵）
                              Row(
                                children: [
                                  // 👨‍👩‍👧 家人綁定
                                  Expanded(
                                    child: ProfileActionCard(
                                      key: widget.familyPairingKey,
                                      icon: Icons.family_restroom_rounded,
                                      title: '家人綁定',
                                      subtitle: '出示配對碼',
                                      color: const Color(0xFFEA580C),
                                      onTap: () => showFamilyPairingDialog(context),
                                      isLandscape: true,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 🤖 語音助理
                                  Expanded(
                                    child: ProfileActionCard(
                                      key: widget.aiAssistantKey,
                                      icon: Icons.assistant_rounded,
                                      title: '語音助理',
                                      subtitle: 'Hey 嘎蛙',
                                      color: const Color(0xFF0284C7),
                                      onTap: () => showAiAssistantSettingsDialog(
                                        context: context,
                                        userId: widget.userId,
                                        userName: widget.userName,
                                      ),
                                      isLandscape: true,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 🚪 切換身分
                                  Expanded(
                                    child: ProfileActionCard(
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
                    StorybookHeaderCard(
                      greetingTitle: greetingTitle,
                      userName: widget.userName,
                    ),

                    const SizedBox(height: 16),

                    // 2. 小豬生活手繪舞台 ＆ 成長里程碑
                    StorybookStageCard(
                      key: widget.petKey,
                      petMood: mood,
                      stepProgress: (dailyStepGoal > 0)
                          ? (currentSteps / dailyStepGoal).clamp(0.0, 1.0)
                          : 0.0,
                      totalTasks: totalTasks,
                      completedTasks: completedTasks,
                      petGrowthState: _petGrowthState,
                      speechText: _speechText,
                      petParticles: _petParticles,
                      onTap: _openPetStudio,
                    ),

                    if (_activeMemoirPrompt != null) ...[
                      const SizedBox(height: 12),
                      ElderStoryPromptBanner(
                        prompt: _activeMemoirPrompt ?? '跟小豬說說你年輕時的故事好不好？',
                        isFromChild: _isMemoirPromptFromChild,
                        onTap: () => _showElderShareStoryDialog(
                          context,
                          _activeMemoirPrompt ?? '跟小豬說說你年輕時的故事好不好？',
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 3. 今日生活排程與用藥打卡手帳
                    TodayTasksHandmadeSection(
                      key: widget.tasksKey,
                      reminders: _reminders,
                      completedReminderIds: _completedReminderIds,
                      isLoadingReminders: _isLoadingReminders,
                      onToggleTask: _toggleTaskCompletion,
                    ),

                    const SizedBox(height: 16),

                    // 4. 今日健康活力雙環
                    VitalityStepGoalsCard(
                      progress: progress,
                      currentSteps: currentSteps,
                      dailyStepGoal: dailyStepGoal,
                      totalDistance: _totalDistance,
                      completedReminderIds: _completedReminderIds,
                    ),

                    const SizedBox(height: 16),

                    // ★ 第四十一輪（item 3）：朋友圈好友 ID 卡片。
                    FriendIdCard(
                      myFriendElderId: _myFriendElderId,
                    ),

                    const SizedBox(height: 16),

                    // 5. 底部快捷操作列
                    Row(
                      children: [
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.familyPairingKey,
                            icon: Icons.family_restroom_rounded,
                            title: '家人綁定',
                            subtitle: '出示配對碼',
                            color: const Color(0xFFEA580C),
                            onTap: () => showFamilyPairingDialog(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.aiAssistantKey,
                            icon: Icons.assistant_rounded,
                            title: '語音助理',
                            subtitle: 'Hey 嘎蛙',
                            color: const Color(0xFF0284C7),
                            onTap: () => showAiAssistantSettingsDialog(
                              context: context,
                              userId: widget.userId,
                              userName: widget.userName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ProfileActionCard(
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

enum _MovementState { stationary, walking, fastTransit }


