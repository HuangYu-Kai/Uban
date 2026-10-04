import 'package:flutter/material.dart';
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
import '../../services/friend_service.dart';
import '../../services/game_service.dart';
import '../../utils/error_handler.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import '../pet_companion_studio/models/pet_food_item.dart';
import '../pet_companion_studio/services/pet_leaderboard_service.dart';
import '../pet_companion_studio/services/pet_progress_service.dart';
import '../pet_companion_studio/widgets/garden_feeding_sheet.dart';

import 'elder_greeting_tab.dart';
import 'elder_layout.dart';
import 'profile/utils/coordinate_kalman_filter.dart';
import 'profile/widgets/pet_hero_stage.dart';
import 'profile/widgets/pet_stats_sheet.dart';
import 'profile/widgets/pet_corner_actions.dart';

/// 長輩端「小豬」分頁（v3 分頁重排新增）：上半是元氣小豬之家（原本在「我的」
/// 分頁最上方），下半嵌入每日祝福圖（[ElderGreetingTab] 的 embedded 模式）。
///
/// 本檔的 state／方法是從 `elder_profile_tab.dart` 原封不動搬過來的：小豬成長、
/// 餵食抽屜、胡蘿蔔帳本、食物解鎖、排行榜體重同步，以及餵給小豬成長的
/// 計步／本機 GPS 軌跡。任務清單、GPS 位置分享、家人綁定等仍留在「我的」。
class ElderPetTab extends StatefulWidget {
  final int userId;
  final String userName;

  /// 新手指引高光目標（掛在 PetHeroStage 上），由 ElderHomeScreen 持有。
  final GlobalKey? petKey;

  const ElderPetTab({
    super.key,
    required this.userId,
    required this.userName,
    this.petKey,
  });

  @override
  State<ElderPetTab> createState() => _ElderPetTabState();
}

class _ElderPetTabState extends State<ElderPetTab> {
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

  // ★ 第五十一輪：把融合步數（[_computeFusedSteps]）上傳到後端
  // `elder_daily_step`（見 [_maybeUploadStepDelta]）。過去這個畫面只算了
  // 步數給小豬本機成長用，從未送到後端，`today_steps` 在正式環境永遠是
  // null／0，導致「散步賺胡蘿蔔」這類依賴後端步數的功能永遠不會觸發。
  final GameService _gameService = GameService();
  int _lastUploadedSteps = 0;
  DateTime? _lastStepUploadAt;

  // ── 🐾 小豬之家狀態 ────────────────────────────────────────

  PetGrowthState? _petGrowthState;


  // 🧺 食匣抽屜開關與庫存（比照 pet_studio_screen.dart 的 _isFeedingSheetOpen
  // + Positioned.fill 做法——個人分頁本身就是小豬之家，不再跳轉到
  // PetStudioScreen，餵食流程要在這裡原地重現）。
  bool _isFeedingSheetOpen = false;
  // ⚠️ 第五十一輪修復：carrot 不再是常駐無限——使用者實機發現可以無限次
  // 投餵同一顆胡蘿蔔。這裡的 0 只是首幀渲染前的安全預設值，實際可餵份數
  // 由 build() 每次用 [_carrotAvailable]（賺得－已消耗，見該 getter 說明）
  // 覆蓋，不採用這個字面值。其餘食物維持舊制：解鎖後給固定份數，見
  // [_loadFeedingInventory] 的持久化讀取。
  final Map<String, int> _feedingInventory = {
    'carrot': 0,
    'apple': 3,
    'cabbage': 2,
    'sweet_potato': 2,
    'corn': 1,
    'watermelon': 1,
    'peach_cake': 1,
  };

  // 🥕 陽光脆胡蘿蔔今天已消耗幾份（`GET /api/pet/food-ledger/{elder_id}` 的
  // `consumed.carrot`）。null 代表尚未成功讀到後端帳本——[_carrotAvailable]
  // 此時保守回傳 0，寧可讓長輩暫時餵不到胡蘿蔔，也不能假設「今天消耗 0
  // 份」而把「今天已賺得」整包當成可餵份數（那等於後端帳本一連不上就退回
  // 原本的無限量老問題）。
  int? _carrotConsumedToday;

