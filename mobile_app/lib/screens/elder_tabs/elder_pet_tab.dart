import 'package:flutter/material.dart';
import '../../utils/step_upload_delta.dart';
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
import '../../services/elder_reminder_manager.dart';
import '../../services/friend_service.dart';
import '../../services/game_service.dart';
import '../../services/weather_service.dart';
import '../../utils/error_handler.dart';
import '../../widgets/ui/ui.dart';
import '../pet_companion_studio/models/pet_growth_state.dart';
import '../pet_companion_studio/models/pet_food_item.dart';
import '../pet_companion_studio/services/pet_progress_service.dart';
import '../pet_companion_studio/services/pet_weight_sync.dart';
import '../pet_companion_studio/widgets/pet_evolution_dialog.dart';
import '../pet_companion_studio/widgets/pet_leaderboard_card.dart';

import 'elder_greeting_tab.dart';
import 'elder_layout.dart';
import 'pet/pet_breed_store.dart';
import 'pet/pet_buddy_stage.dart';
import 'pet/pet_gift_banner.dart';
import 'pet/pet_step_challenge_bar.dart';
import '../../services/api/step_challenge_api.dart';
import '../../services/api/elder_pet_gift_api.dart';
import 'pet/pet_ear_anchors.dart';
import 'pet/pet_scene.dart';
import 'pet/pet_season_chip.dart';
import 'pet/pet_stat_card.dart';
import 'profile/utils/coordinate_kalman_filter.dart';
import 'profile/widgets/pet_corner_actions.dart';
import 'streak/streak_service.dart';

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

  /// 新手指引高光目標（掛在每日吉祥祝賀圖的預覽卡片上）。
  final GlobalKey? greetingKey;

  const ElderPetTab({
    super.key,
    required this.userId,
    required this.userName,
    this.petKey,
    this.greetingKey,
  });

  @override
  State<ElderPetTab> createState() => _ElderPetTabState();
}

