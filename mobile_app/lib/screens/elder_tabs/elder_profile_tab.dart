import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../identification_screen.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import '../pet_companion_studio/models/pet_food_item.dart';
import '../pet_companion_studio/widgets/garden_feeding_sheet.dart';
import '../../services/elder_reminder_manager.dart';
import '../../widgets/spotlight_tutorial.dart';

// 模組化子元件與彈窗
import 'profile/models/pet_mood.dart'; // ⚠️ 只借用 PetHeartParticle，PetMood 列舉本身在小豬之家改版後已不再使用
import 'profile/utils/coordinate_kalman_filter.dart';
import 'profile/dialogs/family_pairing_dialog.dart';
import 'profile/dialogs/ai_assistant_settings_dialog.dart';
import 'profile/widgets/pet_hero_stage.dart';
import 'profile/widgets/pet_stats_sheet.dart';
import 'profile/widgets/pet_corner_actions.dart';
import 'profile/widgets/today_tasks_handmade_section.dart';
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
  static const double _maxAccuracyMeters = 35.0;
  static const double _minPointDistanceMeters = 2.0;
  static const double _maxReasonableJumpMeters = 120.0;
  static const double _maxWalkingSpeedMps = 3.2;
  static const double _vehicleSpeedMps = 7.0;
  static const Duration _minSampleInterval = Duration(seconds: 1);

  // 小豬預設對話語錄（用於任務打卡的短暫慶祝語結束後回到的預設狀態）
  // ★ 2026-09-15 溢位巡檢時發現：這句沿用自舊的 _pigQuotes，寫死了「阿公」。
  //   自主模式的長輩過去會預設叫「長輩朋友」、性別未知（第四十九輪已改為必須
  //   輸入真實稱呼，不再有這個預設值），但阿嬤看到小豬喊她阿公一樣會困惑
  //   ——與 memoir_service 先前修掉的是同一類問題，故仍保留中性稱呼。
  static const String _defaultSpeechText = '今天天氣真好，一起散步活動身體吧！🌿';

  // ── 數據 ───────────────────────────────────────────────
  final int dailyStepGoal = 8000;
  int currentSteps = 0; // Will be calculated from distance or fetched

  // ── GPS 追蹤（距離仍餵給小豬成長，見 _computeFusedSteps）──────────────
  bool _isTracking = false;
  final List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  final Distance _distance = const Distance();
  DateTime? _lastAcceptedTime;
  double _totalDistance = 0.0; // 公里
  StreamSubscription<StepCount>? _stepCountStream;
  int _hardwareBaseSteps = -1;
  int _sessionPedometerSteps = 0;
  double _estimatedStrideMeters = 0.72;
  bool _stepCounterUnavailable = false;
  _MovementState _movementState = _MovementState.stationary;
  CoordinateKalmanFilter? _latFilter;
  CoordinateKalmanFilter? _lngFilter;

  // ── 🐾 小豬之家狀態 ────────────────────────────────────────
  late AnimationController _particleController;
  late AnimationController _petBounceController;
  final List<PetHeartParticle> _petParticles = [];
  PetGrowthState? _petGrowthState;

  // 🧺 食匣抽屜開關與庫存（比照 pet_studio_screen.dart 的 _isFeedingSheetOpen
  // + Positioned.fill 做法——個人分頁本身就是小豬之家，不再跳轉到
  // PetStudioScreen，餵食流程要在這裡原地重現）。
  bool _isFeedingSheetOpen = false;
  final Map<String, int> _feedingInventory = {
    'carrot': -1, // 常駐無限
    'apple': 3,
    'cabbage': 2,
    'sweet_potato': 2,
    'corn': 1,
    'watermelon': 1,
    'peach_cake': 1,
  };

  // ★ 第四十一輪（item 3）：朋友圈好友 ID（見 PetCornerActions 內部另行解析，
  // 本欄位供 _loadElderReminders 讀排程提醒使用）。null 代表尚未載入完成或
  // 載入失敗。
  String? _myFriendElderId;

  // ── 📋 子女排程生活任務 ──────────────────────────────────
  List<Map<String, dynamic>> _reminders = [];
  Set<int> _completedReminderIds = {};
  bool _isLoadingReminders = false;
  // ★ 第四十九輪：見 _loadElderReminders 的 catch 區塊與
  // TodayTasksHandmadeSection.hasLoadError 的說明——讀取失敗不該跟「真的
  // 沒有安排提醒」顯示成同一張空狀態卡片。
  bool _hasReminderLoadError = false;

  // ── 🎨 小豬對話氣泡文字 ──────────────────────────────
  String _speechText = _defaultSpeechText;
  Timer? _speechBubbleTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(
        const AssetImage('assets/images/pet_stages/pig_stage_1.png'), context);
    precacheImage(
        const AssetImage('assets/images/pet_stages/pig_stage_2.png'), context);
    precacheImage(
        const AssetImage('assets/images/pet_stages/pig_stage_3.png'), context);
    precacheImage(
        const AssetImage('assets/images/pet_stages/pig_stage_4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pet_stages/pig_stage_5.png'), context);
    precacheImage(const AssetImage('assets/images/pig_mascot.png'), context);
  }

  Future<void> _loadPetGrowthState() async {
    final state =
        await PetStorageService.loadState(currentSensorSteps: currentSteps);
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
    }
  }

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..addListener(_updateParticles);

    _petBounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _autoStartTracking();
    _startStepTracking();
    _loadElderReminders();
    ElderReminderManager.instance.addListener(_onReminderManagerUpdate);
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
    _particleController.dispose();
    _petBounceController.dispose();
    _speechBubbleTimer?.cancel();
    _positionStream?.cancel();
    _stepCountStream?.cancel();
    super.dispose();
  }

  // ── 自動啟動追蹤與持久化初始化 ──────────────────────────────
  Future<void> _autoStartTracking() async {
    await _loadPersistedRoute();
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
      setState(() {
        _routePoints.clear();
        _totalDistance = 0.0;
        _sessionPedometerSteps = 0;
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
        _movementState = _MovementState.stationary;
      });
      _lastAcceptedTime = pos.timestamp;
      unawaited(_persistRoute());
      return;
    }

    final lastPoint = _routePoints.last;
    final distanceMeters = _distance(lastPoint, filteredPoint);
    if (distanceMeters < _minPointDistanceMeters) {
      _updateMovementState(pos.speed);
      setState(() {});
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
    });
    unawaited(_persistRoute());
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
        // ★ 第四十六輪（E3）：API 回空清單時，過去會塞入 3 筆假提醒
        // （id 101/102/103：服藥／溫開水／散步），讓真的沒設提醒的長輩
        // 看到可以「完成」的假任務，還會驅動小豬心情與「全數達標」徽章。
        // 現在誠實呈現空清單，空狀態文案交給 TodayTasksHandmadeSection
        // 既有的空狀態分支處理。
        setState(() {
          _reminders = List<Map<String, dynamic>>.from(list);
          _isLoadingReminders = false;
          _hasReminderLoadError = false;
        });
      }
    } catch (e) {
      // ★ 第四十九輪：讀取失敗與「真的沒有安排提醒」以前是同一種空清單畫面
      // （`_reminders` 維持空陣列），長輩會被誤導成「今天沒有藥要吃」。
      // 本函式有三個呼叫點（initState／_loadMyFriendElderId 完成後／
      // ElderReminderManager 通知監聽器，見上方 _onReminderManagerUpdate），
      // 後者會在約每 2 分鐘一次的後端排程同步成功時觸發，等同已經有自動
      // 重試機制，不需要像 elder_home_tab.dart 那樣額外排一次性重試計時器。
      if (mounted) {
        setState(() {
          _isLoadingReminders = false;
          _hasReminderLoadError = true;
        });
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
        _speechText = '太棒了！生活排程打卡成功，小豬好開心！🎉';
        _spawnHeartParticles();
        _petBounceController.forward(from: 0.0);
        _particleController.forward(from: 0.0);
        _speechBubbleTimer?.cancel();
        _speechBubbleTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _speechText = _defaultSpeechText;
            });
          }
        });
      }
    });

    await prefs.setStringList(
      'completed_tasks_$today',
      _completedReminderIds.map((e) => e.toString()).toList(),
    );

    // ★ 第四十六輪（E1）：比照 elder_home_tab.dart 的 _completeNextDose——
    // 本機立即更新給即時回饋，另外同步後端，家屬端才看得到長輩在「我的」
    // 分頁的打卡紀錄。只在「標記為完成」時同步，取消完成（isAlreadyDone
    // 為 true）不呼叫——後端沒有取消端點，這是既有限制，不在本次修復
    // 範圍內。⚠️ 已知後果：長輩取消打卡後，後端 activity_log 仍留著那筆
    // medication 紀錄不會被撤銷；只要有消費端是直接讀 activity_log（而非
    // 本機 completed_tasks_<date>）判斷「今天吃藥了沒」，就可能誤判成
    // 已完成。
    //
    // ★ 第四十九輪修復：原本用 unawaited 完全不管成不成功，網路失敗時
    // 畫面照樣顯示打卡完成（含小豬慶祝動畫），家屬端資料庫其實沒有這筆
    // 紀錄，是用藥安全問題。改成 await 讀 bool，失敗時要把上面 setState
    // 區塊在「標記為完成」分支寫入的三份樂觀更新狀態全部回退：記憶體中的
    // _completedReminderIds、SharedPreferences 的 completed_tasks_<today>、
    // 以及被提前導向慶祝文案的 _speechText（連同尚未觸發的
    // _speechBubbleTimer 一併取消)——否則小豬會在打卡其實失敗時仍開心地說
    // 「打卡成功」。粒子與彈跳動畫（_spawnHeartParticles／
    // _petBounceController／_particleController）屬於已播放的短暫視覺
    // 效果，等網路來回一趟通常早已播完，不追加回滾。
    // ApiService.completeElderReminder 內部已經把逾時／連線失敗／後端
    // 錯誤全部吞成 false、不會對外拋例外（見 reminder_api.dart），這裡的
    // try/catch 只是防禦未來改版又開始拋例外，不能取代讀 bool。
    if (!isAlreadyDone) {
      bool success;
      try {
        success = await ApiService.completeElderReminder(reminderId);
      } catch (e) {
        debugPrint('⚠️ [ElderProfileTab] completeElderReminder 例外: $e');
        success = false;
      }
      if (!mounted) return;
      if (!success) {
        _speechBubbleTimer?.cancel();
        setState(() {
          _completedReminderIds.remove(reminderId);
          _speechText = _defaultSpeechText;
        });
        await prefs.setStringList(
          'completed_tasks_$today',
          _completedReminderIds.map((e) => e.toString()).toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '打卡沒有送出成功，請確認網路後再按一次',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    }
  }

  // 小豬成長狀態尚未載入完成前的暫時預設值（與 PetStorageService.loadState
  // 的出廠預設一致），避免 PetHeroStage／PetStatsSheet 拿到 null。
  PetGrowthState get _effectiveGrowthState =>
      _petGrowthState ??
      PetGrowthState(
        weightGrams: 1250,
        vitality: 85,
        todaySteps: currentSteps,
        fedFoodIds: const {},
        lastDateStr: '',
        isCrownUnlocked: false,
      );

  // 🥕 開啟食匣抽屜——個人分頁本身就是小豬之家，不再跳轉到 PetStudioScreen。
  void _openFeedingSheet() {
    HapticFeedback.selectionClick();
    setState(() => _isFeedingSheetOpen = true);
  }

  // ── 核心餵食邏輯（逐一比照 pet_studio_screen.dart 的 _handleFeedFood）──
  void _handleFeedFood(PetFoodItem food) {
    final growthState = _effectiveGrowthState;
    final currentCount = _feedingInventory[food.id] ?? food.initialCount;
    if (!food.isUnlimited && currentCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('【${food.name}】已經吃完囉～多散步解鎖新食材吧！🌾')),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    final newFedFoods = Set<String>.from(growthState.fedFoodIds)..add(food.id);
    final newState = growthState.copyWith(
      fedFoodIds: newFedFoods,
      weightGrams: growthState.weightGrams + food.weightGainGrams,
      vitality: (growthState.vitality + food.vitalityGain).clamp(0, 100),
    );

    setState(() {
      _petGrowthState = newState;
      if (!food.isUnlimited && currentCount > 0) {
        _feedingInventory[food.id] = currentCount - 1;
      }
    });

    PetStorageService.saveState(newState);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('小豬大口吃下了【${food.name}】！活力 +${food.vitalityGain} ✨')),
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

  // 💡 長輩後悔藥：隨時重新觀看新手教學（暖色手作系統，全頁唯一抽出的
  // inline widget——標題／副標題皆為固定文案，非使用者可控字串，但仍加
  // maxLines/ellipsis 做防禦）。
  Widget _buildTutorialReplayCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.school_rounded,
              color: Color(0xFFB45309), size: 28),
        ),
        title: Text(
          '📖 重新觀看新手導覽',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF451A03),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '忘記功能怎麼用？點此重新開啟操作介紹',
          style: GoogleFonts.notoSansTc(
              fontSize: 14, color: const Color(0xFF8C6D58)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 18, color: Color(0xFFD4C5B9)),
        onTap: () async {
          await SpotlightTutorial.resetAllTutorials();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 已重新開啟教學！切換至首頁即可重新查看導覽。')),
            );
          }
        },
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
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width >= 720;
    final PetGrowthState growthState = _effectiveGrowthState;
    final String greetingLine = '$greetingTitle，${widget.userName}';

    // ★ 第四十六輪（F）：原本用 LayoutBuilder 包住，但從未讀取
    // constraints，改成單純的 if (isLandscape)——只建構真正要渲染的那一
    // 棵版面樹，另一棵完全不建構（避免每次 setState 都白白多組一份不會
    // 上樹的 widget）。
    final Widget body = isLandscape
        ? _buildLandscapeBody(growthState, greetingLine, context)
        : _buildPortraitBody(growthState, greetingLine, context);

    return Stack(
      children: [
        Container(
          color: const Color(0xFFFAF7F2), // 溫暖手作燕麥宣紙底色
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                top: isLandscape ? 6 : 0,
                bottom: isLandscape ? 104 : 110,
              ),
              child: body,
            ),
          ),
        ),

        // 🧺 半透明食匣抽屜（比照 pet_studio_screen.dart 的 _isFeedingSheetOpen
        // + Positioned.fill 做法）
        if (_isFeedingSheetOpen)
          Positioned.fill(
            child: GardenFeedingSheet(
              isLandscape: isLandscape,
              foodInventory: _feedingInventory,
              currentSteps: currentSteps,
              onFeedFood: _handleFeedFood,
              onClose: () => setState(() => _isFeedingSheetOpen = false),
            ),
          ),
      ],
    );
  }

  // ── 直屏模式：小豬之家（滿版主視覺，故意不加左右內距，其餘內容統一
  //    包在下方的 Padding 內）──
  Widget _buildPortraitBody(
    PetGrowthState growthState,
    String greetingLine,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 小豬之家主視覺舞台
        PetHeroStage(
          key: widget.petKey,
          growthState: growthState,
          speechText: _speechText,
          greetingLine: greetingLine,
          // 直向手機寬度有限，膠囊改精簡圖示橫排，把空間讓給問候語與對話氣泡
          topRightActions:
              PetCornerActions(userId: widget.userId, compact: true),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 2. 資訊卡：負偏移壓在主視覺下緣，比照 Pokémon GO 詳情頁
              Transform.translate(
                offset: const Offset(0, -24),
                child: PetStatsSheet(
                  growthState: growthState,
                  onFeedTap: _openFeedingSheet,
                ),
              ),

              // 3. 今日生活排程與用藥打卡手帳
              TodayTasksHandmadeSection(
                key: widget.tasksKey,
                reminders: _reminders,
                completedReminderIds: _completedReminderIds,
                isLoadingReminders: _isLoadingReminders,
                onToggleTask: _toggleTaskCompletion,
                hasLoadError: _hasReminderLoadError,
              ),

              const SizedBox(height: 16),

              // 4. 底部快捷操作列
              Row(
                children: [
                  Expanded(
                    child: ProfileActionCard(
                      key: widget.familyPairingKey,
                      icon: Icons.family_restroom_rounded,
                      title: '家人綁定',
                      subtitle: '出示配對碼',
                      color: const Color(0xFFF59E0B),
                      // ★ 第四十九輪修復：過去沒傳 explicitElderId，對話框內部
                      // 只能猜 SharedPreferences 的 caregiver_id/last_elder_id，
                      // 兩鍵都讀不到時會靜默送出缺 id 的配對碼請求，被後端當成
                      // 新長輩註冊、家屬綁到幽靈帳號（見
                      // family_pairing_dialog.dart 的 fetchCode 說明）。這裡是
                      // 呼叫端手上現成、保證非空的正確長輩 id，直接明確傳入。
                      onTap: () =>
                          showFamilyPairingDialog(context, widget.userId),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ProfileActionCard(
                      key: widget.aiAssistantKey,
                      icon: Icons.assistant_rounded,
                      title: '語音助理',
                      subtitle: 'Hey 嘎蛙',
                      color: const Color(0xFFF59E0B),
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

              const SizedBox(height: 16),

              // 5. 重新觀看新手導覽
              _buildTutorialReplayCard(context),
            ],
          ),
        ),
      ],
    );
  }

  // ── 橫屏模式（平板座充模式）：左欄小豬之家、右欄排程與快捷操作 ──
  Widget _buildLandscapeBody(
    PetGrowthState growthState,
    String greetingLine,
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 👈 左欄：小豬之家主視覺 ＆ 資訊卡（佔 50%）
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PetHeroStage(
                      key: widget.petKey,
                      growthState: growthState,
                      speechText: _speechText,
                      greetingLine: greetingLine,
                      topRightActions: PetCornerActions(userId: widget.userId),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -24),
                      child: PetStatsSheet(
                        growthState: growthState,
                        onFeedTap: _openFeedingSheet,
                        isLandscape: true,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // 👉 右欄：今日生活排程打卡手帳 ＆ 底部快捷操作列（佔 50%）
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
                      hasLoadError: _hasReminderLoadError,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.familyPairingKey,
                            icon: Icons.family_restroom_rounded,
                            title: '家人綁定',
                            subtitle: '出示配對碼',
                            color: const Color(0xFFF59E0B),
                            // ★ 第四十九輪修復：理由同直屏版本，見上方
                            // _buildPortraitBody 對應按鈕的註解。
                            onTap: () =>
                                showFamilyPairingDialog(context, widget.userId),
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.aiAssistantKey,
                            icon: Icons.assistant_rounded,
                            title: '語音助理',
                            subtitle: 'Hey 嘎蛙',
                            color: const Color(0xFFF59E0B),
                            onTap: () => showAiAssistantSettingsDialog(
                              context: context,
                              userId: widget.userId,
                              userName: widget.userName,
                            ),
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 8),
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

          const SizedBox(height: 8),

          // ★ 橫向版面原本漏掉「重新觀看新手導覽」，本輪補回
          _buildTutorialReplayCard(context),
        ],
      ),
    );
  }
}

enum _MovementState { stationary, walking, fastTransit }
