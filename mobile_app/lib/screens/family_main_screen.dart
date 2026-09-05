import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'family/family_home_tab.dart';
import 'family/family_interaction_tab.dart';
import 'family/family_data_tab.dart';
import 'family/alert_center_screen.dart';
import 'family/subscription_test_screen.dart';
// ⚠️ 這行 import 在分支整合時遺失（:798 有 const FamilySubscriptionScreen() 卻無 import），
//    2026-08-10 第十九輪補回。
import 'family/family_subscription_screen.dart';
import '../models/elder.dart';
import '../services/elder_manager.dart';
import '../services/signaling.dart';
import '../services/api_service.dart';
import 'video_call_screen.dart';
import 'caregiver_pairing_screen.dart';
import 'family_onboarding_screen.dart';
import 'emergency_permission_guide_screen.dart';
import 'package:flutter_application_1/utils/app_logger.dart';
import '../globals.dart';
import '../widgets/spotlight_tutorial.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// ★ 2026-08-05 第十七輪：跌倒警報的「亮螢幕 + 通知 + 朗讀」三件套
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/cctv_alert_notification.dart';

class FamilyMainScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const FamilyMainScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FamilyMainScreen> createState() => _FamilyMainScreenState();
}

class _FamilyMainScreenState extends State<FamilyMainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final Signaling _signaling = Signaling();
  bool _isIncomingCallDialogOpen = false;

  /// ★ 2026-08-23：供 `_presentCctvAlert` 判斷「App 目前是否在前景」，只在前景
  /// 才呼叫 `WakelockPlus.enable()`——`cctv-alert` 是 Socket 事件，連線在 App
  /// 背景時（尚未被系統殺死）仍可能存活並觸發 `_handleCctvAlert`，並非只有
  /// 前景才會走到這裡（與同方法上方註解「APP 在背景／被殺死時不會經過這裡」
  /// 描述的是設計預期、不是程式碼保證的不變式）。若不判斷就直接 enable，
  /// wakelock 會在背景視窗上掛著沒有實際點亮效果，卻要等到彈窗關閉的
  /// `.then()` 才 disable——使用者之後切回前景會發現螢幕莫名常亮。
  /// 初始值為 `resumed`：`initState` 執行當下 App 必然在前景，
  /// `didChangeAppLifecycleState` 尚未觸發過也不會誤判成背景。
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  Elder? _currentElder;
  List<Elder> _elders = [];
  bool _isElderOnline = false;
  /// 長輩端「第一台在線設備」的 socket id，由 `_applyDeviceList()` 維護。
  /// 撥打通話時當作 `VideoCallScreen.targetSocketId`，讓 SDP 精準送達而非靠房間廣播。
  /// 🚨 跌倒警報要開哪一台監視機時**不可**用它——那要用該裝置自己的 `id`。
  String? _elderSocketId;
  Timer? _deviceRefreshTimer;
  // ★ 2026-08-05 第十七輪：原本的 _onlineStateDebounceTimer / _pendingOnlineState
  //   是「每收到事件就重排」的雙向 debounce，週期與輪詢週期（2500ms）相等，
  //   兩者互相取消導致狀態長期停滯不提交。改為 _offlineConfirmTimer：
  //   僅在「上線→離線」方向做一次性確認，見 onElderDevicesUpdate 內的說明。
  Timer? _offlineConfirmTimer;
  // ★ 2026-08-10 第十九輪（A4）：設備清單的 HTTP 交叉驗證輪詢（10 秒）。
  //   與上面 2.5 秒的 Socket 輪詢**併行**、互為備援：
  //   - Socket 斷線（切網路／進背景被凍結／後端重啟）時清單不會停在舊值；
  //   - 剛用配對碼綁定、尚未成功 join 的離線監視機只存在於後端階段 0
  //     （`monitor_device_binding`），只有這條 HTTP 路徑撈得到。
  //   週期刻意取 10 秒（非 2.5 秒的倍數附近）：既不與 Socket 輪詢同步打點，
  //   也不至於讓「監視機主動退出」的移除延遲到使用者有感。
  Timer? _monitorHttpTimer;

  // ★ 2026-08-10 第十九輪（E）：dispose 時要把自己掛在 Signaling **單例**上的
  //   來電 callback 收回，否則 closure 會一直持有已 dispose 的 State。
  //   但**不能無條件設 null**：`_goHomeAfterCall()` 走的是 `pushAndRemoveUntil`，
  //   Flutter 會先建好新的 FamilyMainScreen（其 initState 已重新註冊 callback）
  //   才 dispose 舊的——無條件 null 會把「新的」handler 一起清掉，家屬端從此
  //   前景收不到來電。因此保留自己那份 closure 的參考，dispose 時只在
  //   「單例上掛的仍是我這一份」時才清除（identical 比對）。
  CallRequestCallback? _ownCallRequest;
  CallRequestCallback? _ownEmergencyCall;
  CallRequestCallback? _ownCancelCall;

  // ★ 移植自 family_dashboard_view.dart：監控裝置清單、CCTV 警報、訂閱層級
  //   （型別對齊該檔實際宣告：_monitorDevices 為 List<dynamic>、_tierLevel 為 String）
  List<dynamic> _monitorDevices = [];
  final List<Map<String, dynamic>> _activeAlerts = [];

  /// ★ 2026-08-24（首頁「最新警示」滑動關閉，父層一半）：使用者在
  /// `FamilyHomeTab` 首頁把警示卡片滑掉／按下已讀鍵時記錄的複合鍵集合，
  /// 對應 `FamilyHomeTab.dismissedAlertKeys`（該 widget 參數宣告見
  /// `family/family_home_tab.dart:49`，filter 用法見同檔 `:3009`）。
  ///
  /// **必須放在這個 State，不能放在 `FamilyHomeTab` 自己的 State**：
  /// `FamilyHomeTab` 是 `IndexedStack` 底下的一頁，本畫面每 2.5 秒的裝置／
  /// 警報輪詢（`_applyDeviceList` 等）都會呼叫 `setState` 觸發整棵樹重建，
  /// 若集合放在子分頁的 State 裡則每次重建都可能連帶被子分頁自己的
  /// `_loadDynamicData()`（下拉重新整理／切換長輩時整批重抓 `_realLogs`／
  /// `_emergencyAlerts`）一併洗掉——這正是 `family_home_tab.dart` 該欄位
  /// 宣告處的註解說明「刻意由父層持有」的原因，見該檔 :42-48。
  ///
  /// **切換長輩時刻意不清空、也不做 per-elder 命名空間**（不比照下方
  /// `_switchElder()` 對 `_activeAlerts` / `_knownAlertKeys` 的 `.clear()`）：
  /// 這組複合鍵的組法（`family_home_tab.dart::_buildAlertPreview`）優先用
  /// `'alert:$alert_id'` / `'log:$log_id'`，兩者的 `alert_id`／`log_id`
  /// 都是後端**單一資料表**的全域 `INTEGER PRIMARY KEY AUTOINCREMENT`
  /// （`uban-api/database.py`：`emergency_alerts.alert_id` :266、
  /// `activity_log.log_id` :430），不同長輩的警示不可能撞到同一個值；
  /// 缺少該 PK 時的備援複合鍵（`'live:$type:$deviceId:$ts'` 等）內嵌的
  /// `device_id` 本身就是 `elder_id` 與裝置名稱的 CRC32 雜湊
  /// （`monitor_identity.py::monitor_device_id`，見
  /// `CLAUDE_call-monitor.md` §6.9），同樣已經是 per-elder 的值。
  /// 換句話說，這組 id 的設計本來就讓「長輩 A 的鍵蓋到長輩 B 的警示」這件事
  /// 在實務上不可能發生，清空反而會違反上一段引用的既有契約
  /// （子分頁明確要求這個集合要撐過 `didUpdateWidget`，也就是切換長輩那次）。
  ///
  /// **刻意不設上限、不做 LRU 淘汰、不寫入 SharedPreferences**：
  /// 這是單次 App 執行期間的記憶體內狀態（未持久化，冷啟動即歸零），
  /// 首頁清單本身也只顯示最近 30 筆（`family_home_tab.dart:3013`），
  /// 使用者一個 session 內能滑掉的筆數遠遠不到需要淘汰的量級；
  /// 若改用「淘汰最舊一筆」的上限機制，一旦被淘汰的那筆剛好還在目前
  /// 30 筆的顯示範圍內，等於讓一個已經被使用者明確關閉的警示自己復活
  /// ——這正是本輪任務要修的問題（滑掉又跳回來），不能為了設上限
  /// 而重新引入它。
  final Set<String> _dismissedAlertKeys = {};

  /// ★ 2026-08-18 IPS prototype：目前長輩的室內定位（presence）狀態，正規化自
  /// REST `ApiService.getCurrentZone`（快照）與 Socket `elder-zone-update`
  /// （即時推播）兩種不同形狀的來源，統一成 `{zone, enteredAt, updatedAt,
  /// present, deviceId}` 供 `FamilyHomeTab` 與 `FamilyInteractionTab` 顯示。
  ///
  /// ★ 2026-08-24（「設定區域」校準功能移除）：`present`（後端
  /// `ZoneTracker.snapshot()` 的過期判定，見
  /// `indoor_position.py::PRESENCE_STALE_SECONDS`）取代了原本的 `calibrated`，
  /// 成為「長輩在此」高亮唯一的判斷依據——校準功能移除後多數監視機永遠不會
  /// 有具名 zone，`calibrated` 已經失去意義。`zone` 欄位仍保留（多半是
  /// `'unknown'`），只作為附加資訊顯示，不再參與任何狀態判斷。
  /// null＝「尚未取得任何回應」（elder 剛切換、REST 還沒回來，或還沒收過
  /// 任何 socket 推播），畫面比照 `present != true` 顯示同一張「目前未偵測到
  /// 長輩」提示卡，不另外做 loading 狀態。
  /// 「尚未綁定監視機」則是完全不同的狀態，靠 `_monitorDevices.isEmpty` 判斷，
  /// 不會落到這裡。
  ///
  /// 🚨 **過期規則**（`_expireStaleZonePresenceIfNeeded`）：後端只在「偵測到
  /// 人」時才會推播／回應 `present: true`，長輩離開鏡頭後不會有主動的
  /// 「離開」事件——`present` 一旦被設為 `true`，必須靠前端自己對
  /// `updatedAt` 做逾時判斷才會變回 `false`，否則會永遠停在最後一次「在」的
  /// 結果（這正是本輪要修的 bug：監視機範圍內沒人，清單卻一直顯示「長輩在
  /// 此」）。見該方法與 `_zonePresenceStaleWindow` 的說明。
  ///
  /// `deviceId`（2026-08-24 新增，String?）＝送出這筆 zone 資料的監視機
  /// device_id，供監控卡片判斷「目前長輩所在此處」要高亮哪一張。兩個來源
  /// 都叫這個鍵：Socket 見 `indoor_position.py::_build_zone_payload`
  /// （`'device_id'`，字串）；REST 見 `routers/ips.py::get_current_zone`
  /// 回應中的 `'device_id'`（int，原樣回傳查詢參數，因此必然等於
  /// `_maybeFetchInitialZone` 當初查詢的那台監視機）。
  Map<String, dynamic>? _elderZone;
  /// dedupe：避免每次 2.5s socket 輪詢／10s HTTP 交叉驗證重新套用設備清單時
  /// 都重打一次 `getCurrentZone`。key＝`'elderId:deviceId'`（或 `'elderId:none'`）。
  /// 只在**成功**取得回應（或確定沒有監視機）時才更新，查詢失敗刻意不更新，
  /// 讓下一輪 `_applyDeviceList` 自然重試，不會卡死在單次網路抖動上。
  String? _zoneFetchKey;
  bool _zoneFetchInFlight = false;
  /// ★ 2026-08-05 第十七輪：去重鍵由「alert_id」改為「alert_id + timestamp」複合鍵。
  ///   後端 `_insert_alert()`（`services/yolo_alert_dispatcher.py`）對同 elder + 同 device +
  ///   同 alert_type 且 `status='active'` 的既有列是 **UPDATE 並沿用原本的 alert_id**，
  ///   只靠 alert_id 去重會讓第二次以後的同類警報完全靜默
  ///   （「跌倒測試」鈕按第二次不會有任何反應，YOLO 連續偵測也一樣）。
  final Set<String> _knownAlertKeys = {};

  /// ★ 2026-08-05 第十七輪：跌倒警報彈窗的**本地**防疊加旗標。
  ///   刻意不放進 `Signaling` singleton——先前加在 singleton 的顯示狀態旗標
  ///   （`isIncomingCallDialogVisible`）曾導致長輩端冷啟動失敗而被整輪回退。
  bool _cctvAlertDialogOpen = false;

  /// ★ 第四十輪（item 2）：目前正在觀看哪一台監視機的 CCTV 即時畫面（只記
  ///   `deviceId`，未在觀看時為 `null`）。供 `_presentCctvAlert()` 判斷「同一台
  ///   監視機已經在看了，不必再給查看鍵」。同樣刻意不放進 `Signaling`
  ///   singleton——理由同上一則註解，這是本畫面自己的 State。
  String? _viewingMonitorDeviceId;

  /// 警報朗讀用的 TTS，只建立一次（不要每次警報都 new），`dispose()` 時 stop。
  FlutterTts? _alertTts;
  String _tierLevel = 'free';
  String _tierDisplayName = '一般會員';
  int _devicesMax = 2;

  /// ★ 2026-08-04 第 4 項：訂閱到期／設備超量彈窗只在每次進入本畫面時提示一次，
  /// 避免每次 `_loadSubscriptionTier()` 重新整理都再彈一次而干擾使用者。
  bool _overLimitDialogShown = false;

  /// ★ 2026-08-20 新增：家屬端首次進入首頁時，若偵測到是 MIUI 家族裝置，自動
  /// 導向「鎖屏與背景權限設定」引導頁（`EmergencyPermissionGuideScreen`）一次。
  ///
  /// 補的是長輩端那一輪遺留的缺口：「後台彈出介面」主要是給家屬端用的（背景
  /// 彈出跌倒警報），但先前只有長輩端 `elder_home_screen.dart` 會自動觸發，
  /// 家屬端只能從設定頁手動找到——需要這項權限最迫切的角色反而看不到自動
  /// 引導，這裡補上對稱的觸發點。
  ///
  /// 與 `elder_home_screen.dart::_maybeShowMiuiPermissionGuide` 共用同一個
  /// `EmergencyPermissionGuideScreen.prefsSeenKey`（刻意不開新鍵）——同一台
  /// 裝置只要看過一次引導頁（不論是哪個角色觸發的），另一邊就不會再自動彈。
  ///
  /// 為什麼放在這裡（而不是更早的冷啟動路徑）：比照長輩端的作法，刻意放在
  /// 「已經到達穩定首頁」之後才觸發，用 addPostFrameCallback 確保第一影格
  /// 已經畫出、Navigator 已經就緒；呼叫本身完全不 await，不會拖慢 initState
  /// 或擋住 `_initializeElderManagerAndConnect`／`_loadSubscriptionTier` 等
  /// 既有初始化流程，也完全不碰 `_setupSignalingCallbacks`／
  /// `_loadElderAndConnect`／`_applyDeviceList`／`_switchElder`／計時器等
  /// 既有通話與裝置狀態邏輯。
  ///
  /// 任何一步失敗（SharedPreferences 不可用、MethodChannel 未實作／拋例外）都
  /// 直接 return，不顯示引導頁——APP 其餘行為與目前版本完全相同。
  Future<void> _maybeShowMiuiPermissionGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadySeen =
          prefs.getBool(EmergencyPermissionGuideScreen.prefsSeenKey) ?? false;
      if (alreadySeen) return;

      final isMiui = await const MethodChannel(
        'com.example.app/notification_policy',
      ).invokeMethod<bool>('isMiuiFamily');
      if (isMiui != true) return;

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const EmergencyPermissionGuideScreen(),
        ),
      );
    } catch (_) {
      // 靜默失敗：不顯示引導頁，APP 其餘行為不受影響。
    }
  }

  // ★ 第四十一輪 item 2（第二階段）：新手指引用的高光目標 GlobalKey。
  //   比照長輩端 elder_home_screen.dart 同一輪同一功能的作法——全部由本畫面
  //   （IndexedStack 的父層）持有並往下傳給三個分頁：IndexedStack 會讓三個
  //   分頁的 initState 在本畫面第一次建構時就全部跑過一次（保活），無法用
  //   各分頁自己的 initState 偵測「使用者第一次切過來」，因此「第一次切到
  //   哪個分頁」的判斷邏輯與對應的 key 都集中在這裡，詳見
  //   _onItemTapped / _maybeShowTabTutorial。
  final List<GlobalKey> _navItemKeys = List.generate(3, (_) => GlobalKey());
  // 首頁分頁
  final GlobalKey _homeElderHeaderKey = GlobalKey();
  final GlobalKey _homeMonitorStatusKey = GlobalKey();
  final GlobalKey _homeAiMoodRadarKey = GlobalKey();
  final GlobalKey _homeAlertPreviewKey = GlobalKey();
  // 互動分頁
  final GlobalKey _interactionCallKey = GlobalKey();
  final GlobalKey _interactionAiCopilotKey = GlobalKey();
  final GlobalKey _interactionCommunityKey = GlobalKey();
  final GlobalKey _interactionMonitorKey = GlobalKey();
  // 資料分頁
  final GlobalKey _dataCaregiverKey = GlobalKey();
  final GlobalKey _dataElderSummaryKey = GlobalKey();
  final GlobalKey _dataMemoirsKey = GlobalKey();
  final GlobalKey _dataAiHelperKey = GlobalKey();

  /// 本次畫面存活期間，已經嘗試顯示過教學的分頁 index。只避免同一個 session
  /// 內因快速連續切換而重複呼叫；「使用者是否真的看過教學」這個跨 session 的
  /// 持久判斷，交給 SpotlightTutorial 內部的 SharedPreferences 完成旗標。
  final Set<int> _tabTutorialAttempted = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pendingAcceptedCall.addListener(_onPendingCallChanged);

    appLogger.d('🔍 FamilyMainScreen initialized:');
    appLogger.d('   userId: ${widget.userId}');
    appLogger.d('   userName: ${widget.userName}');

    _initializeElderManagerAndConnect();
    _loadSubscriptionTier();

    // ★ 2026-08-20 新增：MIUI 家族裝置的「鎖定螢幕顯示／後台彈出介面」權限
    //   引導。等第一影格畫出後才檢查與導航，且完全不 await、不擋任何既有的
    //   啟動流程；詳見 _maybeShowMiuiPermissionGuide。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowMiuiPermissionGuide();
    });

    // ★ 第四十一輪（item 2 第二階段）：主介面（底部三個標籤）的新手指引，
    //   家屬第一次進入主畫面就會看到。獨立一個 addPostFrameCallback（不與
    //   上面的 MIUI 引導共用），且內部一律先確認沒有正在進行的來電／警報
    //   才會顯示——見 _isSafeToShowFamilyTutorial / _maybeShowMainTutorial
    //   的說明。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowMainTutorial();
    });
  }

  Future<void> _initializeElderManagerAndConnect() async {
    appLogger.d('🔄 FamilyMainScreen: Starting ElderManager initialization');
    await ElderManager().initialize(userId: widget.userId);
    
    if (mounted) {
      setState(() {
        _elders = ElderManager().pairedElders;
        _currentElder = ElderManager().currentElder;
      });
      _setupSignalingCallbacks();
      await _loadElderAndConnect();
      _startDeviceRefreshTimer();
      
      // 在初始化連線後，檢查是否有從背景進來的待處理來電
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _checkPendingAcceptedCall();
      });
    }
  }

  void _startDeviceRefreshTimer() {
    _deviceRefreshTimer?.cancel();
    // 取樣週期維持 2.5 秒不變；「上線→離線」的抖動抑制改由 _offlineConfirmTimer
    // 單向處理（見 onElderDevicesUpdate），不再讓輪詢週期與 debounce 週期相等而互相取消。
    _deviceRefreshTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      // ★ 2026-08-24：presence 過期檢查獨立於裝置清單輪詢是否成功送出，放在
      //   下面的 socket 連線判斷之前——即使 socket 斷線也要繼續判斷
      //   `_elderZone` 是否已經該過期，網路異常正是「不該再相信舊資料」最
      //   典型的情況。見 `_expireStaleZonePresenceIfNeeded` 的完整說明。
      _expireStaleZonePresenceIfNeeded();

      final elder = _currentElder;
      if (elder == null || _signaling.socket?.connected != true) return;
      final elderIdStr = elder.elderId ?? elder.id.toString();
      _signaling.sendGetElderDevices('comm_elder_$elderIdStr');
      debugPrint('🔄 [Device Refresh] 輪詢長輩設備狀態 (elder_id=$elderIdStr)');
    });

    // ★ 2026-08-10 第十九輪（A4）：HTTP 交叉驗證，不依賴 socket 是否還活著。
    //   先立即打一次，避免使用者剛配對完還要等滿 10 秒才看到裝置。
    _monitorHttpTimer?.cancel();
    _refreshMonitorDevicesViaHttp();
    _monitorHttpTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _refreshMonitorDevicesViaHttp();
    });
  }

  Future<void> _loadElderAndConnect() async {
    debugPrint('📡📡📡 [FamilyMainScreen] ===== 開始載入長輩並連線 =====');

    if (_currentElder == null) {
      debugPrint('⚠️ [FamilyMainScreen] 沒有已選長輩，嘗試重新整理...');
      // ★ B2 修復（2026-08-04）：原本這裡只印 log 就直接 return，完全沒有重試，
      //   導致家屬端永遠不會 join 任何房間 → 後端 rooms_manager/user_fcm_token
      //   查無此房 → 長輩來電時後端記「無任何轉發目標」，通話 100% 遺失且前端毫無提示。
      //   改為有限次數（最多 2 次、間隔 2 秒）重新初始化 ElderManager 後再檢查一次；
      //   若仍失敗則印出顯眼錯誤並中止，不進入無窮迴圈、不阻塞 initState。
      const maxRetries = 2;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        if (attempt > 1) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
        }
        debugPrint('🔁 [FamilyMainScreen] 第 $attempt/$maxRetries 次嘗試重新取得配對長輩...');
        await ElderManager().initialize(userId: widget.userId);
        if (!mounted) return;
        final refreshedElder = ElderManager().currentElder;
        if (refreshedElder != null) {
          setState(() {
            _elders = ElderManager().pairedElders;
            _currentElder = refreshedElder;
          });
          debugPrint('✅ [FamilyMainScreen] 第 $attempt 次重試成功取得配對長輩: ${refreshedElder.displayName}');
          break;
        }
      }

      if (_currentElder == null) {
        debugPrint('❌❌❌ [FamilyMainScreen] 無法取得配對長輩，家屬端將不會加入任何房間 → 長輩來電必然收不到！請檢查 family_elder_relationship 配對資料。');
        return;
      }
    }

    // ★ 修復：使用正確的房間格式 comm_elder_{elder_id}
    //    elderId 是 elder_profile.elder_id（如 '0343'），而非數字 id
    final elderIdStr = _currentElder!.elderId ?? _currentElder!.id.toString();
    final roomId = 'comm_elder_$elderIdStr';

    debugPrint('📡📡📡 [FamilyMainScreen] ===== 連線到房間: $roomId =====');

    final String? fcmToken = await FirebaseMessaging.instance.getToken();

    _signaling.connect(
      roomId,
      'family',
      deviceName: '${widget.userName}的App',
      userId: widget.userId,
      fcmToken: fcmToken,
    );

    // ★ B3（2026-08-04）：連線後印出 join 參數，供真機除錯比對家屬端與長輩端房號是否一致
    //   （房號漂移會導致長輩端 join-failed 而被後端斷線）。純 log，不影響邏輯。
    debugPrint('🔑 [FamilyMainScreen] join 參數：room=$roomId, role=family, userId=${widget.userId}, fcmToken=${fcmToken == null ? "null" : "${fcmToken.substring(0, fcmToken.length < 12 ? fcmToken.length : 12)}..."}');

    // ★ B1（2026-08-04）：此處 socket 必定已由上面的 _signaling.connect(...) 建立完成，
    //   再呼叫一次以保證 elder-unbound 監聽器確實掛上
    //   （_setupSignalingCallbacks() 那次呼叫發生在 connect() 之前，socket 當時可能仍是 null）。
    _registerElderUnboundListener();
    _registerCctvAlertListener();

    // 請求取得長輩設備在線狀態
    _signaling.sendGetElderDevices(roomId);
  }

  void _setupSignalingCallbacks() {
    // 監聽來電（長輩打給家屬）
    _ownCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('📞 [FamilyMainScreen] 收到來電: room=$roomId, sender=$senderId, callId=$callId, senderName=$senderName');
      _showIncomingCallDialog(roomId, senderId, callId, callerName: senderName);
    };
    _signaling.onCallRequest = _ownCallRequest;

    // 監聽緊急來電
    _ownEmergencyCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🚨 [FamilyMainScreen] 緊急來電: room=$roomId, senderName=$senderName');
      _showIncomingCallDialog(roomId, senderId, callId, isEmergency: true, callerName: senderName);
    };
    _signaling.onEmergencyCall = _ownEmergencyCall;

    // 監聽取消呼叫
    _ownCancelCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🔕 [FamilyMainScreen] 來電取消: room=$roomId');
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
    };
    _signaling.onCancelCall = _ownCancelCall;

    // ★ 2026-07-30 Task 2：監聽長輩被解綁事件，即時更新 UI，避免黑屏。
    // ★ B1 修復（2026-08-04）：原本用 _signaling.socket?.on(...) 直接掛在這裡，
    //   但 initState → _initializeElderManagerAndConnect() 呼叫本方法時 socket 還沒建立
    //   （socket 要到稍後的 _loadElderAndConnect() → _signaling.connect() 才建立），
    //   `?.` 短路導致這個監聽器從未掛上。改為呼叫可重試、冪等的註冊方法；
    //   真正確保掛得上的第二次呼叫點在 _loadElderAndConnect() 內 connect() 之後。
    _registerElderUnboundListener();
    _registerCctvAlertListener();

    // 監聽長輩設備狀態更新
    _signaling.onElderDevicesUpdate = (devices) {
      if (!mounted) return;
      debugPrint('📡 [FamilyMainScreen] 收到長輩設備狀態更新: $devices');
      _applyDeviceList(devices);
    };

    // ★ 2026-08-18 IPS prototype：監聽長輩室內定位區域切換推播。
    _signaling.onElderZoneUpdate = (payload) {
      if (!mounted) return;
      debugPrint('📍 [FamilyMainScreen] 收到 elder-zone-update: $payload');
      _applyZoneUpdate(payload);
    };
  }

  /// ★ 2026-08-10 第十九輪（需求 5 / A4）：設備清單的**唯一**套用點。
  /// Socket 的 `elder-devices-update` 與新的 10 秒 HTTP 交叉驗證
  /// （`_refreshMonitorDevicesViaHttp`）都走這裡——兩者呼叫的是後端同一支
  /// `_get_elder_devices_list()`，形狀與內容完全一致，因此以「後到者為準」
  /// 覆蓋，而**不是**單調聯集。
  ///
  /// ⚠️ 不要改成聯集：需求 3「監視機主動退出監控模式要從家屬端清單移除」
  /// 與卡片上的刪除功能都仰賴清單能夠**變短**，聯集會讓已刪除的裝置永遠留著。
  void _applyDeviceList(List<dynamic> devices) {
      // ★ 2026-08-17 需求 8 修復（Fix B3）：家屬切換長輩後 socket 仍留在舊房間
      //   （leave_room 不在本輪範圍，見後端 socket_app.py::on_disconnect 旁的說明），
      //   舊長輩的 elder-devices-update 廣播仍可能送達本頁。後端（B1）已在每筆
      //   設備補上 elderId，這裡比對「這份清單描述的是不是我正在看的長輩」，
      //   不是就整包丟棄、不動任何既有 state。
      //   ⚠️ 舊版後端、或本來就沒有設備的清單不會帶 elderId（一筆都沒有），此時
      //   必須照舊往下套用——需求 3（監視機退出後清單要立刻變短）依賴空清單仍能
      //   生效並清空 _monitorDevices，不可因為偵測不到 elderId 就整段跳過。
      final String? currentElderId = _currentElder?.elderId ?? _currentElder?.id.toString();
      for (final d in devices) {
        if (d is Map && d['elderId'] != null) {
          if (d['elderId'].toString() != currentElderId) {
            debugPrint(
                '🚫 [FamilyMainScreen] 忽略非當前長輩的設備清單更新 (payload elderId=${d['elderId']}, 目前長輩=$currentElderId)');
            return;
          }
          break; // 同一次廣播內所有筆的 elderId 一致，找到一筆可判定即可
        }
      }

      // ★ 2026-08-05 第十七輪：原本的 debounce 每收到一個事件就 cancel + 重排 2500ms，
      //   而輪詢週期也正好是 2500ms（_startDeviceRefreshTimer）、後端還會廣播給房內所有
      //   家屬 socket，於是 debounce 幾乎永遠在 fire 之前就被下一個事件取消 →
      //   `_isElderOnline` 與 `_monitorDevices` 兩個狀態長期停在初始值
      //   （家屬端看不到監視機、在線燈不亮）。
      //   改為：清單一律立即套用；只有「上線→離線」這個方向做 2.5 秒確認，
      //   且該計時器只在尚未排程時建立（??=），永遠不因新事件重啟，
      //   保證最遲 2.5 秒一定提交，符合需求的 2.5 秒上限。
      //
      // ★ 2026-08-24：「長輩在線」與撥號目標（_elderSocketId）都必須只看
      //   通訊機，監控機不能算——監控機不能接電話，若被當成「在線設備」
      //   選中，_elderSocketId 會指向監控機，通話會打不通（`_elderSocketId`
      //   欄位宣告處已有註記：它是「第一台在線設備」，可能就是監控機）。
      //   `monitors` 本身（監視機卡片自己的在線燈）維持看全部設備不變，
      //   「這台監視機是否在線」與「長輩本人是否可被聯繫到」是兩個不同的
      //   問題，這裡只改後者。
      //   `deviceMode` 缺漏時視為通訊機：本專案裝置只有 comm／monitor 兩種
      //   模式，monitor 一律由後端／前端顯式標記（見
      //   CLAUDE_call-monitor.md §6.1）；沒有標記出來的裝置在舊資料與現行
      //   程式碼路徑裡實際上都是通訊機，寧可誤判成「可撥打」（頂多打不通，
      //   行為與修復前相同）也不要誤判成「不能撥打」（會讓正常通訊機顯示
      //   離線，是更嚴重的迴歸）。
      final List<dynamic> commDevices =
          devices.where((d) => d is Map && d['deviceMode'] != 'monitor').toList();
      final bool online = commDevices.any(_isDeviceOnline);
      final List<dynamic> monitors =
          devices.where((d) => d is Map && d['deviceMode'] == 'monitor').toList();
      final onlineDevice = commDevices.firstWhere(_isDeviceOnline, orElse: () => {});
      final String? onlineSid =
          (onlineDevice is Map && onlineDevice.isNotEmpty) ? onlineDevice['id'] as String? : null;

      if (online) {
        // 離線→上線：立即生效，不等待（延遲只剩一次輪詢往返）
        _offlineConfirmTimer?.cancel();
        _offlineConfirmTimer = null;
        setState(() {
          _isElderOnline = true;
          _elderSocketId = onlineSid;
          _monitorDevices = monitors;
        });
        _maybeFetchInitialZone();
        return;
      }

      // 判定為離線：設備清單仍立即更新（清單本身不需要抖動抑制）
      setState(() => _monitorDevices = monitors);
      _maybeFetchInitialZone();
      if (!_isElderOnline) return; // 本來就離線，無需確認
      _offlineConfirmTimer ??= Timer(const Duration(milliseconds: 2500), () {
        _offlineConfirmTimer = null;
        if (!mounted) return;
        setState(() {
          _isElderOnline = false;
          _elderSocketId = null;
        });
      });
  }

  /// ★ 2026-08-18 IPS prototype：套用 `elder-zone-update` 推播的**唯一**入口。
  /// 比照 `_applyDeviceList` 的隔離規則（Round 25/26 修復過的同一類 bug——
  /// 家屬 socket 收到「別的長輩」的推播）：payload 帶 `elder_id`，只要跟目前
  /// 正在看的長輩不同就整包丟棄，不更動任何既有 state。
  /// ⚠️ 刻意不比對 `device_id`——一位長輩可能綁多台監視機，任一台偵測到
  /// 區域切換都代表長輩「目前」所在位置，故不像 `_monitorDevices` 只認
  /// 第一台，這裡全部接受。
  void _applyZoneUpdate(Map<String, dynamic> payload) {
    final String? currentElderId = _currentElder?.elderId ?? _currentElder?.id.toString();
    final String? payloadElderId = payload['elder_id']?.toString();
    if (currentElderId == null || payloadElderId == null || payloadElderId != currentElderId) {
      debugPrint(
          '🚫 [FamilyMainScreen] 忽略非當前長輩的 zone 推播 (payload elder_id=$payloadElderId, 目前長輩=$currentElderId)');
      return;
    }
    // ★ 2026-09-01（第三十九輪 item 5 前端半邊）：每次推播都重新解析過期
    //   視窗提示。不需要包進下面的 setState——這個值不直接影響 build()，
    //   只被 _expireStaleZonePresenceIfNeeded() 這個計時器回呼讀取。
    _zonePresenceStaleWindow = _resolveStaleWindow(payload);
    setState(() {
      _elderZone = {
        'zone': (payload['to_zone'] ?? 'unknown').toString(),
        'enteredAt': _parseUtcIso(payload['entered_at']) ?? DateTime.now(),
        'updatedAt': DateTime.now(),
        // ★ 2026-08-24（校準功能移除，presence 獨立於具名 zone 運作）：
        //   後端每偵測到一次人（~2 秒/幀）就會推播一次（見
        //   indoor_position.py::process_frame_for_zone），能收到這個事件本身
        //   就代表「剛剛偵測到人」，因此預設 true；仍然讀取 payload 裡的
        //   `present` 欄位（而非直接寫死），只有明確帶 false 時才採信——
        //   為未來若改成也會推播「已離開」事件的情況預留退路，不需要再改
        //   這裡的判斷式。
        'present': payload['present'] != false,
        // ★ 2026-08-24（監控卡片「目前長輩所在此處」高亮）：記錄是哪一台
        //   監視機送出這筆推播。上面的方法註解「刻意不比對 device_id」講的是
        //   要不要用它篩選／丟棄 payload（不篩選，全部接受）；這裡只是存下來
        //   供 UI 顯示哪一張卡片要高亮，兩者不衝突。鍵名見
        //   indoor_position.py::_build_zone_payload 的 'device_id'（字串）。
        'deviceId': payload['device_id']?.toString(),
      };
    });
  }

  /// presence 的用戶端過期視窗——**不再是前端寫死的常數**，改由後端在
  /// `elder-zone-update` 推播（`_applyZoneUpdate`）與 `getCurrentZone` REST
  /// 回應（`_maybeFetchInitialZone`）裡動態指定，前端只保留「payload 沒帶
  /// 該欄位時」的向後相容預設值。實際解析邏輯見 [_resolveStaleWindow]。
  ///
  /// ★ 2026-09-01（第三十九輪 item 5 前端半邊）：後端「在場心跳」的推播
  /// 頻率已依訂閱層級節流（免費 15 秒／黃金 7 秒／鑽石 3 秒，見
  /// `indoor_position.py::_PRESENCE_TIER_INTERVALS_S`）。這個過期視窗若繼續
  /// 寫死 10 秒，免費層級每個節流週期都會有 5 秒被誤判成「已離開」——
  /// 「長輩在此」燈號規律閃爍（長輩本人並未離開）；黃金層級 7 秒雖壓線在
  /// 10 秒內，網路一抖動也會偶爾閃。
  ///
  /// **不採用**前端自己另外維護一份「層級 → 視窗秒數」對照表：節流秒數本來
  /// 就只由後端決定（未來調整定價或節流秒數，只改得動後端那一份），前端
  /// 重複一份必然會再度漂移——這正是這次 bug 的成因，複製第二份只是把同一
  /// 個錯誤犯兩次。改成「後端算好毫秒數直接送過來，前端只負責用、不負責
  /// 算」，讓這個數字只有一個權威來源。
  ///
  /// ⚠️ 截至本輪 `uban-api` 後端變動：`indoor_position.py` 模組 docstring
  /// （2026-09-01 段落）明確記載這個欄位**尚未送出**——節流本身已上線，但
  /// 「把過期視窗一併送給前端」被後端那位代理明確排除在本輪範圍外，回報給
  /// 協調者定奪。因此目前實務上仍會落在下面的 10 秒預設，本輪要修的閃爍
  /// 問題在後端補上這個欄位之前**不會**消失；前端這一半已經就緒，欄位一到
  /// 就會生效，屆時不需要再改這個檔案。
  Duration _zonePresenceStaleWindow = const Duration(seconds: 10);

  /// [_zonePresenceStaleWindow] 沒有任何有效後端提示時的向後相容預設值——
  /// 與變更前的寫死常數同值，確保舊版後端／漏帶欄位的推播行為與修改前
  /// 完全一致（見 [_resolveStaleWindow] 的說明）。
  static const Duration _staleWindowDefault = Duration(seconds: 10);

  /// 過期視窗提示的合理值域（毫秒）。下限 5 秒、上限 120 秒，理由見
  /// [_resolveStaleWindow]。
  static const int _staleWindowHintMinMs = 5000;
  static const int _staleWindowHintMaxMs = 120000;

  /// 從 `elder-zone-update` 推播或 `getCurrentZone` REST 回應解析後端送來的
  /// 過期視窗提示，解出 [_zonePresenceStaleWindow] 這一輪該採用的值。
  ///
  /// 鍵名同時嘗試 `presenceStaleAfterMs`（與後端協調用的暫定名稱，見本輪
  /// 交付說明）與 `presence_stale_after_ms`（這個 payload 其餘欄位——
  /// `from_zone`／`to_zone`／`previous_dwell_seconds`／`device_id`——一律
  /// snake_case，後端若比照既有慣例命名，字面上更可能是這個）；兩者都試，
  /// 避免日後補欄位時只是猜錯命名慣例又讓這個機制多空轉一輪。
  ///
  /// 防呆（依需求）：
  ///   - 欄位缺漏、型別無法解析成數字 → 退回 10 秒預設。
  ///   - 數值小於下限 5 秒 → 視為不可信，同樣退回 10 秒預設，不直接採信。
  ///   - 數值大於上限 120 秒 → 鉗制到 120 秒，而不是整個丟棄——避免異常大
  ///     的值讓「長輩在此」燈號永遠不會過期，但仍承認後端確實想要一個比
  ///     預設更寬鬆的視窗。
  static Duration _resolveStaleWindow(Map<String, dynamic> payload) {
    final dynamic raw =
        payload['presenceStaleAfterMs'] ?? payload['presence_stale_after_ms'];
    if (raw == null) return _staleWindowDefault;
    final num? ms = num.tryParse(raw.toString());
    if (ms == null || ms < _staleWindowHintMinMs) return _staleWindowDefault;
    if (ms > _staleWindowHintMaxMs) {
      return const Duration(milliseconds: _staleWindowHintMaxMs);
    }
    return Duration(milliseconds: ms.round());
  }

  /// ★ 2026-08-24：`_elderZone` 的過期檢查——後端只在「偵測到人」時才會
  /// 推播或回應 `present: true`，長輩離開鏡頭後不會有主動的「離開」事件，
  /// 若不主動判斷逾時，`_elderZone` 會永遠停在最後一次「在」的結果（本輪
  /// 要修的 bug：監視機範圍內沒人，清單卻一直顯示「長輩在此」）。
  ///
  /// 呼叫時機刻意搭上既有的 `_deviceRefreshTimer`（2.5 秒，見
  /// `_startDeviceRefreshTimer`），且**不依賴該次輪詢是否成功送出**——即使
  /// socket 斷線，也要繼續判斷 `_elderZone` 是否已經該過期，網路異常正是
  /// 「不該再相信舊資料」最典型的情況，見該計時器 callback 內的呼叫點。
  /// 不另開專屬計時器，避免多一個要在 `dispose()` 記得取消的物件。
  void _expireStaleZonePresenceIfNeeded() {
    if (!mounted) return;
    final Map<String, dynamic>? zone = _elderZone;
    if (zone == null || zone['present'] != true) return;
    final DateTime? updatedAt = zone['updatedAt'] as DateTime?;
    if (updatedAt == null) return;
    if (DateTime.now().difference(updatedAt) <= _zonePresenceStaleWindow) return;
    setState(() {
      _elderZone = {..._elderZone!, 'present': false};
    });
  }

  /// ★ 2026-08-18 IPS prototype：監視機清單確定後，補一次 zone 初始值。
  /// 為什麼需要它：`elder-zone-update` 只在後端偵測到人的那一刻才推播（見
  /// `indoor_position.py::process_frame_for_zone`），App 剛開啟、還沒收過
  /// 任何一次推播時 UI 會在切分頁前一直空白，必須主動查一次目前快照才知道
  /// 「現在」是不是在場——這正是 REST 與 Socket 兩條路徑都要走
  /// `ZoneTracker.snapshot()` 的過期判定的原因（見 `_zoneStateFromRest` 與
  /// `_applyZoneUpdate` 的說明）。
  /// 用 `_zoneFetchKey` 去重，避免每次 2.5s socket 輪詢／10s HTTP 交叉驗證
  /// 重新套用設備清單時都重打一次 API（清單內容沒變就不重查）。
  void _maybeFetchInitialZone() {
    final String? elderIdStr = _currentElder?.elderId ?? _currentElder?.id.toString();
    if (elderIdStr == null) return;

    // ★ 依需求：從 `_monitorDevices` 取第一台監視機的 deviceId，沒有就顯示
    //   「尚未綁定監視機」狀態、不呼叫 API。`_monitorDevices` 在 `_applyDeviceList`
    //   已經是「只含 deviceMode=='monitor'」的子集，這裡直接取第一筆即可。
    final dynamic monitor = _monitorDevices.isNotEmpty ? _monitorDevices.first : null;
    final int? deviceId = monitor is Map
        ? int.tryParse((monitor['deviceId'] ?? monitor['id'])?.toString() ?? '')
        : null;
    final String key = '$elderIdStr:${deviceId ?? 'none'}';

    if (deviceId == null) {
      if (key != _zoneFetchKey) {
        _zoneFetchKey = key;
        if (mounted) setState(() => _elderZone = null);
      }
      return;
    }

    if (key == _zoneFetchKey || _zoneFetchInFlight) return;
    _zoneFetchInFlight = true;

    final int userId = widget.userId;
    ApiService.getCurrentZone(elderIdStr, userId: userId, deviceId: deviceId).then((data) {
      _zoneFetchInFlight = false;
      if (!mounted) return;
      // 競態防護：回應回來時長輩或監視機組合可能已經變了（切長輩／設備清單
      // 改變），比照 `_refreshMonitorDevicesViaHttp` 的作法，不是目前這組就丟棄。
      final String? nowElderIdStr = _currentElder?.elderId ?? _currentElder?.id.toString();
      if ('$nowElderIdStr:$deviceId' != key) return;
      if (data.isEmpty) return; // 查詢失敗：維持現狀，不覆蓋既有畫面，讓下一輪重試
      _zoneFetchKey = key;
      // ★ 2026-09-01（第三十九輪 item 5 前端半邊，後端補完後更新）：REST
      //   路徑的 `getCurrentZone`（routers/ips.py）現在也會送
      //   `presence_stale_after_ms`——與 Socket `elder-zone-update` payload
      //   同一套計算（見 `indoor_position.py::resolve_presence_stale_after_ms`）。
      //   這裡解析它是為了讓 App 冷啟動、還沒收到任何 Socket 推播前的第一次
      //   畫面就拿到正確的過期視窗，不必等第一次推播才校正；欄位缺漏時仍照
      //   [_resolveStaleWindow] 的規則退回 10 秒預設。
      _zonePresenceStaleWindow = _resolveStaleWindow(data);
      // ★ 2026-08-24：後端直接給 `present` 權威欄位（已內含過期判定，見
      //   indoor_position.py::ZoneTracker.snapshot），不再需要前端自己用
      //   `last_seen` 反推——只要成功回應（非空 Map）就正規化套用。
      setState(() {
        _elderZone = _zoneStateFromRest(data);
      });
    }).catchError((_) {
      _zoneFetchInFlight = false;
    });
  }

  /// ★ 2026-08-18 IPS prototype：把後端 ISO 字串（Python
  /// `datetime.utcnow().isoformat()`，不含時區尾碼）安全解析成本地 DateTime。
  /// Dart 的 `DateTime.parse` 對「沒有時區資訊」的字串會直接當成本地時間套用
  /// 數字，不補 'Z' 會整段解析成錯誤時區。解析失敗一律回傳 null，不拋例外。
  static DateTime? _parseUtcIso(dynamic raw) {
    if (raw == null) return null;
    final String str = raw.toString();
    if (str.isEmpty) return null;
    try {
      final bool hasTz = str.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(str);
      return DateTime.parse(hasTz ? str : '${str}Z').toLocal();
    } catch (_) {
      return null;
    }
  }

  /// ★ 2026-08-18 IPS prototype：REST `getCurrentZone` 回傳形狀
  /// `{zone, present, dwell_seconds, last_seen, calibrated, elder_id,
  /// device_id}` → 正規化狀態。
  /// 後端只給 `dwell_seconds`（查詢當下已停留秒數），沒有 `entered_at`；用
  /// 「現在－dwell_seconds」反推進入時間，讓卡片用同一套邏輯估算停留時長，
  /// 與 socket 推播（有真正的 `entered_at`）共用同一份顯示邏輯。
  /// ★ 2026-08-24：`present` 才是權威欄位（後端 `ZoneTracker.snapshot()` 已
  /// 內含過期判定，見 `indoor_position.py::PRESENCE_STALE_SECONDS`），直接
  /// 透傳，不再讀取／使用 `calibrated`（校準功能移除後已失去意義，見
  /// `_elderZone` 欄位宣告處的說明）。REST 是「查詢當下即時算」，這裡故意
  /// 用嚴格的 `== true`（沒有欄位或非 true 一律當作不在場），不像 Socket
  /// 推播路徑（`_applyZoneUpdate`）預設 true——兩者語意不同：能收到 Socket
  /// 推播本身就代表剛偵測到人，但 REST 回應必須誠實反映「現在」的狀態。
  /// `device_id`（2026-08-24 起一併透傳為 `deviceId`）：呼叫端固定查第一台
  /// 監視機（見 `_maybeFetchInitialZone`），這裡的值必然等於該查詢用的
  /// deviceId，只是換一個型別（String?）供監控卡片比對高亮用。
  static Map<String, dynamic> _zoneStateFromRest(Map<String, dynamic> data) {
    final num dwellSeconds = num.tryParse('${data['dwell_seconds'] ?? 0}') ?? 0;
    return {
      'zone': (data['zone'] ?? 'unknown').toString(),
      'enteredAt': DateTime.now().subtract(Duration(seconds: dwellSeconds.round())),
      'updatedAt': _parseUtcIso(data['last_seen']) ?? DateTime.now(),
      'present': data['present'] == true,
      'deviceId': data['device_id']?.toString(),
    };
  }

  /// ★ 2026-08-10 第十九輪（需求 5 / A4）：每 10 秒以 HTTP 交叉驗證設備清單。
  ///
  /// 為什麼需要它：Socket 的 `elder-devices-update` 只送給**房內**的 socket，
  /// 家屬端 socket 一斷（切網路、進背景被凍結、後端重啟）清單就永遠停在舊值。
  /// 這條 HTTP 路徑不依賴 socket，且呼叫的是後端同一支 `_get_elder_devices_list()`，
  /// 所以能補上剛配對完、尚未 join 成功的離線監視機（後端階段 0）。
  ///
  /// 失敗一律安靜略過——這是補強路徑，不能因為後端暫時不可用就把清單清空。
  Future<void> _refreshMonitorDevicesViaHttp() async {
    final elder = _currentElder;
    final userId = widget.userId;
    if (elder == null) return;
    final String elderIdStr = elder.elderId ?? elder.id.toString();
    try {
      final devices = await ApiService.fetchMonitorDevices(
        elderId: elderIdStr,
        userId: userId,
      );
      if (!mounted) return;
      // 切換長輩的競態：回應回來時已經不是同一位長輩就丟棄
      final current = _currentElder;
      if (current == null ||
          (current.elderId ?? current.id.toString()) != elderIdStr) {
        return;
      }
      debugPrint('🔁 [Device HTTP] 交叉驗證取得 ${devices.length} 台設備 (elder_id=$elderIdStr)');
      _applyDeviceList(devices);
    } catch (e) {
      debugPrint('⚠️ [Device HTTP] 交叉驗證失敗（略過）: $e');
    }
  }

  /// ★ 2026-08-10 第十九輪（需求 4）：一般視訊通話的**單一**發起點。
  ///
  /// 與 `family_interaction_tab.dart` 的「一般視訊通話」使用完全相同的參數
  /// （`comm_elder_<rawId>` + `targetSocketId` + `autoStart` + 非緊急）。
  /// 首頁分頁的「開始撥號」透過 `FamilyHomeTab.onStartVideoCall` 注入這裡，
  /// 避免各分頁各自拼一份房號／目標邏輯而互相漂移。
  void _startNormalVideoCall() {
    final elder = _currentElder;
    if (elder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未選擇長輩，無法撥打')),
      );
      return;
    }
    final String rawId = elder.elderId ?? elder.id.toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          roomId: 'comm_elder_$rawId',
          targetSocketId: null, // ★ 不綁死單一 socket ID，由後端完整廣播給線上長輩 Socket 與所有長輩 FCM Token
          autoStart: true,
          isEmergency: false,
        ),
      ),
    );
  }

  /// ★ B1（2026-08-04）：'elder-unbound' 事件的實際處理邏輯，從原本直接掛在
  /// `_signaling.socket?.on(...)` 的 inline callback 原封不動抽出，供
  /// `_registerElderUnboundListener()` 在 socket 確定存在時掛上。
  void _handleElderUnbound(dynamic data) {
    if (!mounted) return;
    try {
      final unboundElderId = data is Map ? (data['elderId'] ?? data['elder_id'])?.toString() : null;
      debugPrint('🔓 [FamilyMainScreen] 收到 elder-unbound: elderId=$unboundElderId');
      if (unboundElderId == null) return;

      // 比對當前選中的長輩
      final currentElderId = _currentElder?.elderId ?? _currentElder?.id.toString();
      final isCurrentElder = unboundElderId == currentElderId;

      // 從列表中移除
      setState(() {
        _elders.removeWhere((e) {
          final eId = e.elderId ?? e.id.toString();
          return eId == unboundElderId;
        });
        if (isCurrentElder) {
          _currentElder = null;
          _isElderOnline = false;
          _elderSocketId = null;
        }
      });

      // 同步 ElderManager
      ElderManager().removeElderLocally(unboundElderId);

      // 若列表為空 → 導航至 Onboarding；否則若目前長輩被解綁 → 自動選第一個
      if (_elders.isEmpty) {
        debugPrint('🔓 [FamilyMainScreen] 所有長輩已解綁，導航至 Onboarding');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => FamilyOnboardingScreen(userId: widget.userId, userName: widget.userName)),
            (route) => false,
          );
        }
      } else if (isCurrentElder) {
        debugPrint('🔓 [FamilyMainScreen] 當前長輩被解綁，自動切換至第一個');
        _switchElder(_elders.first);
      }
    } catch (e) {
      debugPrint('❌ [FamilyMainScreen] elder-unbound 處理失敗: $e');
    }
  }

  /// ★ B1（2026-08-04）：冪等註冊 'elder-unbound' 監聽器。socket 尚未建立時安全跳過，
  /// 呼叫端（_setupSignalingCallbacks / _loadElderAndConnect）需在 socket 建立後再呼叫一次，
  /// 才能保證監聽器實際掛上（見上方兩處呼叫點的註解）。
  void _registerElderUnboundListener() {
    final s = _signaling.socket;
    if (s == null) {
      debugPrint('⚠️ [FamilyMainScreen] socket 尚未建立，elder-unbound 監聽器延後註冊');
      return;
    }
    s.off('elder-unbound'); // 冪等：避免重連時重複註冊造成同一事件觸發多次
    s.on('elder-unbound', _handleElderUnbound);
    debugPrint('✅ [FamilyMainScreen] elder-unbound 監聽器已註冊');
  }

  /// ★ 2026-08-05 第十七輪：`isOnline` 可能是 bool / int / String（不同來源序列化不同），
  ///   只認 `== true` 曾造成 2026-07-16 的裝置狀態迴歸，這裡一律容錯解析。
  static bool _isDeviceOnline(dynamic d) {
    final v = (d is Map) ? d['isOnline'] : null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return false;
  }

  /// ★ 移植自 family_dashboard_view.dart 第 145-160 行：處理 CCTV 跌倒警報（YOLO）。
  /// 從原本直接掛在 `_signaling.socket?.on(...)` 的 inline callback 抽出，
  /// 供 `_registerCctvAlertListener()` 在 socket 確定存在時掛上（比照 `_handleElderUnbound`）。
  void _handleCctvAlert(dynamic data) {
    if (!mounted) return;
    try {
      final alertId = data is Map ? int.tryParse((data['alert_id'] ?? data['alertId'])?.toString() ?? '') : null;
      if (alertId == null) return;
      // ★ 2026-08-05 第十七輪：見 `_knownAlertKeys` 的說明——alert_id 會被後端重複沿用，
      //   必須把 timestamp 一併納入去重鍵。timestamp 缺漏時退回只用 alert_id：
      //   寧可漏掉一次重複顯示，也不要因為缺欄位而讓每一則警報都重複彈窗。
      final String ts =
          (data is Map ? (data['timestamp'] ?? data['ts']) : null)?.toString() ?? '';
      final String alertKey = ts.isEmpty ? 'a$alertId' : 'a$alertId@$ts';
      if (_knownAlertKeys.contains(alertKey)) return;
      _knownAlertKeys.add(alertKey);
      // 長時間執行時避免無限增長（Set 為 LinkedHashSet，first 即最早插入的那筆）
      if (_knownAlertKeys.length > 100) {
        _knownAlertKeys.remove(_knownAlertKeys.first);
      }
      final newAlert = Map<String, dynamic>.from(data is Map ? data : {});
      setState(() {
        _activeAlerts.insert(0, newAlert);
        if (_activeAlerts.length > 20) _activeAlerts.removeLast();
      });
      debugPrint('🚨 [FamilyMainScreen] 收到 CCTV 警報: ${newAlert['alert_type']} elder=${newAlert['elder_id']}');
      // ★ 2026-08-05 第十七輪：原本到上一行就結束（只有設備卡片變紅），
      //   使用者沒盯著畫面就完全不會知道長輩跌倒了。需求要求「強制開啟螢幕 +
      //   彈出通知 + 朗讀」，故追加 _presentCctvAlert（原本的清單插入與去重完整保留）。
      _presentCctvAlert(newAlert);
    } catch (e) {
      debugPrint('❌ [FamilyMainScreen] cctv-alert 處理失敗: $e');
    }
  }

  /// ★ 2026-08-05 第十七輪：把警報型別轉成人看得懂的中文。
  /// YOLO 會送出四種：`fall` / `crawl` / `lying_down` / `prolonged_inactivity`，
  /// 只有第一種代表「跌倒」，其餘三種不可混為一談（實測時最常搞混的就是這點）。
  static String _alertTypeLabel(String type) {
    switch (type) {
      case 'fall':
        return '跌倒';
      case 'crawl':
        return '疑似爬行';
      case 'lying_down':
        return '長時間躺臥';
      case 'prolonged_inactivity':
        return '長時間無活動';
      default:
        return '異常狀況';
    }
  }

  /// 開啟指定監視機的 CCTV 單向檢視（G55 兩個 `monitorViewOnly: true` 建構點之一）。
  ///
  /// ★ 2026-08-31 第三十八輪：抽成共用方法，供兩條入口使用，避免各拼一份而漂移——
  ///   1. `_presentCctvAlert()` 的「查看監視畫面」鍵（跌倒警報彈窗）
  ///   2. `FamilyHomeTab.onOpenMonitorView`（首頁「最新警示」清單的 CCTV／跌倒項目）
  ///   第 2 條在此之前**從未被接上**：`FamilyHomeTab` 宣告了該回呼、消費端也寫好了，
  ///   但本檔建構 `FamilyHomeTab` 時沒傳，於是那類警示永遠不可點擊。
  ///
  /// [deviceIdStr]：該監視機的 `deviceId`／`id`。
  /// [elderIdOverride]：警報彈窗傳入警報自己的 `elder_id`；省略時用目前選中的長輩。
  /// [onReturn]：監控畫面關閉後回呼（彈窗用它清掉該裝置的警報高亮）。
  void _openMonitorViewForDevice(
    String deviceIdStr, {
    String? elderIdOverride,
    VoidCallback? onReturn,
  }) {
    // 🚨 一定要用該裝置自己的 `id`，不可用 `_elderSocketId`（那是「第一台在線設備」，
    //    很可能是通訊機而不是這台監視機，送過去會連到錯的裝置）。
    final dynamic device = _monitorDevices.firstWhere(
      (d) => d is Map && (d['deviceId'] ?? d['id'])?.toString() == deviceIdStr,
      orElse: () => null,
    );
    final String viewSocketId =
        (device is Map ? (device['id'] as String? ?? '') : '');
    // 解析不出線上的來源設備就直接返回——寧可沒反應，也不要帶著空的
    // targetSocketId 進房而卡在「連線中」（與彈窗的 canView 同一判準）。
    if (viewSocketId.isEmpty || !_isDeviceOnline(device)) return;
    final String deviceName =
        (device is Map ? (device['deviceName'] ?? '監視機') : '監視機').toString();
    final String rawElderId =
        (elderIdOverride != null && elderIdOverride.isNotEmpty)
            ? elderIdOverride
            : (_currentElder?.elderId ?? _currentElder?.id.toString() ?? '');
    if (rawElderId.isEmpty) return;

    // ★ 第四十輪（item 2）：記錄目前正在看哪一台，供 _presentCctvAlert() 判斷是否
    //   要隱藏「查看監視畫面」鍵——已經在看同一台的即時畫面，再給一顆鍵是多餘的干擾。
    _viewingMonitorDeviceId = deviceIdStr;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          roomId: 'monitor_elder_$rawElderId',
          targetSocketId: viewSocketId,
          isEmergency: true,
          autoStart: true,
          // 監控檢視一律用 pop() 返回本頁
          returnByPop: true,
          // ★ 第十九輪（需求 2）：單向監控檢視（G55）
          monitorViewOnly: true,
          // 傳裝置名給 Signaling.onMonitorRemoved 精準比對，避免刪除
          // 同一長輩底下「另一台」監視機時誤關本畫面。
          monitorDeviceName: deviceName,
        ),
      ),
    ).then((_) {
      // 離開監控檢視，清除「正在觀看」標記，讓該裝置之後的警報恢復顯示查看鍵。
      _viewingMonitorDeviceId = null;
      if (mounted) onReturn?.call();
    });
  }

  /// ★ 2026-08-05 第十七輪：家屬端在**前景**時的跌倒警報呈現。
  /// 需求的三件事分別由三個機制負責，任一項失敗都不得影響其餘兩項：
  ///   - 螢幕      → `WakelockPlus`，**僅在 App 本來就在前景時**維持亮著（見下方
  ///     `_lifecycleState` 判斷）；`CctvAlertNotification` 負責鎖屏可見＋鬧鐘級
  ///     音量的高優先級通知。★ 2026-08-23（新鐵律）：`CctvAlertNotification` 的
  ///     `fullScreenIntent` 已改為 `false`——**家屬端不再強制把 App 拉到鎖定
  ///     畫面之上**，是否查看交還使用者自行點擊通知決定；緊急程度不變（鬧鐘
  ///     音量／繞過勿擾／鎖屏可見皆保留）。強制開啟只留給長輩端使用。
  ///   - 彈出通知  → 本方法的 `AlertDialog`（APP 已在前景時系統通知容易被忽略）
  ///   - 朗讀      → `FlutterTts`
  /// APP 在背景／被殺死時走的是 `main.dart` 的 FCM `cctv-alert` 分支，不會經過這裡。
  Future<void> _presentCctvAlert(Map<String, dynamic> alert) async {
    final String alertType =
        (alert['alert_type'] ?? alert['alertType'] ?? 'fall').toString();
    final String typeLabel = _alertTypeLabel(alertType);

    // 1) 保持螢幕亮著——僅限 App 本來就在前景時（見 _lifecycleState 欄位說明）。
    //   背景時開啟對「目前看不見的視窗」沒有實際點亮效果，只會讓 wakelock
    //   一直掛著，直到使用者切回前景、彈窗關閉的 .then() 才 disable。
    if (_lifecycleState == AppLifecycleState.resumed) {
      try {
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint('⚠️ [FamilyMainScreen] WakelockPlus.enable 失敗: $e');
      }
    }

    // 2) 系統通知（★ 2026-08-23 起不再用 fullScreenIntent 強制點亮螢幕/拉起
    //    App；鎖屏可見＋鬧鐘級音量仍會讓通知在螢幕關閉時顯眼地響，由使用者
    //    自行點開，見 CctvAlertNotification.show 內的說明）
    try {
      await CctvAlertNotification.show({
        'elderId': (alert['elder_id'] ?? alert['elderId'] ?? '').toString(),
        // ★ 2026-08-20：後端 Socket 'cctv-alert' payload 現會帶 elder_name
        //   （見 yolo_alert_dispatcher.py::_build_push_payload），讓通知文案顯示姓名
        //   而非 elder_id。這裡是 APP 在前景時的主要路徑（見本方法上方註解——背景／
        //   被殺死時走的是 main.dart 的 FCM 分支，不經過這裡），若漏接就會讓「前景時
        //   仍顯示 elder_id」的舊行為在這條路徑上復發。刻意不用 `?? ''` 兜底：
        //   缺欄位時要讓值維持 null，才能讓 CctvAlertNotification.show() 內建的
        //   elderName → elderId → 「長輩」三層退回鏈正常運作（空字串會被 `??`
        //   當成「有值」而卡住，跳過 elderId 那一層退回）。
        'elderName': (alert['elder_name'] ?? alert['elderName'])?.toString(),
        'alertId': (alert['alert_id'] ?? alert['alertId'] ?? '').toString(),
        'alertType': alertType,
      });
    } catch (e) {
      debugPrint('⚠️ [FamilyMainScreen] 跌倒警報通知發送失敗: $e');
    }

    // 3) 朗讀
    try {
      _alertTts ??= FlutterTts();
      await _alertTts!.setLanguage('zh-TW');
      await _alertTts!.setSpeechRate(0.45);
      await _alertTts!.speak('注意，偵測到長輩可能$typeLabel，請立即查看監視畫面');
    } catch (e) {
      debugPrint('⚠️ [FamilyMainScreen] 跌倒警報朗讀失敗: $e');
    }

    // 4) 彈窗
    if (!mounted || _cctvAlertDialogOpen) return;

    // 由 device_id 反查設備，取得名稱與該台監視機自己的 socketId。
    // 🚨 一定要用該裝置自己的 `id`，不可用 `_elderSocketId`（那是「第一台在線設備」，
    //    很可能是通訊機而不是這台監視機，送過去會連到錯的裝置）。
    final String deviceIdStr =
        (alert['device_id'] ?? alert['deviceId'] ?? '').toString();
    final dynamic device = _monitorDevices.firstWhere(
      (d) =>
          d is Map && (d['deviceId'] ?? d['id'])?.toString() == deviceIdStr,
      orElse: () => null,
    );
    final String deviceName =
        (device is Map ? (device['deviceName'] ?? '監視機') : '監視機').toString();
    final String viewSocketId =
        (device is Map ? (device['id'] as String? ?? '') : '');
    // 解析不出線上的來源設備就不給「查看監視畫面」鍵——寧可少一個功能鍵，
    // 也不要帶著空的 targetSocketId 進房而卡在連線中。
    // ★ 第四十輪（item 2）：若已經在觀看「同一台」監視機的 CCTV 即時畫面，也不給這顆
    //   鍵——使用者已經看到即時狀況了，再彈一顆「查看監視畫面」只是多餘的干擾。只比對
    //   同一台，別台監視機的警報仍要給鍵（不影響通知／朗讀／卡片高亮，只動這顆按鈕）。
    final bool alreadyViewingThisDevice =
        deviceIdStr.isNotEmpty && _viewingMonitorDeviceId == deviceIdStr;
    final bool canView = viewSocketId.isNotEmpty &&
        _isDeviceOnline(device) &&
        !alreadyViewingThisDevice;
    final String rawElderId =
        (alert['elder_id'] ?? alert['elderId'] ?? '').toString();

    final double? conf = double.tryParse(
        (alert['confidence'] ?? '').toString());
    final String confText =
        conf == null ? '' : '信心度 ${(conf * 100).toStringAsFixed(0)}%';

    _cctvAlertDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFB91C1C), size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '偵測到$typeLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('監視機：$deviceName'),
              if (confText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(confText, style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 8),
              const Text(
                '請立即查看監視畫面確認長輩狀況。',
                style: TextStyle(color: Colors.black87),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // ★ 點擊「我知道了」：解除警報狀態，還原介面樣式與動畫
                if (mounted) {
                  setState(() {
                    final String alertDevice = (alert['device_id'] ?? alert['deviceId'])?.toString() ?? '';
                    _activeAlerts.removeWhere((a) =>
                        (a['device_id'] ?? a['deviceId'])?.toString() == alertDevice ||
                        a['alert_id'] == alert['alert_id']);
                  });
                }
              },
              child: const Text('我知道了'),
            ),
            if (canView)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // ★ 2026-08-31 第三十八輪：改呼叫共用方法 _openMonitorViewForDevice，
                  //   與 FamilyHomeTab.onOpenMonitorView 共用同一份 VideoCallScreen
                  //   建構參數（G55），行為與抽出前逐字相同。
                  _openMonitorViewForDevice(
                    deviceIdStr,
                    elderIdOverride: rawElderId,
                    onReturn: () {
                      // ★ 2026-08-16（需求 2）：查看完監視畫面返回後，將該警報移出 _activeAlerts，將遠端監控卡片動畫與紅框還原正常
                      setState(() {
                        final String alertDevice = (alert['device_id'] ?? alert['deviceId'])?.toString() ?? '';
                        _activeAlerts.removeWhere((a) =>
                            (a['device_id'] ?? a['deviceId'])?.toString() == alertDevice ||
                            a['alert_id'] == alert['alert_id']);
                      });
                    },
                  );
                },
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('查看監視畫面'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        );
      },
    ).then((_) async {
      _cctvAlertDialogOpen = false;
      try {
        await WakelockPlus.disable();
      } catch (e) {
        debugPrint('⚠️ [FamilyMainScreen] WakelockPlus.disable 失敗: $e');
      }
      try {
        await _alertTts?.stop();
      } catch (e) {
        debugPrint('⚠️ [FamilyMainScreen] TTS stop 失敗: $e');
      }
      try {
        await CctvAlertNotification.cancel();
      } catch (e) {
        debugPrint('⚠️ [FamilyMainScreen] 取消警報通知失敗: $e');
      }
    });
  }

  /// ★ 冪等註冊 'cctv-alert' 監聽器。socket 尚未建立時安全跳過，
  /// 呼叫端（_setupSignalingCallbacks / _loadElderAndConnect）需在 socket 建立後再呼叫一次，
  /// 註冊方式完全比照 `_registerElderUnboundListener()`。
  void _registerCctvAlertListener() {
    final s = _signaling.socket;
    if (s == null) {
      debugPrint('⚠️ [FamilyMainScreen] socket 尚未建立，cctv-alert 監聽器延後註冊');
      return;
    }
    s.off('cctv-alert'); // 冪等：避免重連時重複註冊造成同一事件觸發多次
    s.on('cctv-alert', _handleCctvAlert);
    debugPrint('✅ [FamilyMainScreen] cctv-alert 監聽器已註冊');
  }

  /// ★ 移植自 family_dashboard_view.dart 第 396-409 行（原名 _loadTier）：
  /// 載入使用者目前訂閱層級，供監控區塊的訂閱徽章與設備上限顯示。
  Future<void> _loadSubscriptionTier() async {
    try {
      final data = await ApiService.getSubscriptionTier(widget.userId);
      if (data['tier_level'] != null && mounted) {
        setState(() {
          _tierLevel = (data['tier_level'] ?? 'free').toString();
          _tierDisplayName = (data['tier_display_name'] ?? '一般會員').toString();
          _devicesMax = (data['devices_max'] ?? 2) as int;
        });

        // ★ 2026-08-04 第 4 項：訂閱到期後方案會退回免費層（上限 2 台），
        //   原本合法的 3～5 台監視機就變成超量。此時必須讓使用者二選一：
        //   繼續訂閱，或刪掉多出來的監視機。
        //   後端 `over_limit` 已是「逐位長輩比對 devices_in_use > devices_max」的結果，
        //   前端不重算，避免兩邊判準不一致。
        final overLimit = data['over_limit'] == true;
        if (overLimit && !_overLimitDialogShown) {
          _overLimitDialogShown = true;
          // 用 postFrameCallback：此時仍在 setState 的建置流程中，直接 showDialog 會拋例外。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showSubscriptionOverLimitDialog(
              elders: (data['elders'] as List?) ?? const [],
              endDate: data['end_date']?.toString(),
              totalDevicesInUse: (data['total_devices_in_use'] ?? 0) is int
                  ? data['total_devices_in_use'] as int
                  : int.tryParse('${data['total_devices_in_use']}') ?? 0,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FamilyMainScreen] 載入訂閱層級失敗: $e');
    }
  }

  /// ★ 2026-08-04 第 4 項：監視機超過方案上限時的二選一彈窗。
  /// `barrierDismissible: false` —— 這是需要使用者做決定的狀態，
  /// 但仍保留「稍後再說」出口，不可把人鎖死在彈窗裡。
  void _showSubscriptionOverLimitDialog({
    required List<dynamic> elders,
    String? endDate,
    required int totalDevicesInUse,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('監視機數量超過方案上限')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('目前方案：$_tierDisplayName（每位長輩上限 $_devicesMax 台）'),
            if (endDate != null && endDate.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('訂閱到期日：$endDate',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 4),
            Text('目前使用中：共 $totalDevicesInUse 台',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            // 逐位長輩列出超量狀況，讓使用者知道要從哪一位長輩底下刪除
            ...elders.where((e) => e['over_limit'] == true).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${e['elder_name'] ?? e['elder_id']}：'
                      '${e['devices_in_use']} / ${e['devices_max']} 台',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            const Text(
              '請選擇繼續訂閱以保留全部監視機，或刪除部分監視機以符合目前方案。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('稍後再說', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showDeleteMonitorDeviceDialog();
            },
            child: Text('刪除部分監視機',
                style: TextStyle(color: Colors.red.shade700)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FamilySubscriptionScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF59B294),
              foregroundColor: Colors.white,
            ),
            child: const Text('繼續訂閱'),
          ),
        ],
      ),
    );
  }

  /// ★ 2026-08-04 第 4 項：刪除監視機的挑選介面。
  /// 只列出「目前關照中的這位長輩」底下的監視機——Socket 的
  /// `elder-devices-update` 本來就只推送當前長輩的設備清單，
  /// 硬要跨長輩列出會需要另一支 API，且使用者也必須先切換長輩才看得到畫面。
  void _showDeleteMonitorDeviceDialog() {
    final elder = _currentElder;
    if (elder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要管理的長輩')),
      );
      return;
    }
    final String rawElderId = elder.elderId ?? elder.id.toString();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('刪除監視機（${elder.displayName}）'),
          content: SizedBox(
            width: double.maxFinite,
            child: _monitorDevices.isEmpty
                ? const Text('這位長輩目前沒有連接任何監視機設備')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _monitorDevices.length,
                    itemBuilder: (_, index) {
                      final device = _monitorDevices[index];
                      final name =
                          (device['deviceName'] ?? 'Unnamed').toString();
                      final isOnline = device['isOnline'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.videocam_rounded,
                          color: isOnline ? const Color(0xFF59B294) : Colors.grey,
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 15)),
                        subtitle: Text(isOnline ? '線上' : '離線',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red.shade600),
                          onPressed: () async {
                            final confirmed = await _confirmDeleteDevice(name);
                            if (confirmed != true) return;
                            // ★ 2026-08-26：補上 `userId`。後端
                            //   `routers/pairing.py::delete_monitor_device` 在
                            //   `user_id is None` 時直接回 404（見 G45／§3.8）——
                            //   缺這個參數會讓這顆刪除鍵每次都必然失敗。
                            //   `widget.userId` 與 `family_interaction_tab.dart`
                            //   `_showDeleteMonitorDeviceDialog` 能成功刪除時用的是
                            //   同一顆家屬 user_id，來源相同（`FamilyMainScreen`
                            //   建構子的 `required this.userId`）。
                            final ok = await ApiService.deleteMonitorDevice(
                              elderId: rawElderId,
                              deviceName: name,
                              userId: widget.userId,
                            );
                            if (!mounted) return;
                            if (ok) {
                              // 後端刪除後會廣播 elder-devices-update，
                              // _monitorDevices 會自動更新；這裡同步移除以便彈窗即時反映。
                              setState(() => _monitorDevices.removeWhere(
                                  (d) => d['deviceName'] == name));
                              setDialogState(() {});
                              await _loadSubscriptionTier();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('刪除失敗，請稍後再試')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteDevice(String deviceName) {
    return showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要移除監視機「$deviceName」嗎？\n該設備將被登出並停止推送畫面。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  /// ★ 2026-08-24（首頁「最新警示」滑動關閉，父層一半）：
  /// `FamilyHomeTab.onAlertItemDismissed` 的實作——把該複合鍵加入
  /// `_dismissedAlertKeys`（欄位宣告與完整理由見上方 `_activeAlerts` 附近）
  /// 並 `setState`，讓 `family_home_tab.dart:3009` 的 `.where(...)` 在下一次
  /// build 立即排除該筆；之後每 2.5 秒的裝置／警報輪詢觸發的重建也會沿用
  /// 同一份已更新的集合，不會讓滑掉的警示在下一輪輪詢又跳回來。
  void _handleAlertItemDismissed(String itemId) {
    if (!mounted) return;
    setState(() {
      _dismissedAlertKeys.add(itemId);
    });
  }

  Future<void> _switchElder(Elder elder) async {
    if (elder.id == _currentElder?.id) return;
    
    debugPrint('🔄 切換關照長輩至: ${elder.displayName} (ID: ${elder.id})');
    
    // 1. 掛斷當前通話/釋放連線
    _signaling.hangUp(disposeLocalStream: true);

    // ★ 2026-08-18 需求 8 根因修復：在 _currentElder 被下面的 setState 覆蓋
    //   成新長輩之前，先明確 leave 舊長輩的 comm/monitor 兩個房間。Round 25
    //   只靠 _applyDeviceList 的 elderId 過濾擋掉「切換後還看到舊長輩設備」
    //   的症狀，根因是 socket 從未 leave_room、永遠留在舊房間，後端
    //   _broadcast_elder_devices_update(舊長輩) 因此持續送達本 socket；
    //   這裡才是根治，_applyDeviceList 的 elderId 過濾保留作第二道防線。
    if (_currentElder != null) {
      final oldElderIdStr = _currentElder!.elderId ?? _currentElder!.id.toString();
      _signaling.leaveRoom('comm_elder_$oldElderIdStr');
      // 家屬端可能在查看 CCTV 時額外加入過監控房間；leaveRoom 對「本來就
      // 沒加入」的房間是 no-op（見該方法文件註解），兩間都 leave 才安全。
      _signaling.leaveRoom('monitor_elder_$oldElderIdStr');
    }

    // 2. 更新選中的長輩
    await ElderManager().setCurrentElder(elder);
    
    // 3. 更新本地狀態並重設監視機與警報清單（徹底隔離長輩間的設備與警報）
    setState(() {
      _currentElder = elder;
      _isElderOnline = false;
      _elderSocketId = null;
      _monitorDevices = [];
      _activeAlerts.clear();
      // ★ 2026-08-17 需求 8 修復（Fix B4）：訂閱層級/上限與 CCTV 警報去重集合
      //   先前只清了在線狀態與設備/警報清單，這三個訂閱欄位會殘留舊長輩的值，
      //   直到 _loadSubscriptionTier() resolve 前 UI 會短暫顯示前一位長輩的方案；
      //   _knownAlertKeys 若不清，新長輩的第一筆警報若剛好撞到舊長輩用過的
      //   複合鍵（alert_id 由後端沿用同一序列、非全域唯一）會被誤判為重複而靜默。
      _tierLevel = 'free';
      _tierDisplayName = '一般會員';
      _devicesMax = 2;
      _knownAlertKeys.clear();
      // ★ 2026-08-18 IPS prototype：切長輩時一併清空定位狀態與去重 key，
      //   否則舊長輩的 zone 會在新長輩資料抵達前短暫殘留在畫面上。
      _elderZone = null;
      _zoneFetchKey = null;
      _zoneFetchInFlight = false;
    });
    
    await _loadElderAndConnect();
    await _loadSubscriptionTier();
  }

  Future<void> _refreshElders() async {
    await ElderManager().refresh();
    if (mounted) {
      setState(() {
        _elders = ElderManager().pairedElders;
        _currentElder = ElderManager().currentElder;
      });
      await _loadElderAndConnect();
    }
  }

  void _onPendingCallChanged() {
    _checkPendingAcceptedCall();
  }

  void _checkPendingAcceptedCall() {
    if (pendingAcceptedCall.value != null) {
      final args = pendingAcceptedCall.value!;
      pendingAcceptedCall.value = null; // 處理後清空
      
      final senderId = args['senderId']!;
      final roomId = args['roomId']!;
      final callId = args['callId'];
      // ★ 2026-07-22 第八輪 Fix 3：防角色反轉。senderRole 為發起方角色，
      //   家屬端只應接聽「長輩」發起的來電。若 senderRole == 'family'（自身角色），
      //   代表這是自己這方發出、經 stale state 回流的假來電 → 拒絕並清除，
      //   否則會誤發 sendCallAccept 讓對端反被叫（接收方變發起方）。
      final String? senderRole = args['senderRole'];
      if (senderRole != null && senderRole.isNotEmpty && senderRole == appRole) {
        debugPrint("🚫 [FamilyMainScreen] 忽略角色反轉來電 (senderRole=$senderRole == appRole=$appRole, callId=$callId)");
        return;
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int? expiresAt = int.tryParse('${args['expiresAt'] ?? ''}');
      final int? issuedAt = int.tryParse('${args['issuedAt'] ?? ''}');
      final bool isExpired = (expiresAt != null && now > expiresAt) || (issuedAt != null && (now - issuedAt) > kCallValidityMs);
      if (isExpired) {
        debugPrint("⏰ [FamilyMainScreen] 忽略過期待接聽來電 (callId=$callId)");
        return;
      }
      
      debugPrint("🔔 [FamilyMainScreen] 偵測到背景 CallKit 接聽 (Sender: $senderId, Room: $roomId)");
      
      // 確保視窗已關閉
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.pop(context);
        _isIncomingCallDialogOpen = false;
      }
      
      // 發送接聽信號
      _signaling.sendCallAccept(senderId, callId: callId);
      
      // 跳轉通話畫面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoCallScreen(
            roomId: roomId,
            targetSocketId: senderId,
            isIncomingCall: true,
            callId: callId,
            sendAcceptOnOpen: false,
            isVideoCall: parseIsVideoCall(args['isVideoCall']), // ★ 2026-08-02 第十四輪修正
          ),
        ),
      ).then((_) {
        if (mounted) _setupSignalingCallbacks();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ★ 2026-08-23：記錄目前生命週期狀態，供 _presentCctvAlert 判斷是否要
    //   開 wakelock（見 _lifecycleState 欄位宣告處的說明）。
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _checkPendingAcceptedCall();
    }
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId, {bool isEmergency = false, String? callerName}) {
    if (_isIncomingCallDialogOpen) return; // 防止重複彈窗
    _isIncomingCallDialogOpen = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEmergency ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEmergency ? Icons.warning : Icons.phone_callback,
                  color: isEmergency ? Colors.red : Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  isEmergency ? '🚨 緊急來電' : '📞 長輩來電',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Text(
            // ★ issue 11：優先使用後端解析出的實際來電者名稱，
            //   避免在切換關照長輩後，來電通知仍顯示先前選擇的長輩名稱
            '${callerName ?? _currentElder?.displayName ?? "長輩"} 正在呼叫您！',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: isEmergency ? Colors.red.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                _signaling.sendCallBusy(senderId, callId: callId);
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
              },
              icon: const Icon(Icons.call_end),
              label: const Text('拒接', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
                // 先發送接聽信號
                _signaling.sendCallAccept(senderId, callId: callId);
                // 跳轉到視訊通話頁面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoCallScreen(
                      roomId: roomId,
                      targetSocketId: senderId,
                      isIncomingCall: true,
                      callId: callId,
                      sendAcceptOnOpen: false,
                      isVideoCall: _signaling.isVideoCallFor(callId), // ★ Fix E
                    ),
                  ),
                ).then((_) {
                  if (mounted) _setupSignalingCallbacks();
                });
              },
              icon: const Icon(Icons.videocam),
              label: const Text('接聽', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isIncomingCallDialogOpen = false;
    });
  }

  void _showElderSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    '切換關照對象',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_elders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Text(
                      '目前沒有配對的長輩裝置',
                      style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _elders.length,
                      itemBuilder: (context, index) {
                        final elder = _elders[index];
                        final isSelected = elder.id == _currentElder?.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: elder.gender == 'F'
                                ? const Color(0xFFFDF2F8)
                                : const Color(0xFFF0FDF4),
                            child: Text(
                              elder.genderEmoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          title: Text(
                            elder.displayName,
                            style: GoogleFonts.notoSansTc(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${elder.id} • ${elder.age ?? "?"}歲',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF3B82F6))
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _switchElder(elder);
                          },
                        );
                      },
                    ),
                  ),
                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF3B82F6), size: 20),
                  ),
                  title: Text(
                    '配對新的長輩裝置',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: widget.userName,
                        ),
                      ),
                    ).then((_) => _refreshElders());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceRefreshTimer?.cancel();
    _offlineConfirmTimer?.cancel();
    _monitorHttpTimer?.cancel();
    // ★ 2026-08-05 第十七輪：離開畫面時務必收掉警報朗讀與 wakelock，
    //   否則 TTS 會繼續唸完、螢幕也會一直亮著。
    _alertTts?.stop();
    WakelockPlus.disable();
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    // ★ 2026-08-10 第十九輪（E）：原本只清 onElderDevicesUpdate，
    //   onCallRequest / onEmergencyCall / onCancelCall 三個覆寫留在 Signaling
    //   singleton 上（Signaling 是全域單例，不會隨本畫面銷毀），closure 持續
    //   持有已 dispose 的 State。
    //   ⚠️ 只清「還是自己那一份」的，理由見欄位宣告處的 pushAndRemoveUntil 說明。
    _signaling.onElderDevicesUpdate = null;
    _signaling.onElderZoneUpdate = null;
    if (identical(_signaling.onCallRequest, _ownCallRequest)) {
      _signaling.onCallRequest = null;
    }
    if (identical(_signaling.onEmergencyCall, _ownEmergencyCall)) {
      _signaling.onEmergencyCall = null;
    }
    if (identical(_signaling.onCancelCall, _ownCancelCall)) {
      _signaling.onCancelCall = null;
    }
    super.dispose();
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact(); // 添加觸覺反饋
    setState(() {
      _selectedIndex = index;
    });
    // ★ 第四十一輪 item 2（第二階段）：偵測「使用者第一次切到某個分頁」並
    //   排程該分頁的新手指引。比照 elder_home_screen.dart::_onNavTap 同一輪
    //   同一功能的作法——IndexedStack 讓三個分頁的 initState 在本畫面第一次
    //   建構時就全部跑過一次，無法拿來偵測「第一次切過來」，因此判斷邏輯
    //   放在這裡（nav 的 tap 入口）。`_tabTutorialAttempted.add()` 在
    //   setState 之後、postFrameCallback 之前同步執行，可擋掉快速連續點擊
    //   同一分頁造成的重複排程。
    if (_tabTutorialAttempted.add(index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowTabTutorial(index);
      });
    }
  }

  // ════════════════════════════════════════════════════════════════
  // ★ 第四十一輪 item 2（第二階段）：新手指引（步驟式高光），家屬端
  // ════════════════════════════════════════════════════════════════

  /// 🚨 硬性要求（來自任務指示，務必保留，不可移除）：教學遮罩絕對不能蓋住
  /// 跌倒警報彈窗／來電對話框，也不能阻止使用者查看監視畫面——家屬錯過一則
  /// 跌倒警報，比錯過一次教學嚴重得多。顯示前一律先確認下列全部條件都成立，
  /// 任一條件不成立就直接放棄本次顯示（不重試；SharedPreferences 完成旗標
  /// 只在 `SpotlightTutorial.showIfNeeded` 真正跑到 `showGeneralDialog` 那
  /// 一步才會寫入，這裡提早 return 不會誤標記成「已經看過」，下次再進來、
  /// 屆時沒有警報／來電了，仍會再嘗試一次）。
  ///
  /// 比長輩端 elder_home_screen.dart 的三個 guard（mounted／
  /// pendingAcceptedCall／來電對話框）多出三項家屬端特有情境：
  /// - `_cctvAlertDialogOpen`：跌倒警報彈窗正開著。
  /// - `_activeAlerts.isNotEmpty`：即時警報卡片仍在畫面上（彈窗可能已被
  ///   使用者關掉，但警報本身尚未處理／查看，見 `_presentCctvAlert` 與
  ///   `_handleCctvAlert` 的欄位註解）。
  /// - `_viewingMonitorDeviceId != null`：正在觀看某台監視機的即時畫面。
  ///
  /// 長輩端只在「主介面教學」（冷啟動當下最容易撞到來電）檢查一次，各分頁
  /// 教學不再重查，因為 `_onNavTap` 本身就無法在阻擋式來電對話框開著時被
  /// 觸發（`showDialog(barrierDismissible: false)` 會擋掉底下所有點擊）。
  /// 家屬端的 CCTV 警報卡片**不是**阻擋式彈窗（`_activeAlerts` 非空時使用者
  /// 仍可正常操作分頁、點擊底部導覽），因此這裡在主介面教學與三個分頁教學
  /// 的每一個入口都重新檢查一次，而不是只在最外層查一次。
  bool _isSafeToShowFamilyTutorial() {
    if (!mounted) return false;
    if (pendingAcceptedCall.value != null) return false;
    if (_isIncomingCallDialogOpen) return false;
    if (_cctvAlertDialogOpen) return false;
    if (_activeAlerts.isNotEmpty) return false;
    if (_viewingMonitorDeviceId != null) return false;
    return true;
  }

  /// 主介面教學：介紹最下面三個標籤分別是什麼。
  Future<void> _maybeShowMainTutorial() async {
    if (!_isSafeToShowFamilyTutorial()) return;
    await SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'family_main_v1',
      titleFontSize: 20,
      bodyFontSize: 15,
      buttonHeight: 48,
      steps: [
        TutorialStep(
          targetKey: _navItemKeys[0],
          title: '首頁',
          body: '這裡會看到長輩現在在不在線上、AI 幫您整理的情緒氣象台，還有最新的警示通知。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[1],
          title: '互動',
          body: '想打視訊電話給長輩、找 AI 討論照護問題、看家庭時光牆或監視器畫面，都在這裡。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[2],
          title: '資料',
          body: '這裡有您的帳號資料、長輩的基本資料摘要、回憶錄，還有 AI 助手的設定。',
        ),
      ],
    );

    // ★ 首頁（index 0）是開機時的預設選中分頁，理由同 elder_home_screen.dart
    //   對應註解：使用者不需要點擊就已經看到首頁，_onItemTapped 永遠不會被
    //   觸發，family_home_v1 教學需在這裡補上一次串接。守門條件重查一次，
    //   不沿用函式開頭那次的結果——主介面教學播完可能已經過了好幾秒。
    if (!_isSafeToShowFamilyTutorial()) return;
    if (_tabTutorialAttempted.add(_selectedIndex)) {
      _maybeShowTabTutorial(_selectedIndex);
    }
  }

  /// 分頁教學的分派：只在 `_onItemTapped` 判定「第一次切到這個分頁」時呼叫。
  void _maybeShowTabTutorial(int index) {
    if (!_isSafeToShowFamilyTutorial()) return;
    switch (index) {
      case 0:
        _showHomeTabTutorial();
        break;
      case 1:
        _showInteractionTabTutorial();
        break;
      case 2:
        _showDataTabTutorial();
        break;
    }
  }

  void _showHomeTabTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'family_home_v1',
      titleFontSize: 20,
      bodyFontSize: 15,
      buttonHeight: 48,
      steps: [
        TutorialStep(
          targetKey: _homeElderHeaderKey,
          title: '長輩目前狀態',
          body: '這裡會顯示長輩現在在不在線上、目前的位置，還有今天走了幾步路。',
        ),
        TutorialStep(
          targetKey: _homeMonitorStatusKey,
          title: '監控設備狀態',
          body: '這裡看監視器有沒有連線。偵測到跌倒時卡片會變紅色提醒您，長輩出現在鏡頭前時會變成青色。',
        ),
        TutorialStep(
          targetKey: _homeAiMoodRadarKey,
          title: 'AI 情緒氣象台',
          body: 'AI 會分析長輩最近的狀況，幫您整理一段開場白和話題，讓您打電話時知道要聊什麼。',
        ),
        TutorialStep(
          targetKey: _homeAlertPreviewKey,
          title: '最新警示',
          body: '這裡列出最新的警示通知，點下去可以看到完整的警示清單。',
        ),
      ],
    );
  }

  void _showInteractionTabTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'family_interaction_v1',
      titleFontSize: 20,
      bodyFontSize: 15,
      buttonHeight: 48,
      steps: [
        TutorialStep(
          targetKey: _interactionCallKey,
          title: '視訊通話',
          body: '按這裡可以打視訊電話給長輩，遇到緊急狀況也可以在這裡發起緊急通話。',
        ),
        TutorialStep(
          targetKey: _interactionAiCopilotKey,
          title: 'AI 照護共創助理',
          body: 'AI 助理可以陪您一起討論怎麼照顧長輩，給您實用的照護建議。',
        ),
        TutorialStep(
          targetKey: _interactionCommunityKey,
          title: '家庭生活時光牆',
          body: '這裡是全家人分享生活點滴的地方，您可以看到長輩的近況，也能分享照片給長輩看。',
        ),
        TutorialStep(
          targetKey: _interactionMonitorKey,
          title: '監控設備',
          body: '這裡管理家中的監視器，可以隨時打開查看即時畫面，確認長輩是否平安。',
        ),
      ],
    );
  }

  void _showDataTabTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'family_data_v1',
      titleFontSize: 20,
      bodyFontSize: 15,
      buttonHeight: 48,
      steps: [
        TutorialStep(
          targetKey: _dataCaregiverKey,
          title: '您的帳號資料',
          body: '這裡是您自己的帳號資訊，可以查看和修改您的個人資料。',
        ),
        TutorialStep(
          targetKey: _dataElderSummaryKey,
          title: '長輩基本資料',
          body: '這裡整理了長輩的基本資料，像是慢性病史和用藥提醒，方便您隨時查閱。',
        ),
        TutorialStep(
          targetKey: _dataMemoirsKey,
          title: '回憶錄',
          body: '這裡收藏長輩的人生故事，您可以陪長輩一起回顧美好的回憶。',
        ),
        TutorialStep(
          targetKey: _dataAiHelperKey,
          title: 'AI 助手設定',
          body: '這裡可以調整陪伴長輩的 AI 助手，像是稱呼、說話語氣和聊天話題偏好。',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: _currentElder == null
          ? Text(
              'Uban 照護中樞',
              style: GoogleFonts.notoSansTc(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            )
          : InkWell(
              onTap: _showElderSelector,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF1E293B),
                      child: Text(
                        _currentElder?.genderEmoji ?? '',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // ★ 2026-08-10 第二十輪（需求 2）：長輩名字長度不可控，
                    //   這條 AppBar 標題列出現在家屬端每一頁的最上方，
                    //   不包 Flexible 就會整條往右溢出（黃黑斜紋 RenderFlex 警示）。
                    Flexible(
                      child: Text(
                        _currentElder?.displayName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF38BDF8),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    _PulseDot(
                      color: _isElderOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isElderOnline ? '在線' : '離線',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: _isElderOnline
                            ? const Color(0xFF34D399)
                            : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF5C451), size: 26),
          tooltip: '訂閱測試（為長輩開通）',
          onPressed: () {
            final elder = _currentElder;
            Navigator.push(
              context,
              MaterialPageRoute(
                // 帶入 elder_id → RevenueCat App User ID 綁成 elder_<id>，
                // 購買才會落到這位長輩身上（見 SubscriptionTestScreen 說明）。
                builder: (context) => SubscriptionTestScreen(
                  elderId: elder?.elderId ?? elder?.id.toString(),
                  elderName: elder?.displayName,
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 28),
          tooltip: '配對新長輩',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CaregiverPairingScreen(
                  familyId: widget.userId,
                  familyName: widget.userName,
                ),
              ),
            ).then((_) => _refreshElders());
          },
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: Colors.white.withValues(alpha: 0.08),
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBody: true,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FamilyHomeTab(
            currentElder: _currentElder,
            isElderOnline: _isElderOnline,
            activeAlerts: _activeAlerts,
            // ★ 2026-08-18 IPS prototype：長輩目前所在區域卡片所需資料。
            //   monitorDevices 沿用與 FamilyInteractionTab 相同的清單，由該分頁
            //   自行取第一台監視機的 deviceId/deviceName（與本檔 `_maybeFetchInitialZone`
            //   同一套邏輯），不在此另外拆欄位傳遞。
            monitorDevices: _monitorDevices,
            elderZone: _elderZone,
            userId: widget.userId,
            // ★ 2026-08-10 第十九輪（需求 4）：首頁「開始撥號」接回真正的通話路徑
            onStartVideoCall: _startNormalVideoCall,
            onNavigateToAlerts: () {
              if (_currentElder != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => AlertCenterScreen(
                      elderName: _currentElder!.displayName,
                      elderId: _currentElder!.id,
                      // ★ 第四十一輪（item 1 追加）：與 family_home_tab.dart
                      // ::_loadDynamicData（:824）算法一致，供 AlertCenterScreen
                      // 自行抓取活動流水／持久化跌倒警報時使用。
                      elderRoomId: _currentElder!.elderId ??
                          _currentElder!.id.toString(),
                      // ★ 第四十一輪（item 1）：與傳給 FamilyHomeTab 的是同一份
                      // _activeAlerts，避免「查看全部」展開後即時警報消失。
                      activeAlerts: _activeAlerts,
                    ),
                  ),
                );
              }
            },
            // ★ 2026-08-24（首頁「最新警示」滑動關閉，父層一半）：接上
            //   FamilyHomeTab 的同名參數（宣告見 family_home_tab.dart:49-52，
            //   對方那份分頁側程式碼——filter :3009、Dismissible :3173——早已
            //   就位，只是父層一直沒有傳入非預設值，導致滑掉的警示在下一輪
            //   2.5 秒輪詢又跳回來）。_dismissedAlertKeys／
            //   _handleAlertItemDismissed 宣告與完整理由見本檔上方欄位註解。
            dismissedAlertKeys: _dismissedAlertKeys,
            onAlertItemDismissed: _handleAlertItemDismissed,
            // ★ 2026-08-31 第三十八輪：首頁「最新警示」的 CCTV／跌倒項目點擊入口。
            //   在此之前本參數從未被傳入，導致該類警示永遠不可點擊（見
            //   _openMonitorViewForDevice 的說明）。與跌倒警報彈窗共用同一組
            //   VideoCallScreen 建構參數（G55）。
            onOpenMonitorView: (deviceId) {
              if (deviceId == null || deviceId.isEmpty) return;
              _openMonitorViewForDevice(deviceId);
            },
            // ★ 第四十一輪 item 2（第二階段）：新手指引高光目標，見本檔
            //   `_showHomeTabTutorial` 與欄位宣告處的說明。
            elderHeaderKey: _homeElderHeaderKey,
            monitorStatusKey: _homeMonitorStatusKey,
            aiMoodRadarKey: _homeAiMoodRadarKey,
            alertPreviewKey: _homeAlertPreviewKey,
          ),
          FamilyInteractionTab(
            currentElder: _currentElder,
            signaling: _signaling,
            monitorDevices: _monitorDevices,
            activeAlerts: _activeAlerts,
            // ★ 2026-08-24 Feature A：與傳給 FamilyHomeTab 的是同一份狀態，
            //   供監控卡片高亮「目前長輩所在此處」。
            elderZone: _elderZone,
            devicesMax: _devicesMax,
            tierDisplayName: _tierDisplayName,
            tierLevel: _tierLevel,
            userId: widget.userId,
            elderSocketId: _elderSocketId,
            // ★ 第四十一輪 item 2（第二階段）：新手指引高光目標，見本檔
            //   `_showInteractionTabTutorial` 與欄位宣告處的說明。
            callSectionKey: _interactionCallKey,
            aiCopilotKey: _interactionAiCopilotKey,
            communityKey: _interactionCommunityKey,
            monitorSectionKey: _interactionMonitorKey,
            // ★ 2026-08-16（需求 2）：查看完監視畫面後移除該設備的警報狀態
            onAlertDismissed: (deviceId) {
              if (mounted) {
                setState(() {
                  _activeAlerts.removeWhere((a) =>
                      (a['device_id'] ?? a['deviceId'])?.toString() == deviceId.toString());
                });
              }
            },
            // ★ 2026-08-10 第十九輪（需求 3）：卡片刪除／改名後立即重新整理。
            onDevicesChanged: () {
              _refreshMonitorDevicesViaHttp();
              _loadSubscriptionTier();
            },
          ),
          FamilyDataTab(
            currentElder: _currentElder,
            userId: widget.userId,
            userName: widget.userName,
            onElderUpdated: () {
              _refreshElders();
            },
            // ★ 第四十一輪 item 2（第二階段）：新手指引高光目標，見本檔
            //   `_showDataTabTutorial` 與欄位宣告處的說明。
            caregiverCardKey: _dataCaregiverKey,
            elderSummaryKey: _dataElderSummaryKey,
            memoirsKey: _dataMemoirsKey,
            aiHelperKey: _dataAiHelperKey,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.home_rounded, '首頁'),
                    _buildNavItem(1, Icons.chat_bubble_rounded, '互動'),
                    _buildNavItem(2, Icons.settings_rounded, '資料'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? const Color(0xFF38BDF8) // Neon Cyan Glow
        : const Color(0xFF64748B); // Slate Gray

    return Expanded(
      child: GestureDetector(
        key: _navItemKeys[index],
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(icon, color: color, size: 29),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  color: color,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .fade(duration: 1200.ms, begin: 1.0, end: 0.3)
        .then()
        .fade(duration: 1200.ms, begin: 0.3, end: 1.0);
  }
}
