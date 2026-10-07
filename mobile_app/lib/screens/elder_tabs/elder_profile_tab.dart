import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../identification_screen.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../../services/today_tasks_loader.dart';
import '../../services/elder_location_service.dart';
import 'elder_layout.dart';
import '../../services/api/location_api.dart';
import '../../services/location_device_status.dart';
import '../../utils/reminder_schedule.dart';
import '../../widgets/ui/ui.dart';
import '../../services/elder_reminder_manager.dart';
import '../../widgets/spotlight_tutorial.dart';
import '../../data/privacy_policy_content.dart';
import '../../widgets/policy_detail_dialog.dart';

// 模組化子元件與彈窗
import 'profile/models/pet_mood.dart'; // ⚠️ 只借用 PetHeartParticle，PetMood 列舉本身在小豬之家改版後已不再使用
import 'profile/dialogs/family_pairing_dialog.dart';
import 'profile/dialogs/ai_assistant_settings_dialog.dart';
import 'profile/widgets/profile_appearance_card.dart';
import 'profile/widgets/profile_greet_row.dart';
import 'profile/widgets/profile_location_hint.dart';
import 'profile/widgets/profile_task_card.dart';
import 'streak/streak_celebration.dart';
import 'streak/streak_service.dart';
import 'streak/streak_widgets.dart';
import 'widgets/elder_task_sheet.dart';
import 'widgets/elder_goal_form.dart';

class ElderProfileTab extends StatefulWidget {
  final int userId;
  final String userName;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。由
  //   上層 ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  final GlobalKey? tasksKey;
  final GlobalKey? familyPairingKey;
  final GlobalKey? aiAssistantKey;

  /// 連勝慶祝畫面的「去餵小豬」：由 `ElderHomeScreen` 傳入，轉成既有的 `_onNavTap(2)`。
  final VoidCallback? onGoFeedPig;

  /// 「重新觀看新手導覽」：由 `ElderHomeScreen` 傳入（重設進度、切回首頁並重播）。
  /// 為 null 時退回只重設進度並顯示 SnackBar。
  final Future<void> Function()? onReplayTutorial;

  /// ⚠️ 僅供 widget test 注入假提醒（正式呼叫端恆為 null）。非 null 時不讀 SharedPreferences、
  /// 不打 API（提醒、好友 id、位置分享狀態、年齡地區都跳過），畫面直接用這份資料。
  @visibleForTesting
  final List<Map<String, dynamic>>? debugInitialRemindersForTest;

  /// ⚠️ 僅供 widget test：搭配 [debugInitialRemindersForTest] 指定「今天已完成」的提醒 id。
  @visibleForTesting
  final Set<int>? debugInitialCompletedIdsForTest;

  const ElderProfileTab({
    super.key,
    required this.userId,
    required this.userName,
    this.tasksKey,
    this.familyPairingKey,
    this.aiAssistantKey,
    this.onGoFeedPig,
    this.onReplayTutorial,
    this.debugInitialRemindersForTest,
    this.debugInitialCompletedIdsForTest,
  });

  @override
  State<ElderProfileTab> createState() => _ElderProfileTabState();
}

class _ElderProfileTabState extends State<ElderProfileTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {


  // 小豬預設對話語錄（用於任務打卡的短暫慶祝語結束後回到的預設狀態）
  // ★ 2026-09-15 溢位巡檢時發現：這句沿用自舊的 _pigQuotes，寫死了「阿公」。
  //   自主模式的長輩過去會預設叫「長輩朋友」、性別未知（第四十九輪已改為必須
  //   輸入真實稱呼，不再有這個預設值），但阿嬤看到小豬喊她阿公一樣會困惑
  //   ——與 memoir_service 先前修掉的是同一類問題，故仍保留中性稱呼。
  static const String _defaultSpeechText = '今天天氣真好，一起散步活動身體吧！🌿';

  // ── 🐾 小豬之家狀態 ────────────────────────────────────────
  late AnimationController _particleController;
  late AnimationController _petBounceController;
  final List<PetHeartParticle> _petParticles = [];