class _ElderPetTabState extends State<ElderPetTab>
    with WidgetsBindingObserver {
  static const double _maxAccuracyMeters = 35.0;
  static const double _minPointDistanceMeters = 2.0;
  static const double _maxReasonableJumpMeters = 120.0;
  static const double _maxWalkingSpeedMps = 3.2;
  static const double _vehicleSpeedMps = 7.0;
  static const Duration _minSampleInterval = Duration(seconds: 1);

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


  // 🧺 其他食物的庫存（資料／解鎖邏輯保留；本分頁改版後只剩胡蘿蔔入口，
  // 食匣抽屜 GardenFeedingSheet 不再開啟）。
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

  // ── 🎨 舞台（寶可夢 GO 夥伴舞台）狀態 ─────────────────────
  // 品種（粉紅豬／黑豬）由後端指派；PetBreedStore 只當離線快取（先讀它，後端回應後覆寫）。
  PetBreed _breed = PetBreed.pink;
  // 天氣三級，只用既有 WeatherService.getWeather（含快取），不新增 API。
  PetWeather _weather = PetWeather.sunny;
  // 餵食／同步後遞增，觸發排行榜重新讀取（PetLeaderboardCard.refreshTick）。
  int _leaderboardTick = 0;
  // 餵食前的階段：餵食動畫播完後與新階段比較，升階才呼叫 PetEvolutionDialog。
  PetGrowthStage? _stageBeforeFeed;
  bool _wasVisible = false;
  bool _refreshing = false;

  /// 重新同步：食物解鎖來源、胡蘿蔔帳本、小豬成長狀態、排行榜。進行中不重複發。
  /// 三種觸發共用：下拉刷新、切回本分頁（TickerMode 由不可見→可見，不節流）、
  /// App 回前景（僅本分頁可見時）。
  // 祝賀圖（嵌在本分頁下半部）監聽此值，變動時重讀小豬品種／階段。
  final ValueNotifier<int> _greetingPigSignal = ValueNotifier<int>(0);

  Future<void> _refreshAll() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      await Future.wait([
        _refreshFoodUnlocks(),
        _refreshCarrotLedger(),
        _loadPetGrowthState(),
      ]);
      // 本機存檔載入後再與伺服器體重對帳（換機／重裝時採用伺服器值，
      // 本機較重則推上去；見 PetWeightSync）。
      await _reconcileWeight();
      if (mounted) setState(() => _leaderboardTick++);
      // 通知嵌在下方的祝賀圖重讀小豬品種／階段
      _greetingPigSignal.value++;
      // ★ 2026-10-07 小豬共養：下拉／回前景一併重讀家人送的點心。
      ElderPetGiftApi.refreshSignal.value++;
      // ★ 2026-10-07 家庭步數挑戰：一併重讀「全家一起走」進度。
      await _refreshStepChallenge();
    } finally {
      _refreshing = false;
    }
  }

  /// ★ 2026-10-07 家庭步數挑戰：讀進度；解析不到 elder_id 時不動（長輩端失敗即隱藏）。
  Future<void> _refreshStepChallenge() async {
    final eid = _myFriendElderId;
    if (eid == null || eid.isEmpty || !mounted) return;
    await StepChallengeApi.refreshElder(eid);
  }

  void _onStepChallengeSignal() {
    if (mounted) unawaited(_refreshStepChallenge());
  }

  /// 打卡後（提醒同步／連勝變動）立刻更新胡蘿蔔數，不必切分頁。
  void _onCheckinChanged() {
    if (!mounted) return;
    unawaited(_refreshFoodUnlocks());
    unawaited(_refreshCarrotLedger());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wasVisible) {
      unawaited(_refreshAll());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 小豬分頁由不可見變可見（IndexedStack 以 TickerMode 開關）時重新同步，
    // 否則在別的分頁打卡後這裡仍是舊的數字。
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_wasVisible) {
      unawaited(_refreshAll());
    }
    _wasVisible = visible;
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
      unawaited(_refreshStepChallenge());
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

  /// 進入小豬之家時做一次初次體重對帳。
  ///
  /// 本機存檔（[_loadPetGrowthState]）與好友 elder_id 解析（[_loadMyFriendElderId]）
  /// 是兩個互相獨立的非同步流程，哪個先完成都在這裡因為另一項還沒就緒而先行
  /// 返回，等兩者都到齊時才由後完成的一方補上這一次對帳。
  ///
  /// ★ 不再盲目上傳本機預設體重（1250g）：先讀伺服器體重再決定——伺服器較重
  /// 就採用（換機／重裝不會歸零）、本機較重或伺服器沒資料才推上去（見
  /// [_reconcileWeight]）。刻意只做背景同步、不彈訊息，失敗保留本機值，
  /// 下次重新整理或餵食會自然再試。
  void _maybeSyncInitialWeight() {
    if (_hasSyncedInitialWeight ||
        _petGrowthState == null ||
        _myFriendElderId == null) {
      return;
    }
    _hasSyncedInitialWeight = true;
    unawaited(_reconcileWeight().then((_) {
      if (mounted) setState(() => _leaderboardTick++);
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

  // 餵食請求進行中的數量。>0 時不做體重對帳的採用／推送，避免「本機樂觀值
  // 被 POST /pet/state 推上去之後，餵食增量又在伺服器加一次」的重複計算。
  int _feedsInFlight = 0;
  bool _reconcilingWeight = false;

  /// 與伺服器對帳體重（GET /pet/state/{id}）：伺服器較重→採用並存檔；
  /// 本機較重或伺服器沒資料→推上去（後端只增不減）；失敗→保留本機。
  /// 不拋例外、不跳訊息。
  Future<void> _reconcileWeight() async {
    final eid = _myFriendElderId;
    if (eid == null || _petGrowthState == null || _reconcilingWeight) return;
    _reconcilingWeight = true;
    try {
      final r = await PetWeightSync.reconcile(
        elderId: eid,
        readLocal: () => _effectiveGrowthState.weightGrams,
        canWrite: () => mounted && _feedsInFlight == 0,
      );
      if (!r.ok) {
        debugPrint('⚠️ [ElderProfileTab] 寵物體重與伺服器對帳失敗，保留本機體重');
      }
      _applyServerBreed(r.breed);
      final adopted = r.adoptedWeight;
      if (adopted != null) _adoptServerWeight(adopted, force: r.forceAdopt);
    } catch (e) {
      debugPrint('⚠️ [ElderProfileTab] 寵物體重對帳例外: $e');
    } finally {
      _reconcilingWeight = false;
    }
  }

  /// 採用伺服器體重（預設只在比目前本機大時採用，本機領先不倒退；賽季更新
  /// [force]＝true 時無條件採用，讓賽季重置不被本機較重的舊體重蓋回去）並寫回存檔。
  /// 不觸發進化對話框：進化畫面只由「餵食動畫結束」比較餵食前後階段時顯示
  /// （[_stageBeforeFeed]），換機還原體重不是餵食，不應彈出慶祝。
  void _adoptServerWeight(int serverWeight, {bool force = false}) {
    if (!mounted) return;
    final cur = _effectiveGrowthState;
    final merged = force
        ? serverWeight
        : mergeFedWeight(local: cur.weightGrams, server: serverWeight);
    if (merged == cur.weightGrams) return;
    final next = cur.copyWith(weightGrams: merged);
    setState(() => _petGrowthState = next);
    unawaited(PetStorageService.saveState(next));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ElderReminderManager.instance.addListener(_onCheckinChanged);
    StreakService.changes.addListener(_onCheckinChanged);
    StepChallengeApi.refreshSignal.addListener(_onStepChallengeSignal);

    _autoStartTracking();
    _startStepTracking();
    _loadPetGrowthState();
    _loadFeedingInventory();
    _loadMyFriendElderId();
    _loadBreed();
    _loadWeather();
  }

  /// 套用後端指派的品種並寫回離線快取（伺服器為權威）。
  /// null（舊版後端／請求失敗）→ 沿用現有顯示；未知 key → [PetBreed.fromId] 退回粉紅豬。
  /// 品種改變只換 sprite，不彈任何對話框。
  void _applyServerBreed(String? id) {
    if (id == null) return;
    final b = PetBreed.fromId(id);
    unawaited(PetBreedStore.save(b));
    if (mounted && b != _breed) setState(() => _breed = b);
  }

  Future<void> _loadBreed() async {
    final b = await PetBreedStore.load();
    if (mounted && b != _breed) setState(() => _breed = b);
  }

  Future<void> _loadWeather() async {
    final info = await WeatherService.getWeather(widget.userId);
    if (!mounted || info == null) return;
    setState(() {
      _weather = PetWeather.fromRainProbability(info.rainProbability);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ElderReminderManager.instance.removeListener(_onCheckinChanged);
    StreakService.changes.removeListener(_onCheckinChanged);
    StepChallengeApi.refreshSignal.removeListener(_onStepChallengeSignal);
    _positionStream?.cancel();
    _stepCountStream?.cancel();
    _greetingPigSignal.dispose();
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
      // ★ 2026-10-07 交接 C/D（長輩端）D1：跨日歸零「已上傳步數」。
      await prefs.setInt(kLastUploadedStepsKey, 0);
      await prefs.setString(kLastUploadedStepsDateKey, today);
      _lastUploadedSteps = 0;
      setState(() {
        _routePoints.clear();
        _totalDistance = 0.0;
        _sessionPedometerSteps = 0;
      });
      return;
    }

    // ★ 2026-10-07 交接 C/D（長輩端）D1：還原今日已上傳步數，重開 App 不重送整天步數。
    _lastUploadedSteps = restoreUploadedSteps(
      storedSteps: prefs.getInt(kLastUploadedStepsKey),
      storedDate: prefs.getString(kLastUploadedStepsDateKey),
      today: today,
    );

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
    final int delta =
        stepUploadDelta(fusedSteps: fused, lastUploaded: _lastUploadedSteps);
    if (delta <= 0) return;

    final now = DateTime.now();
    final bool deltaBigEnough = delta >= 100;
    final bool timeElapsed = _lastStepUploadAt == null ||
        now.difference(_lastStepUploadAt!) >= const Duration(minutes: 5);
    if (!deltaBigEnough && !timeElapsed) return;

    _lastUploadedSteps = fused;
    _lastStepUploadAt = now;
    // ★ 2026-10-07 交接 C/D（長輩端）D1：持久化（含日期），失敗不影響上傳。
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kLastUploadedStepsKey, fused);
      await prefs.setString(kLastUploadedStepsDateKey,
          now.toIso8601String().substring(0, 10));
    } catch (_) {}

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

  // ★ 2026-10-07 小豬共養：餵家人送的點心中（防連點）。
  bool _giftFeeding = false;

  /// 點橫幅「餵牠吃」：禮物本身就是庫存，不看每日上限／本機庫存；
  /// 餵食流程共用 [_handleFeedFood]（[gift] 非 null 時走禮物分支）。
  Future<void> _feedGift(PetGift gift) async {
    if (_giftFeeding || _feedsInFlight > 0) return;
    PetFoodItem? food;
    for (final f in PetFoodItem.milestoneMenu) {
      if (f.id == gift.foodId) food = f;
    }
    if (food == null) {
      ErrorHandler.showWarning(context, '這份點心小豬還不認識，請稍後再試');
      return;
    }
    setState(() => _giftFeeding = true);
    try {
      final stageBefore = _effectiveGrowthState.stage;
      final ok = await _handleFeedFood(food, gift: gift);
      if (ok && mounted) {
        final now = _effectiveGrowthState.stage;
        if (now.index > stageBefore.index) {
          PetEvolutionDialog.show(context, now,
              oldStage: stageBefore,
              breedId: _breed.id,
              userName: widget.userName);
        }
      }
    } finally {
      if (mounted) setState(() => _giftFeeding = false);
    }
  }

  /// 回傳是否真的餵出去（庫存不足／禮物記帳失敗為 false）。
  Future<bool> _handleFeedFood(PetFoodItem food, {PetGift? gift}) async {
    final growthState = _effectiveGrowthState;
    final bool isGift = gift != null;
    final bool isCarrot = food.id == 'carrot' && !isGift;
    final currentCount = _feedingInventory[food.id] ?? food.initialCount;
    if (!isGift && !food.isUnlimited && currentCount <= 0) {
      if (!mounted) return false;
      ErrorHandler.showWarning(
        context,
        '【${food.name}】已經吃完囉～多散步解鎖新食材吧！🌾',
      );
      return false;
    }

    // ★ 禮物：先向後端記一筆消耗（後端據此標記最舊的未餵禮物並通知送禮家人）；
    //   記帳失敗就不餵，避免小豬吃了但禮物永遠未餵。
    if (isGift) {
      final eid = _myFriendElderId;
      final ok = eid != null &&
          await PetProgressService.recordFoodConsumption(
            elderId: eid,
            ledgerDate: _todayLedgerDate,
            foodId: food.id,
          );
      if (!mounted) return false;
      if (!ok) {
        ErrorHandler.showWarning(context, '目前連不上伺服器，請稍後再餵一次');
        return false;
      }
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
      } else if (!isGift && !food.isUnlimited && currentCount > 0) {
        _feedingInventory[food.id] = currentCount - 1;
      }
    });

    await PetStorageService.saveState(newState);
    // 任務 C：食物庫存持久化，不 await——庫存寫檔慢不應該拖慢餵食後的
    // 排行榜同步與訊息顯示，且與體重存檔（上面那行）一樣屬於「盡力而為」
    // 的本機寫入，SharedPreferences 幾乎不會失敗。
    if (!isGift) {
      unawaited(PetStorageService.saveFoodInventory(_feedingInventory));
    }

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

    // ★ 2026-10-07 小豬共養：後端在 food-ledger 記帳時會把該食物最舊的未餵禮物
    //   標為已餵並通知送禮家人；這裡只通知首頁重讀橫幅／小紅點（不動食物經濟）。
    ElderPetGiftApi.refreshSignal.value++;

    // 餵食改送「增量」到伺服器（伺服器原子累加、client_event_id 冪等），並採用
    // 回傳的伺服器體重（只在較大時採用，避免本機因離線餵食領先時倒退）。
    // 採用不影響進化判斷：[_onFeedAnimationDone] 只比較餵食前階段與當下階段。
    final eid = _myFriendElderId;
    bool synced = false;
    if (eid != null) {
      _feedsInFlight++;
      try {
        final r = await PetWeightSync.feed(
          elderId: eid,
          gramsDelta: food.weightGainGrams,
        );
        synced = r.ok;
        // 餵食回應也帶品種（換季／管理員覆寫時直接換圖，不彈對話框）。
        _applyServerBreed(r.breed);
        final sw = r.serverWeight;
        if (r.ok && sw != null) {
          _adoptServerWeight(sw, force: r.seasonReset);
        }
      } finally {
        _feedsInFlight--;
      }
    }
    if (!mounted) return true;

    // 排行榜卡依 refreshTick 重新讀取（上傳是非同步的，所以放在同步完成之後）。
    setState(() => _leaderboardTick++);

    if (isGift) {
      // 禮物已記帳成功；體重同步失敗只影響排行榜，下次餵食會補。
      ErrorHandler.showSuccess(
          context, '小豬吃了${gift.familyName}送的${gift.foodName}，好開心！');
    } else if (synced) {
      // 設計稿規定畫面上不顯示任何「+N」數值，只說小豬吃得開心。
      ErrorHandler.showSuccess(
        context,
        '小豬吃得好開心！🥕',
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
    return true;
  }

  /// 胡蘿蔔數為 0 時點按鈕：先重讀解鎖來源與帳本，回傳最新可餵份數。
  /// 把 `_feedingInventory['carrot']` 同步更新，`_handleFeedFood` 才讀得到新值。
  Future<int> _refreshCarrotForTap() async {
    await Future.wait([_refreshFoodUnlocks(), _refreshCarrotLedger()]);
    final n = _carrotAvailable;
    _feedingInventory['carrot'] = n;
    return n;
  }

  /// 舞台上的胡蘿蔔要餵了：資料一律走既有 [_handleFeedFood]（胡蘿蔔帳本、
  /// 體重、排行榜同步全在裡面）。[_handleFeedFood] 在第一個 await 之前就會
  /// 同步更新 [_petGrowthState]，所以呼叫後比較新舊體重即可知道有沒有成功
  /// （庫存 0 時它直接警告返回、體重不變 → 回傳 false，舞台不播動畫）。
  bool _requestCarrotFeed() {
    final before = _effectiveGrowthState;
    unawaited(_handleFeedFood(_carrotFoodItem));
    final grew = _effectiveGrowthState.weightGrams > before.weightGrams;
    if (grew) _stageBeforeFeed = before.stage;
    return grew;
  }

  /// 餵食動畫（含愛心、跳躍）播完：階段升高才顯示進化畫面（只顯示、不寫入）。
  void _onFeedAnimationDone() {
    final before = _stageBeforeFeed;
    _stageBeforeFeed = null;
    if (!mounted || before == null) return;
    final now = _effectiveGrowthState.stage;
    if (now.index > before.index) {
      PetEvolutionDialog.show(
        context,
        now,
        oldStage: before,
        breedId: _breed.id,
        userName: widget.userName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    currentSteps = _computeFusedSteps();
    _feedingInventory['carrot'] = _carrotAvailable;
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width >= 720;
    final PetGrowthState growthState = _effectiveGrowthState;

    final Widget petBody = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 560 : 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ★ 2026-10-07 小豬共養：家人送的未餵點心橫幅（沒有時不佔位）。
              PetGiftBanner(onFeed: _feedGift),
              PetBuddyStage(
                key: widget.petKey,
                stage: growthState.stage.index + 1,
                breed: _breed,
                weather: _weather,
                carrotCount: _carrotAvailable,
                onFeedRequest: _requestCarrotFeed,
                onFeedDone: _onFeedAnimationDone,
                onRefreshCarrot: _refreshCarrotForTap,
                onEmptyCarrot: () =>
                    ErrorHandler.showWarning(context, '打卡就能賺胡蘿蔔 🥕'),
                onHint: (m) => ErrorHandler.showWarning(context, m),
                cornerAction:
                    PetCornerActions(userId: widget.userId, musicOnly: true),
              ),
              // ★ 2026-10-07 家庭步數挑戰：精簡「全家一起走」進度條（失敗時整塊隱藏）。
              const PetStepChallengeBar(),
              const SizedBox(height: 14),
              PetStatCard(growth: growthState),
              const SizedBox(height: 14),
              UbanCard(
                child: PetLeaderboardCard(
                  boardStyle: true,
                  myElderId: _myFriendElderId,
                  refreshTick: _leaderboardTick,
                  headerTrailing: const PetSeasonChip(),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );

    return Container(
      color: UbanColors.of(context).bg,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: UbanColors.of(context).brandFill,
          backgroundColor: UbanColors.of(context).surface,
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.only(bottom: elderNavClearanceWithPill(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              petBody,
              ElderGreetingTab(
                userId: widget.userId,
                userName: widget.userName,
                embedded: true,
                refreshSignal: _greetingPigSignal,
                tutorialKey: widget.greetingKey,
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

enum _MovementState { stationary, walking, fastTransit }