  // ★ 第四十一輪（item 3）：朋友圈好友 ID（見 PetCornerActions 內部另行解析，
  // 本欄位供 _loadElderReminders 讀排程提醒使用）。null 代表尚未載入完成或
  // 載入失敗。
  // ★ 第五十輪：同時也是好友寵物排行榜（PetLeaderboardService）與今日食物
  // 解鎖來源（PetProgressService.loadFoodUnlocks）要用的權威 elder_id，
  // 三者共用同一把鍵，理由同 _loadElderReminders 的既有註解——不可各自
  // 用 widget.userId 補零臆測。
  String? _myFriendElderId;

  // ★ 第五十輪：好友寵物排行榜「初次同步」只做一次，避免每次 setState／
  // rebuild 都重打一次後端。比照 pet_studio_screen.dart 的
  // _hasSyncedInitialWeight 做法。
  bool _hasSyncedInitialWeight = false;

  // ★ 第五十輪：今日食物解鎖來源（步數／服藥打卡次數，
  // `GET /api/pet/food-unlocks/{elder_id}`）。null 代表尚未載入成功，此時
  // 退回裝置端既有的步數來源、服藥打卡次數視為 0（等同「只靠步數解鎖」的
  // 舊行為，見下方 _effectiveStepsForUnlock／_medicationCheckinsToday）。
  PetFoodUnlockSource? _unlockSource;