  // ★ 第四十一輪（item 3）：朋友圈好友 ID（見 PetCornerActions 內部另行解析，
  // 本欄位供 _loadElderReminders 讀排程提醒使用）。null 代表尚未載入完成或
  // 載入失敗。
  // ★ 第五十輪：同時也是好友寵物排行榜（PetLeaderboardService）與今日食物
  // 解鎖來源（PetProgressService.loadFoodUnlocks）要用的權威 elder_id，
  // 三者共用同一把鍵，理由同 _loadElderReminders 的既有註解——不可各自
  // 用 widget.userId 補零臆測。
  String? _myFriendElderId;

  // ── 🛰️ 與家人分享 GPS 位置（戶外定位軌跡，與上方本機步數用途的 GPS 追蹤
  //   是不同的東西——見 ElderLocationService 檔頭說明）───────────────
  // 系統預設開啟（與後端 elder_profile.location_sharing_enabled DEFAULT 1 一致），
  // 實際值以 _loadLocationSharingState() 讀回的後端狀態為準。
  bool _locationSharingEnabled = true;
  bool _locationSharingBusy = false;


  // ── 📋 子女排程生活任務 ──────────────────────────────────
  List<Map<String, dynamic>> _reminders = [];
  Set<int> _completedReminderIds = {};
  bool _isLoadingReminders = false;
  // ★ 第四十九輪：見 _loadElderReminders 的 catch 區塊與
  // TodayTasksHandmadeSection.hasLoadError 的說明——讀取失敗不該跟「真的
  // 沒有安排提醒」顯示成同一張空狀態卡片。
  bool _hasReminderLoadError = false;

  // ── 🔥 連勝紀錄（新功能，見 streak/streak_service.dart）──────────
  late StreakSnapshot _streak = StreakService.buildSnapshot({}, DateTime.now());
  bool _taskSheetOpen = false;

  // ── 👤 頁首：年齡／地區（只用既有的 getElderProfile，拿不到就不顯示）──
  String? _headerDetail;

  // ── 🎨 小豬對話氣泡文字 ──────────────────────────────
  // 小豬頁面搬到 ElderPetTab 後，本分頁不再顯示氣泡；任務打卡失敗回退仍照舊
  // 重設這個值（_toggleTaskCompletion 邏輯一行未改），故保留欄位。
  // ignore: unused_field
  String _speechText = _defaultSpeechText;
  Timer? _speechBubbleTimer;

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
      // 連勝要用 elder_id 向後端合併其他裝置的「全部完成」日期。
      _loadStreak();
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

