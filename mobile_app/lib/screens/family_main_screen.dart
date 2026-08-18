import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加觸覺反饋
import 'package:google_fonts/google_fonts.dart';
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
import 'package:flutter_application_1/utils/app_logger.dart';
import '../globals.dart';
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
  
  Elder? _currentElder;
  List<Elder> _elders = [];
  bool _isElderOnline = false;

  /// 長輩端「第一台在線設備」的 socket id，由 `_applyDeviceList()` 維護。
  /// 撥打通話時當作 `VideoCallScreen.targetSocketId`，讓 SDP 精準送達而非靠房間廣播。
  ///
  /// ⚠️ 這個欄位在分支整合時連同宣告一起遺失（HEAD 上只剩三處賦值、無宣告，
  ///    整個檔案無法編譯），2026-08-10 第十九輪補回。
  /// 🚨 跌倒警報要開哪一台監視機時**不可**用它——那要用該裝置自己的 `id`，
  ///    見 `_presentCctvAlert()` 內的說明。
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

  /// ★ 2026-08-18 IPS prototype：目前長輩的室內定位（zone）狀態，正規化自
  /// REST `ApiService.getCurrentZone`（快照）與 Socket `elder-zone-update`
  /// （即時推播）兩種不同形狀的來源，統一成 `{zone, enteredAt, updatedAt,
  /// calibrated}` 供 `FamilyHomeTab` 顯示。
  /// `calibrated`（後端 `GET /api/ips/current/{elder_id}` 的權威欄位，代表該
  /// 監視機是否已有非空的 zone 多邊形設定）才是「要不要顯示前往校準提示」
  /// 的判斷依據，不要用 `zone == 'unknown'` 或 `last_seen == null` 反推——
  /// 兩者都無法區分「尚未校準」與「已校準但目前沒偵測到人」。
  /// Socket 推播不帶 `calibrated`，收到即視為 `true`（見 `_applyZoneUpdate`）。
  /// null＝「尚未取得任何回應」（elder 剛切換、REST 還沒回來，或還沒收過
  /// 任何 socket 推播），畫面比照 `calibrated == false` 顯示同一張提示卡，
  /// 不另外做 loading 狀態。
  /// 「尚未綁定監視機」則是完全不同的狀態，靠 `_monitorDevices.isEmpty` 判斷，
  /// 不會落到這裡。
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

  /// 警報朗讀用的 TTS，只建立一次（不要每次警報都 new），`dispose()` 時 stop。
  FlutterTts? _alertTts;
  String _tierLevel = 'free';
  String _tierDisplayName = '一般會員';
  int _devicesMax = 2;

  /// ★ 2026-08-04 第 4 項：訂閱到期／設備超量彈窗只在每次進入本畫面時提示一次，
  /// 避免每次 `_loadSubscriptionTier()` 重新整理都再彈一次而干擾使用者。
  bool _overLimitDialogShown = false;

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
      final bool online = devices.any(_isDeviceOnline);
      final List<dynamic> monitors =
          devices.where((d) => d is Map && d['deviceMode'] == 'monitor').toList();
      final onlineDevice = devices.firstWhere(_isDeviceOnline, orElse: () => {});
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
    setState(() {
      _elderZone = {
        'zone': (payload['to_zone'] ?? 'unknown').toString(),
        'enteredAt': _parseUtcIso(payload['entered_at']) ?? DateTime.now(),
        'updatedAt': DateTime.now(),
        // ★ payload 不帶 calibrated 欄位（見團隊回覆：一次區域切換推播就代表
        //   已在追蹤，等同已校準）。整包物件都在這裡重建，若不明確寫 true，
        //   這個 key 會直接消失、被畫面當成 false 處理，變成「已知的 true
        //   被 socket 推播降級成 unknown」——明確寫死，不要留給預設值。
        'calibrated': true,
      };
    });
  }

  /// ★ 2026-08-18 IPS prototype：監視機清單確定後，補一次 zone 初始值。
  /// 為什麼需要它：`elder-zone-update` 只在區域**切換**時才推播，長輩若長時間
  /// 待在同一區域，UI 會在切分頁前一直空白，必須主動查一次目前快照。
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
      // ★ 後端現在直接給 `calibrated` 權威欄位，不再用 `last_seen` 是否為
      //   null 反推「有沒有資料」——只要成功回應（非空 Map）就正規化套用，
      //   校準與否交給 `calibrated`，是否在任何區域內交給 `zone`。
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
  /// `{zone, dwell_seconds, last_seen, calibrated, elder_id, device_id}` →
  /// 正規化狀態。
  /// 後端只給 `dwell_seconds`（查詢當下已停留秒數），沒有 `entered_at`；用
  /// 「現在－dwell_seconds」反推進入時間，讓卡片用同一套邏輯估算停留時長，
  /// 與 socket 推播（有真正的 `entered_at`）共用同一份顯示邏輯。
  /// `calibrated` 是後端的權威欄位（該監視機是否已有非空 zone 多邊形設定），
  /// 直接透傳，不用 `zone`／`last_seen` 反推。
  static Map<String, dynamic> _zoneStateFromRest(Map<String, dynamic> data) {
    final num dwellSeconds = num.tryParse('${data['dwell_seconds'] ?? 0}') ?? 0;
    return {
      'zone': (data['zone'] ?? 'unknown').toString(),
      'enteredAt': DateTime.now().subtract(Duration(seconds: dwellSeconds.round())),
      'updatedAt': _parseUtcIso(data['last_seen']) ?? DateTime.now(),
      'calibrated': data['calibrated'] == true,
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
      final currentElderId = _currentElder?.elderId ?? _currentElder?.id?.toString();
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

  /// ★ 2026-08-05 第十七輪：家屬端在**前景**時的跌倒警報呈現。
  /// 需求的三件事分別由三個機制負責，任一項失敗都不得影響其餘兩項：
  ///   - 強制開啟螢幕 → `CctvAlertNotification`（`fullScreenIntent`）＋ `WakelockPlus`（維持亮著）
  ///   - 彈出通知     → 本方法的 `AlertDialog`（APP 已在前景時系統通知容易被忽略）
  ///   - 朗讀         → `FlutterTts`
  /// APP 在背景／被殺死時走的是 `main.dart` 的 FCM `cctv-alert` 分支，不會經過這裡。
  Future<void> _presentCctvAlert(Map<String, dynamic> alert) async {
    final String alertType =
        (alert['alert_type'] ?? alert['alertType'] ?? 'fall').toString();
    final String typeLabel = _alertTypeLabel(alertType);

    // 1) 保持螢幕亮著
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('⚠️ [FamilyMainScreen] WakelockPlus.enable 失敗: $e');
    }

    // 2) 系統通知（螢幕關閉時由 fullScreenIntent 負責點亮）
    try {
      await CctvAlertNotification.show({
        'elderId': (alert['elder_id'] ?? alert['elderId'] ?? '').toString(),
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
    final bool canView = viewSocketId.isNotEmpty && _isDeviceOnline(device);
    final String rawElderId =
        (alert['elder_id'] ?? alert['elderId'] ?? '').toString();
    final String monitorRoomId = 'monitor_elder_$rawElderId';

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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoCallScreen(
                        roomId: monitorRoomId,
                        targetSocketId: viewSocketId,
                        isEmergency: true,
                        autoStart: true,
                        // 從彈窗進入的監控檢視同樣用 pop() 返回本頁
                        returnByPop: true,
                        // ★ 2026-08-10 第十九輪（需求 2）：單向監控檢視
                        monitorViewOnly: true,
                      ),
                    ),
                  ).then((_) {
                    // ★ 2026-08-16（需求 2）：查看完監視畫面返回後，將該警報移出 _activeAlerts，將遠端監控卡片動畫與紅框還原正常
                    if (mounted) {
                      setState(() {
                        final String alertDevice = (alert['device_id'] ?? alert['deviceId'])?.toString() ?? '';
                        _activeAlerts.removeWhere((a) =>
                            (a['device_id'] ?? a['deviceId'])?.toString() == alertDevice ||
                            a['alert_id'] == alert['alert_id']);
                      });
                    }
                  });
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
                            final ok = await ApiService.deleteMonitorDevice(
                              elderId: rawElderId,
                              deviceName: name,
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
                    ),
                  ),
                );
              }
            },
          ),
          FamilyInteractionTab(
            currentElder: _currentElder,
            signaling: _signaling,
            monitorDevices: _monitorDevices,
            activeAlerts: _activeAlerts,
            devicesMax: _devicesMax,
            tierDisplayName: _tierDisplayName,
            tierLevel: _tierLevel,
            userId: widget.userId,
            elderSocketId: _elderSocketId,
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