  // ── 🎨 小豬對話氣泡文字（沿用「我的」分頁的預設語錄；本分頁沒有任務打卡，
  //   不會被改寫）──
  final String _speechText = _defaultSpeechText;

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
      // ★ 第五十輪：本機存檔載入完成是「進場初次同步」兩個先決條件之一
      // （另一個是 _myFriendElderId 解析完成，見 _loadMyFriendElderId），見
      // _maybeSyncInitialWeight 的說明。
      _maybeSyncInitialWeight();
    }
  }

  // ★ 第五十輪：讀取食物庫存持久化狀態（PetStorageService.loadFoodInventory），
  // 蓋掉 _feedingInventory 的出廠預設值——沒有持久化紀錄的食物 id（例如舊
  // 使用者第一次升級到本輪、或該食物從未被扣過庫存）維持出廠預設不變。
  // ⚠️ 第五十一輪：carrot 已改為「賺取制」，可餵份數改由後端食物帳本
  // （[_carrotConsumedToday]／[_carrotAvailable]）即時算出、每次 build()
  // 都會覆蓋，這份僅供其餘食物使用的 SharedPreferences 本機庫存快照不再是
  // carrot 的權威來源，跳過它、不採用裡面的舊值（沿用第五十輪就有的跳過
  // 邏輯，理由更新為新模型）。
  Future<void> _loadFeedingInventory() async {
    final saved = await PetStorageService.loadFoodInventory();
    if (!mounted || saved.isEmpty) return;
    setState(() {
      for (final entry in saved.entries) {
        if (entry.key == 'carrot') continue;
        if (_feedingInventory.containsKey(entry.key)) {
          _feedingInventory[entry.key] = entry.value;
        }
      }
    });
  }

  // ★ 第四十一輪（item 3）：讀取朋友圈好友 ID。權威來源是後端 elder_profile
  // 表（見 FriendService.resolveMyElderId 的說明），不可用 userId 補零臆測。
  Future<void> _loadMyFriendElderId() async {
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (mounted) {
      setState(() => _myFriendElderId = id);
      // ★ 第五十輪：elder_id 解析完成是「進場初次同步」另一個先決條件，見
      // _maybeSyncInitialWeight 的說明。同時順便刷新今日食物解鎖來源
      // （步數／服藥打卡次數），讓用藥打卡真的能換到食物解鎖（過去
      // medicationCheckinsToday 恆為 0，見 _refreshFoodUnlocks 說明）。
      _maybeSyncInitialWeight();
      _refreshFoodUnlocks();
      // ★ 第五十一輪：同時讀一次今日食物帳本，讓胡蘿蔔的「今天已消耗」
      // 份數在裝置重開後依然正確（見 _refreshCarrotLedger 說明）。
      _refreshCarrotLedger();
    }
  }

  /// 進入小豬之家時做一次初次體重同步，讓「從沒餵過食」的長輩也會出現在
  /// 好友排行榜——否則 `my_rank` 永遠是 null（見
  /// `pet_leaderboard_card.dart:223` 的空狀態文案「你的寵物體重還沒同步上榜」）。
  ///
  /// 比照 `pet_studio_screen.dart` 的 `_maybeSyncInitialWeight`：本機存檔
  /// （[_loadPetGrowthState]）與好友 elder_id 解析（[_loadMyFriendElderId]）
  /// 是兩個互相獨立的非同步流程，哪個先完成都在這裡因為另一項還沒就緒而
  /// 先行返回，等兩者都到齊時才由後完成的一方補上這一次同步——這樣才不會
  /// 用還沒套用本機存檔的預設體重（1250g）搶先上傳。
  ///
  /// 刻意只做背景同步、不彈訊息——被動進場同步失敗不像主動餵食（見
  /// [_handleFeedFood]）那樣需要長輩立刻注意，下次餵食或重新整理時會自然
  /// 再試一次，此處若也跳警示只會讓長輩一打開畫面就看到看不懂的錯誤提示。
  void _maybeSyncInitialWeight() {
    if (_hasSyncedInitialWeight ||
        _petGrowthState == null ||
        _myFriendElderId == null) {
      return;
    }
    _hasSyncedInitialWeight = true;
    unawaited(_syncWeightToLeaderboard(_petGrowthState!.weightGrams).then((ok) {
      if (!ok) {
        debugPrint('⚠️ [ElderProfileTab] 初次寵物體重同步到排行榜失敗，不影響既有寵物養成功能');
      }
    }));
  }

  /// 重新整理「今日食物解鎖來源」（步數／服藥打卡次數，
  /// `GET /api/pet/food-unlocks/{elder_id}`）。elder_id 還沒解析出來時直接
  /// 跳過——[_unlockSource] 維持 null，[_effectiveStepsForUnlock]／
  /// [_medicationCheckinsToday] 會自動退回裝置端步數與 0 次打卡，等同
  /// 「只靠步數解鎖」的既有行為，不影響既有的餵食流程。失敗只記 log
  /// （[PetProgressService] 內部已處理過），不彈錯誤對話框——這只是食匣裡
  /// 「今天達成了沒」的顯示資訊，不是餵食動作本身，失敗不需要打斷長輩。
  Future<void> _refreshFoodUnlocks() async {
    final eid = _myFriendElderId;
    if (eid == null) return;
    final source = await PetProgressService.loadFoodUnlocks(eid);
    if (mounted && source != null) {
      setState(() => _unlockSource = source);
    }
  }

  /// 今日步數——優先用後端答案（`elder_daily_step` 的即時資料），答不出來
  /// （null，代表後端查詢失敗或該表在目前環境不存在）時退回裝置端既有的
  /// 步數來源（[currentSteps]，GPS＋計步器融合值，見 [_computeFusedSteps]）。
  int get _effectiveStepsForUnlock => _unlockSource?.todaySteps ?? currentSteps;

  /// 今日服藥打卡次數；還沒有後端資料時視為 0（等同不提供打卡解鎖加成，
  /// 只靠步數，不影響既有行為）。
  int get _medicationCheckinsToday =>
      _unlockSource?.medicationCheckinsToday ?? 0;

  // 🥕 陽光脆胡蘿蔔「賺取制」相關換算（第五十一輪新增，見
  // `PetFoodItem.milestoneMenu` 中 carrot 的欄位說明）。

  PetFoodItem get _carrotFoodItem =>
      PetFoodItem.milestoneMenu.firstWhere((f) => f.id == 'carrot');

  /// 裝置本機日期字串（`yyyy-MM-dd`）。食物帳本的 `ledger_date` 一律用這個
  /// ——不可用伺服器時區推算，長輩若剛好在跨日前後操作，兩邊時區不一致會
  /// 誤判成前一天或後一天。
  String get _todayLedgerDate {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  /// 今天已賺得的胡蘿蔔份數（尚未扣掉已消耗）。純函式換算，不需要額外的
  /// 網路請求——直接沿用 [_effectiveStepsForUnlock]／[_medicationCheckinsToday]
  /// 這兩個既有欄位（它們本來就已經正確處理「後端答不出來」與「答案是 0」
  /// 的語意差異，見兩者各自的說明）。
  int get _carrotEarnedToday => _carrotFoodItem.earnedCountFor(
        steps: _effectiveStepsForUnlock,
        checkins: _medicationCheckinsToday,
      );

  /// 胡蘿蔔目前可投餵份數＝今天已賺得－今天已消耗。[_carrotConsumedToday]
  /// 還沒有成功讀到後端帳本時保守回傳 0——寧可讓長輩暫時餵不到胡蘿蔔，
  /// 也不能在資料不齊全時把「今天已賺得」整包當成可餵，那等於帳本一連
  /// 不上就退回原本「無限量」的老問題（誠實優先於樂觀）。
  int get _carrotAvailable {
    final consumed = _carrotConsumedToday;
    if (consumed == null) return 0;
    final earned = _carrotEarnedToday;
    return (earned - consumed).clamp(0, earned);
  }

  /// 重新整理「今日食物帳本」中胡蘿蔔已消耗的份數（`GET /api/pet/
  /// food-ledger/{elder_id}`）。elder_id 還沒解析出來時直接跳過——
  /// [_carrotConsumedToday] 維持 null，[_carrotAvailable] 會保守顯示成
  /// 不可餵，不影響其餘食物的既有餵食流程。失敗只記 log（見
  /// [PetProgressService.loadFoodLedger] 內部已處理過），不彈錯誤對話框。
  Future<void> _refreshCarrotLedger() async {
    final eid = _myFriendElderId;
    if (eid == null) return;
    final ledger =
        await PetProgressService.loadFoodLedger(eid, _todayLedgerDate);
    if (mounted && ledger != null) {
      setState(() => _carrotConsumedToday = ledger.consumedOf('carrot'));
    }
  }

  /// 把目前體重同步到後端好友排行榜（`POST /api/pet/state`）。
  ///
  /// 比照 `pet_studio_screen.dart::_syncWeightToLeaderboard`：
  /// `PetLeaderboardService.uploadMyState` 內部已經 try/catch 過一層，這裡
  /// 再包一層防禦性 try/catch 只是避免未來改版又開始拋例外，回傳
  /// bool 讓呼叫端（[_handleFeedFood] 主動餵食／[_maybeSyncInitialWeight]
  /// 被動進場）各自決定要不要提示使用者。
  Future<bool> _syncWeightToLeaderboard(int weightGrams) async {
    final eid = _myFriendElderId;
    if (eid == null) return false;
    try {
      return await PetLeaderboardService.uploadMyState(
        elderId: eid,
        weightGrams: weightGrams,
      );
    } catch (e) {
      debugPrint('⚠️ [ElderProfileTab] 寵物體重同步到排行榜例外: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();

    _autoStartTracking();
    _startStepTracking();
    _loadPetGrowthState();
    _loadFeedingInventory();
    _loadMyFriendElderId();
  }

  @override
  void dispose() {
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
          unawaited(_maybeUploadStepDelta());
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

  /// 把步數增量上傳到後端 `elder_daily_step`（`POST /api/game/elder/
  /// update_steps`，見 [GameService.updateSteps]）。這是「散步賺胡蘿蔔」
  /// （`PetFoodItem.milestoneMenu` 的 carrot／`PetProgressService
  /// .loadFoodUnlocks` 的 `today_steps`）能生效的前提——沒有這一步，
  /// `elder_daily_step` 永遠不會被寫入，後端的 `today_steps` 永遠是 null。
  ///
  /// 節流：累積增量達 100 步，或距離上次上傳超過 5 分鐘，兩者滿足其一才
  /// 送出，避免計步器／GPS 每次微小變動都打一次後端。失敗只記 log、不拋
  /// 例外、不影響裝置端步數顯示——比照 [_syncWeightToLeaderboard] 既有的
  /// 錯誤處理慣例（本機顯示永遠優先，離線也要能正常用）。失敗時刻意不把
  /// [_lastUploadedSteps] 復原——寧可少送一次增量（下次融合步數繼續累積，
  /// delta 會自然變大再補送），也不要在連線持續不穩時對同一段增量重送到
  /// 後端造成重複計算風險。
  Future<void> _maybeUploadStepDelta() async {
    final eid = _myFriendElderId;
    if (eid == null) return;

    final int fused = _computeFusedSteps();
    final int delta = fused - _lastUploadedSteps;
    if (delta <= 0) return;

    final now = DateTime.now();
    final bool deltaBigEnough = delta >= 100;
    final bool timeElapsed = _lastStepUploadAt == null ||
        now.difference(_lastStepUploadAt!) >= const Duration(minutes: 5);
    if (!deltaBigEnough && !timeElapsed) return;

    _lastUploadedSteps = fused;
    _lastStepUploadAt = now;

    try {
      await _gameService.updateSteps(eid, delta);
    } catch (e) {
      debugPrint('⚠️ [ElderProfileTab] 步數上傳失敗，不影響裝置端步數顯示: $e');
    }
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
    unawaited(_maybeUploadStepDelta());
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
    // ★ 第五十輪：開抽屜前順便刷新一次今日食物解鎖來源，避免長輩剛完成
    // 用藥打卡／散步達標，食匣卻還顯示舊資料的「鎖定」狀態。失敗不影響開
    // 抽屜本身（見 _refreshFoodUnlocks 的說明）。
    unawaited(_refreshFoodUnlocks());
    // ★ 第五十一輪：同理，開抽屜前順便重讀一次胡蘿蔔的今日食物帳本。
    unawaited(_refreshCarrotLedger());
    setState(() => _isFeedingSheetOpen = true);
  }

  // ── 核心餵食邏輯（逐一比照 pet_studio_screen.dart 的 _handleFeedFood）──
  //
  // ★ 第五十輪修復：過去本函式只更新本機 state＋PetStorageService.saveState，
  // 全檔沒有任何 PetLeaderboardService 呼叫——長輩因此從不存在於後端
  // elder_pet_state 表，好友排行榜的 my_rank 永遠是 null（見
  // pet_leaderboard_card.dart:223 的空狀態文案）。現在餵食後會額外：
  // ① 把新體重同步到後端排行榜；② 把新庫存持久化（見 PetStorageService.
  // saveFoodInventory，任務 C），讓「食物有限」在重開 App 後依然有限。
  //
  // ⚠️ 誠實性鐵律：本機餵食（體重／活力／已餵食物集合）一律照常成功並
  // 立即套用——小豬「已經把食物吃下去」是真實發生、不需要網路確認的本機
  // 事實，不能因為後端同步失敗就整個回滾（那樣反而是另一種造假：長輩明明
  // 看到小豬吃了東西，畫面卻假裝沒發生過）。但**顯示的訊息**必須誠實反映
  // 後端同步的實際結果：同步成功才顯示「餵食成功」，同步失敗要換成可重試
  // 的提示文案，不可以讓長輩以為排行榜已經更新。
  Future<void> _handleFeedFood(PetFoodItem food) async {
    final growthState = _effectiveGrowthState;
    final bool isCarrot = food.id == 'carrot';
    final currentCount = _feedingInventory[food.id] ?? food.initialCount;
    if (!food.isUnlimited && currentCount <= 0) {
      if (!mounted) return;
      ErrorHandler.showWarning(
        context,
        '【${food.name}】已經吃完囉～多散步解鎖新食材吧！🌾',
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
      if (isCarrot) {
        // 賺取制食物：本機樂觀先把「今天已消耗」+1，讓食匣立刻反映最新
        // 可餵份數（_carrotAvailable 會在下次 build() 重新算出），實際是
        // 否記帳成功交給下面的 POST 決定；失敗時整份重讀帳本校正，不用
        // 「減 1」去猜後端真實狀態（見下方 recordFoodConsumption 失敗分支）。
        _carrotConsumedToday = (_carrotConsumedToday ?? 0) + 1;
      } else if (!food.isUnlimited && currentCount > 0) {
        _feedingInventory[food.id] = currentCount - 1;
      }
    });

    await PetStorageService.saveState(newState);
    // 任務 C：食物庫存持久化，不 await——庫存寫檔慢不應該拖慢餵食後的
    // 排行榜同步與訊息顯示，且與體重存檔（上面那行）一樣屬於「盡力而為」
    // 的本機寫入，SharedPreferences 幾乎不會失敗。
    unawaited(PetStorageService.saveFoodInventory(_feedingInventory));

    if (isCarrot) {
      final eid = _myFriendElderId;
      final bool ledgerOk = eid != null &&
          await PetProgressService.recordFoodConsumption(
            elderId: eid,
            ledgerDate: _todayLedgerDate,
            foodId: 'carrot',
          );
      if (!ledgerOk) {
        // 後端帳本沒記到這一份，本機樂觀 +1 的消耗數不可信任，整份重讀一次
        // 帳本校正（讀不到就退回 null，_carrotAvailable 會保守顯示成暫時
        // 不可餵）——見 _carrotConsumedToday／_carrotAvailable 欄位說明，
        // 不能自己用「減 1」去猜後端真實狀態（中間可能還有其他裝置也在
        // 同步寫入）。
        unawaited(_refreshCarrotLedger());
      }
    }

    final bool synced = await _syncWeightToLeaderboard(newState.weightGrams);
    if (!mounted) return;

    if (synced) {
      ErrorHandler.showSuccess(
        context,
        '小豬大口吃下了【${food.name}】！活力 +${food.vitalityGain} ✨',
      );
    } else {
      // 誠實性鐵律：本機餵食已經生效（上面 setState／saveState 都已完成），
      // 但排行榜同步失敗，不可以顯示「餵食成功」誤導長輩以為排行榜也更新
      // 了。下次餵食會自然重新呼叫本函式再試一次同步，不需要額外的重試
      // 按鈕。
      ErrorHandler.showWarning(
        context,
        '小豬已經吃下【${food.name}】，但體重排行榜同步失敗，下次餵食會自動重試',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    currentSteps = _computeFusedSteps();
    // ★ 第五十一輪：胡蘿蔔可餵份數每次 build() 都用「今天已賺得－今天已
    // 消耗」重新覆蓋（見 _carrotAvailable 說明），不再是一個寫死或只在餵食
    // 時才更新的數字——這樣步數／打卡剛好在畫面開著時達標，食匣也會立刻
    // 反映最新可餵份數，不需要額外監聽。
    _feedingInventory['carrot'] = _carrotAvailable;
    final hour = DateTime.now().hour;
    String greetingTitle = '早安';
    if (hour >= 12 && hour < 18) greetingTitle = '午安';
    if (hour >= 18 || hour < 5) greetingTitle = '晚安';
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width >= 720;
    final PetGrowthState growthState = _effectiveGrowthState;
    final String greetingLine = '$greetingTitle，${widget.userName}';

    final Widget petBody = isLandscape
        ? _buildLandscapePet(growthState, greetingLine)
        : _buildPortraitPet(growthState, greetingLine);

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
                bottom: elderNavClearance(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  petBody,
                  // 下半：每日祝福圖（原封不動的 ElderGreetingTab，嵌入模式）
                  ElderGreetingTab(
                    userId: widget.userId,
                    userName: widget.userName,
                    embedded: true,
                  ),
                ],
              ),
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
              // ★ 第五十輪修復：過去這裡永遠傳裝置端 currentSteps，
              // medicationCheckinsToday 恆為預設值 0——用藥打卡換食物解鎖
              // 在正式畫面從未生效。改用 _effectiveStepsForUnlock／
              // _medicationCheckinsToday，優先採後端 GET /api/pet/
              // food-unlocks/{elder_id} 的答案，答不出來才退回裝置端步數
              // 與 0 次打卡（見兩個 getter 的說明）。
              currentSteps: _effectiveStepsForUnlock,
              medicationCheckinsToday: _medicationCheckinsToday,
              onFeedFood: _handleFeedFood,
              onClose: () => setState(() => _isFeedingSheetOpen = false),
            ),
          ),
      ],
    );
  }

  // ── 直屏：小豬之家主視覺 + 資訊卡 ──
  Widget _buildPortraitPet(PetGrowthState growthState, String greetingLine) {
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
          // ★ 第五十輪修復：拖曳餵食與食匣按鈕餵食走同一條路徑，見
          // PetHeroStage.onFoodAccepted 欄位說明。
          onFoodAccepted: _handleFeedFood,
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
            ],
          ),
        ),
      ],
    );
  }

  // ── 橫屏（平板座充）：小豬之家置中、限寬 ──
  Widget _buildLandscapePet(PetGrowthState growthState, String greetingLine) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                    PetHeroStage(
                      key: widget.petKey,
                      growthState: growthState,
                      speechText: _speechText,
                      greetingLine: greetingLine,
                      topRightActions: PetCornerActions(userId: widget.userId),
                      // ★ 第五十輪修復：理由同直屏版本，見上方
                      // _buildPortraitBody 對應的 PetHeroStage 註解。
                      onFoodAccepted: _handleFeedFood,
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
      ),
    );
  }
}

enum _MovementState { stationary, walking, fastTransit }