    final debugReminders = widget.debugInitialRemindersForTest;
    if (debugReminders != null) {
      // 測試注入：不連網、不讀本機。
      _reminders = List<Map<String, dynamic>>.from(debugReminders);
      _completedReminderIds = {...?widget.debugInitialCompletedIdsForTest};
    } else {
      _loadElderReminders();
      _loadMyFriendElderId();
      _loadLocationSharingState();
      _loadHeaderDetail();
      _loadStreak();
    }
    ElderReminderManager.instance.addListener(_onReminderManagerUpdate);
    StreakService.changes.addListener(_loadStreak);
    // 長輩從手機「設定」頁（開定位／改權限）回到 App 時，重新檢查定位權限，
    // 讓「我的」分頁的提示自動消失、位置回報自動恢復。這個觀察者只做這一件
    // 事（見 didChangeAppLifecycleState），與 ElderHomeScreen 自己的觀察者
    // 互不影響。
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只在回到前景時重查；recheckDeviceStatus 內部自帶守門（分享關閉、正在啟動
    // 時直接返回），而且只用 checkPermission，不會再次跳出權限對話框。
    if (state == AppLifecycleState.resumed && _locationSharingEnabled) {
      unawaited(ElderLocationService.instance.recheckDeviceStatus());
    }
    // 回前景時，若本分頁正在顯示就重新同步任務與連勝。
    if (state == AppLifecycleState.resumed && _isVisible) {
      unawaited(_refreshAll());
    }
  }

  // ── 重新同步機制（本頁在 IndexedStack 下保活，initState 只跑一次）──
  // 三種觸發共用 [_refreshAll]：下拉刷新、切回本分頁（TickerMode 由不可見→可見）、
  // App 回前景（僅在本分頁可見時）。
  bool _refreshing = false;
  bool? _wasVisible;
  bool _isVisible = true;

  /// 重新讀取「任務清單」與「連勝」。進行中不重複發。
  Future<void> _refreshAll() async {
    if (_refreshing || !mounted) return;
    if (widget.debugInitialRemindersForTest != null) return; // 測試注入模式不連網
    _refreshing = true;
    try {
      await Future.wait([_loadElderReminders(), _loadStreak()]);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 第一次進來 initState 已載過，只記錄狀態；之後由不可見→可見才刷新。
    final visible = TickerMode.valuesOf(context).enabled;
    _isVisible = visible;
    if (_wasVisible == false && visible) unawaited(_refreshAll());
    _wasVisible = visible;
  }

  /// 頁首年齡／地區：沿用既有的 `ApiService.getElderProfile`（聊天頁也在用），
  /// 失敗或欄位空白就維持只顯示名字，不新增 API、不補假資料。
  Future<void> _loadHeaderDetail() async {
    try {
      final res = await ApiService.getElderProfile(widget.userId);
      final data = res['data'];
      final profile = data is Map<String, dynamic>
          ? data
          : (res['status'] == 'error' ? null : res);
      final detail = ProfileGreetRow.buildDetail(profile);
      if (mounted && detail != _headerDetail) {
        setState(() => _headerDetail = detail);
      }
    } catch (_) {}
  }

  Future<void> _loadStreak() async {
    final snap = await StreakService.load(elderId: _myFriendElderId);
    if (mounted) setState(() => _streak = snap);
  }

  /// 讀取目前「與家人分享我的位置」開關狀態，供 [_buildLocationSharingCard] 顯示。
  /// 失敗（離線／尚未配對）時維持預設開啟的顯示，不影響畫面其餘功能。
  Future<void> _loadLocationSharingState() async {
    final elderId = await FriendService.resolveMyElderId(widget.userId);
    if (elderId == null || !mounted) return;
    final enabled = await LocationApi.getSharingEnabled(
      elderId: elderId,
      userId: widget.userId,
    );
    if (enabled != null && mounted) {
      setState(() => _locationSharingEnabled = enabled);
    }
  }

  Future<void> _handleLocationSharingToggle(bool value) async {
    if (_locationSharingBusy) return;
    setState(() => _locationSharingBusy = true);
    final ok = await ElderLocationService.instance.setSharingEnabled(value);
    if (!mounted) return;
    setState(() {
      _locationSharingBusy = false;
      if (ok) _locationSharingEnabled = value;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定失敗，請檢查網路連線後再試一次')),
      );
    }
  }

  void _onReminderManagerUpdate() {
    if (mounted && widget.debugInitialRemindersForTest == null) {
      _loadElderReminders();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ElderReminderManager.instance.removeListener(_onReminderManagerUpdate);
    StreakService.changes.removeListener(_loadStreak);
    _particleController.dispose();
    _petBounceController.dispose();
    super.dispose();
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
    try {
      final data = await TodayTasksLoader.load(elderKey);
      _completedReminderIds = data.completedIds;
      final list = data.reminders;
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
        _spawnHeartParticles();
        _petBounceController.forward(from: 0.0);
        _particleController.forward(from: 0.0);
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
        success = await ApiService.completeElderReminder(reminderId,
            localDate: today);
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
      // ★ 連勝紀錄（新功能）：打卡「成功之後」才檢查，上面的樂觀更新／回退邏輯不變。
      if (success) unawaited(_checkStreak());
    } else {
      // ★ 取消打卡：後端現在有 DELETE /reminder/{id}/complete，比照上面的
      // 樂觀更新＋失敗回退——否則別台裝置／家屬端仍看到已完成，下次同步又把
      // 這筆聯集回來。失敗時把 id 加回記憶體與本機清單，並提示再按一次。
      bool success;
      try {
        success = await ApiService.uncompleteElderReminder(reminderId,
            localDate: today);
      } catch (e) {
        debugPrint('⚠️ [ElderProfileTab] uncompleteElderReminder 例外: $e');
        success = false;
      }
      if (!mounted) return;
      if (!success) {
        setState(() => _completedReminderIds.add(reminderId));
        await prefs.setStringList(
          'completed_tasks_$today',
          _completedReminderIds.map((e) => e.toString()).toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '取消打卡沒有送出成功，請確認網路後再按一次',
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
      // 取消打卡：今天就不再是「全部完成」，讓連勝紀錄同步（不會觸發慶祝）。
      unawaited(_checkStreak());
    }
  }

  /// 連勝：今天的提醒剛好全部完成、且今天還沒慶祝過，就顯示慶祝畫面。
  /// 失敗一律吞掉（見 [StreakService.syncToday]），不影響打卡本身。
  Future<void> _checkStreak() async {
    final celebration = await StreakService.syncToday(
      reminders: _reminders,
      completedIds: _completedReminderIds,
      elderId: _myFriendElderId,
    );
    if (celebration == null || !mounted) return;
    // 抽屜若還開著就先收起來：否則按「去餵小豬」切到小豬分頁後，抽屜會還蓋在上面。
    // （_taskSheetOpen 只在抽屜存在期間為 true，此時最上層路由就是抽屜。）
    if (_taskSheetOpen) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    await showStreakCelebration(context, celebration,
        onFeedPig: widget.onGoFeedPig);
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

  // ── 🎯 打卡入口（任務卡「打卡」鈕與抽屜共用）─────────────────────
  // 新版介面只提供「把還沒做的打勾」，不再有取消打勾；而 _toggleTaskCompletion
  // 本身是「切換」，所以這裡擋掉「已完成」與「處理中」的重複點擊，避免連點兩下
  // 被後面那下切回未完成。
  final Set<int> _checkInFlight = {};

  Future<void> _checkIn(Map<String, dynamic> reminder) async {
    final id = int.tryParse(reminder['id']?.toString() ?? '');
    if (id == null) return;
    if (_completedReminderIds.contains(id) || !_checkInFlight.add(id)) return;
    try {
      await _toggleTaskCompletion(id);
    } finally {
      _checkInFlight.remove(id);
    }
  }

  /// 開「今天要做的事」抽屜（與首頁共用 [ElderTaskSheetBody]）。
  void _openTaskSheet() {
    HapticFeedback.lightImpact();
    _taskSheetOpen = true;
    showUbanSheet<void>(
      context,
      (ctx) => ElderTaskSheetBody(
        readGroups: () =>
            groupByStatus(_reminders, _completedReminderIds, DateTime.now()),
        onCheckIn: _checkIn,
        onAddGoal: () => _editGoal(null),
        onEditGoal: _editGoal,
        onDeleteGoal: (g) async {
          if (await confirmDeleteElderGoal(context, g, userId: widget.userId)) {
            await _loadElderReminders();
          }
        },
      ),
    ).whenComplete(() => _taskSheetOpen = false);
  }

  /// 長輩自建目標：新增（[goal]＝null）或修改；成功後重讀清單。
  Future<void> _editGoal(Map<String, dynamic>? goal) async {
    final elderId = _myFriendElderId;
    if (elderId == null || elderId.isEmpty || !mounted) return;
    final ok = await runElderGoalForm(context,
        elderId: elderId, userId: widget.userId, existing: goal);
    if (ok) await _loadElderReminders();
  }

  void _openPolicy() {
    PolicyDetailDialog.show(
      context,
      title: PrivacyPolicyContent.title,
      introText: PrivacyPolicyContent.introText,
      headerIcon: Icons.privacy_tip_outlined,
      primaryColor: UbanColors.of(context).brandStrong,
      secondaryColor: UbanColors.of(context).brandFill,
      sections: PrivacyPolicyContent.sections,
      lastUpdated: '最後更新：${PrivacyPolicyContent.lastUpdated}',
    );
  }

  Future<void> _replayTutorial() async {
    final replay = widget.onReplayTutorial;
    if (replay != null) {
      await replay();
      return;
    }
    await SpotlightTutorial.resetAllTutorials();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重新開啟教學！切換至首頁即可重新查看導覽。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    const gap = SizedBox(height: 14);

    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.brandFill,
          backgroundColor: c.surface,
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.fromLTRB(18, 14, 18, elderNavClearanceWithPill(context)),
          child: Align(
            alignment: Alignment.topCenter,
            // 平板橫放時不要讓卡片拉成整排，限制最大寬度。
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileGreetRow(name: widget.userName, detail: _headerDetail),
                  const SizedBox(height: 18),

                  // 連勝卡（新功能）
                  StreakCard(snapshot: _streak),
                  gap,

                  // 今日任務卡：進度環＋下一件，點開抽屜；打卡仍走 _toggleTaskCompletion
                  ProfileTaskCard(
                    key: widget.tasksKey,
                    reminders: _reminders,
                    completedIds: _completedReminderIds,
                    isLoading: _isLoadingReminders,
                    hasLoadError: _hasReminderLoadError,
                    onCheckIn: _checkIn,
                    onOpenSheet: _openTaskSheet,
                  ),
                  gap,

                  // 家人綁定
                  UbanActionTile(
                    key: widget.familyPairingKey,
                    icon: Icons.link_rounded,
                    title: '家人綁定',
                    subtitle: '出示配對碼給家人掃',
                    trailing: UbanActionTile.chevron(context),
                    // ★ 第四十九輪修復：明確傳入保證非空的長輩 id（理由見
                    // family_pairing_dialog.dart 的 fetchCode 說明），不能讓對話框自己猜。
                    onTap: () =>
                        showFamilyPairingDialog(context, widget.userId),
                  ),
                  gap,

                  // 語音助理
                  UbanActionTile(
                    key: widget.aiAssistantKey,
                    icon: Icons.mic_rounded,
                    title: '語音助理',
                    subtitle: '喊「Hey 嘎蛙」叫小嘎',
                    trailing: UbanActionTile.chevron(context),
                    onTap: () => showAiAssistantSettingsDialog(
                      context: context,
                      userId: widget.userId,
                      userName: widget.userName,
                    ),
                  ),
                  gap,

                  // 分享我的位置（長輩本人的隱私開關；關閉時家屬看不到位置）
                  UbanActionTile(
                    icon: Icons.place_rounded,
                    title: '分享我的位置',
                    subtitle: _locationSharingEnabled
                        ? '子女可以看到您的位置與移動路線'
                        : '目前未分享，子女無法看到您的位置',
                    trailing: UbanSwitch(
                      value: _locationSharingEnabled,
                      onChanged: _locationSharingBusy
                          ? null
                          : _handleLocationSharingToggle,
                    ),
                  ),
                  // 手機的定位功能／權限沒開時，開關雖然是「開」，位置其實傳不出去：
                  // 在開關下方整列寬直接告訴長輩原因與怎麼修。
                  ValueListenableBuilder<String?>(
                    valueListenable: ElderLocationService.instance.deviceStatus,
                    builder: (context, status, _) {
                      if (!_locationSharingEnabled ||
                          !LocationDeviceStatus.isProblem(status)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: LocationStatusHint(status: status!),
                      );
                    },
                  ),
                  gap,

                  // 重新觀看新手導覽
                  UbanActionTile(
                    icon: Icons.replay_rounded,
                    title: '重新觀看新手導覽',
                    subtitle: '忘記功能怎麼用？點這裡',
                    onTap: _replayTutorial,
                  ),
                  gap,

                  // 外觀：跟隨系統／淺色／深色
                  const ProfileAppearanceCard(),
                  gap,

                  // 服務條款與隱私權政策
                  UbanActionTile(
                    icon: Icons.privacy_tip_outlined,
                    title: '查看服務條款與隱私權政策',
                    subtitle: '了解我們如何使用與保護您的資料',
                    onTap: _openPolicy,
                  ),
                  gap,

                  // 切換身分（登出）
                  UbanActionTile(
                    icon: Icons.swap_horiz_rounded,
                    tone: UbanTone.danger,
                    title: '切換身分',
                    subtitle: '登出並回到身分選擇',
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
