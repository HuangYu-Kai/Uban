import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/signaling.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../services/emergency_tone.dart';
import '../widgets/heartbeat_overlay.dart';
import '../widgets/call_retry_dialog.dart';
import 'identification_screen.dart';
import 'elder_home_screen.dart';
import '../globals.dart';

class ElderScreen extends StatefulWidget {
  final String roomId;
  final bool isCCTVMode;
  final String deviceName;
  final bool autoCall;
  final bool isVideoCall; // ★ 新增：是否為視訊通話（false = 純語音）
  final Map<String, dynamic>? initialCallData; // ★ 新增：初始化通話參數，避免與 global 變數競爭

  const ElderScreen({
    super.key,
    required this.roomId,
    this.isCCTVMode = false,
    this.deviceName = 'Elder Device',
    this.autoCall = false,
    this.isVideoCall = true, // 預設視訊通話
    this.initialCallData,
  });

  @override
  State<ElderScreen> createState() => _ElderScreenState();
}

class _ElderScreenState extends State<ElderScreen> with WidgetsBindingObserver {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _status = "等待連線...";
  bool _isInCall = false;
  bool _isCameraOff = false; // 視訊房間預設開啟鏡頭
  bool _isMuted = false;
  bool _isFrontCamera = true; // ★ issue 12：前/後鏡頭狀態
  late bool _isSpeakerOn; // ★ 2026-08-10 第二十輪（D4）：擴音(true)／聽筒(false)，依通話類型於 initState 決定初始值
  bool _speakerAutoSwitched = false; // ★ 2026-08-10 第二十輪（D4）：語音通話中途開鏡頭時只自動切一次擴音，不覆蓋使用者手動切回聽筒的選擇
  bool _mediaInitialized = false;
  Timer? _callTimer;
  int _callDuration = 0; // 秒數

  /// ★ 2026-08-05 第十七輪：跌倒測試按鈕的防連點旗標（暫時性測試入口，
  ///   YOLO 可實測後連同按鈕一起移除）。
  bool _testFallSending = false;

  /// ★ 2026-08-04 第 7 項：CCTV 影格推送給後端做 YOLO 跌倒偵測。
  /// 只在 `widget.isCCTVMode == true` 時啟動——一般通話路徑完全不建立這個計時器、
  /// 不呼叫 captureFrame，位元組層級與修改前相同，不影響通話品質與時序。
  Timer? _cctvFrameTimer;

  /// 上一張影格是否仍在上傳中。網路變慢時直接跳過該輪，**絕不排隊**，
  /// 避免計時器堆積把長輩機的記憶體與上行頻寬吃光（與後端限流丟幀策略一致）。
  bool _cctvFrameSending = false;

  /// ★ 2026-08-11 第二十二輪（需求 3：家屬端奇數次進入監控會讓監控機畫面停住）。
  /// 連續失敗次數；連續 3 輪失敗就視為擷取管線已壞，觸發 [_recoverCctvCapture]。
  int _cctvFrameFailStreak = 0;

  /// 最近一次「成功推出影格」的時間。超過 30 秒沒有任何一張成功就強制重建擷取管線——
  /// 這條看門狗涵蓋的是「沒有拋例外、就只是永遠不返回」的情境（失敗計數不會增加）。
  DateTime? _cctvLastFrameOkAt;

  /// [_recoverCctvCapture] 的重入保護。重建過程本身有 await，沒有這個旗標，
  /// 每 2 秒一輪的計時器會疊著呼叫，把相機開開關關到真的壞掉。
  bool _cctvRecovering = false;

  /// ★ 2026-08-11 第二十二輪（需求 6）：本監控機是否已被家屬端刪除。
  ///
  /// 後端刪除監控設備時會先 emit `monitor-removed`、再把這台裝置踢線，
  /// 於是監控機端會**先後**收到兩個訊號；若只看後者（連線中斷），畫面會顯示
  /// 「連線中斷」——使用者看到的是「設備明明還開著、卻說我斷線」而不是真相
  /// 「這台已經被移除了」。這個旗標讓 [Signaling.onConnectionLost] 能分辨兩者。
  ///
  /// 兩個訊號的到達順序不保證（踢線可能先到），所以 `onConnectionLost` 除了讀
  /// 這個旗標，還會再用 REST 清單交叉驗證一次。
  bool _monitorRemoved = false;

  /// ★ 2026-08-11 第二十二輪（需求 8）：本畫面註冊在 socket 上的 `force-logout`
  /// 原生監聽。存起來才有辦法在 dispose() 時用
  /// `socket.off('force-logout', _forceLogoutHandler)` 精準解除，
  /// 避免每進出一次通話／監控畫面就在 singleton socket 上多疊一份殭屍 handler。
  void Function(dynamic)? _forceLogoutHandler;

  int? _userId; // ★ issue 3/10：用於安全導航回主畫面時建構 ElderHomeScreen
  String? _prefsUserName; // ★ Issue 1 硬化：真實 caregiver_name，供 _buildFallbackHome 使用

  /// ★ 2026-08-06 第十九輪（D4）：監視機「目前」的裝置名稱，初始值等於 widget.deviceName。
  /// 收到後端 'monitor-renamed' 事件後會更新成新名稱，讓退出監控時呼叫刪除 API、
  /// 以及推送 CCTV 影格都使用「改名後」的最新名稱——後端以 device_name 字串精確比對，
  /// 若改名後仍送出過期的 widget.deviceName 會比對不到，家屬端清單/影格歸屬就會對不上。
  late String _currentDeviceName;

  /// ★ 2026-07-27 第十三輪：本畫面目前正在進行的通話 callId。
  /// 作為 isSameOngoingCall 去重的第二道防線——不依賴 Signaling.lastProcessedCallId
  /// 是否被各路徑正確設定。任何一條寫入 pendingAcceptedCall 的路徑若漏設，
  /// 都不會再把進行中的通話誤判成新來電而 hangUp（緊急通話瞬間掛斷的直接成因）。
  String? _activeCallId;

  // ★ 新增：用於生成新格式的房間ID
  late String _formattedRoomId;
  
  // ★ 輔助方法：根據通訊模式生成房間ID（冪等保護）
  String _getFormattedRoomId(String elderId) {
    // 冪等保護：若已是完整格式，直接使用（防止 FCM 冷啟動時重複添加前綴）
    if (elderId.startsWith('comm_elder_') || elderId.startsWith('monitor_elder_')) {
      return elderId;
    }
    if (widget.isCCTVMode) {
      return 'monitor_elder_$elderId';  // 監控/CCTV 模式
    } else {
      return 'comm_elder_$elderId';  // 雙向通訊模式
    }
  }

  /// ★ 2026-08-04 第 7 項：由 `_formattedRoomId` 還原出純 elder_id。
  /// `/api/cctv/frame` 與後端設備清單的 device_id 推導都以「純 elder_id」為基準，
  /// 若誤把 `monitor_elder_0343` 整串送過去，推導出的 device_id 會與
  /// `_get_elder_devices_list()` 算出來的不一致，家屬端的紅色高亮就永遠對不上。
  String get _rawElderId {
    const monitorPrefix = 'monitor_elder_';
    const commPrefix = 'comm_elder_';
    if (_formattedRoomId.startsWith(monitorPrefix)) {
      return _formattedRoomId.substring(monitorPrefix.length);
    }
    if (_formattedRoomId.startsWith(commPrefix)) {
      return _formattedRoomId.substring(commPrefix.length);
    }
    return _formattedRoomId;
  }

  /// ★ 2026-08-04 第 7 項：每 2 秒擷取一張畫面推給後端做 YOLO 偵測。
  ///
  /// 為何是 2 秒：後端 `yolo_detector_service` 的判定窗口以「連續影格數」計算
  /// （FALL_WINDOW_FRAMES=12、CRAWL_WINDOW_FRAMES=18、INACTIVITY_WINDOW_FRAMES=24），
  /// 2 秒一張正好對應到 24 秒倒地不起、36 秒爬行、48 秒無動作才告警，
  /// 符合需求所說的「長時間倒地不起」，也不會讓監視機一直滿載。
  ///
  /// 任何一輪失敗都只記錄並跳過，計時器本身絕不因單次錯誤而中止。
  ///
  /// ★ 2026-08-11 第二十二輪（需求 3：**家屬端奇數次進入監控會讓監控機畫面停住，
  ///   要再進一次才恢復**）。根因就在這個迴圈：
  ///   1. 家屬端進入監控 → 監控機的 `startMonitoring`/`_acceptCall` 會先
  ///      `_closePeerConnection()`，那裡有一段
  ///      `for (sender in await pc.getSenders()) { await pc.removeTrack(sender); }`。
  ///      `removeTrack` 會把本機視訊軌從編碼器上拆下來。
  ///   2. 若此刻剛好有一輪 `captureFrame()` 正在等原生層回傳，那個 Future 會
  ///      **永遠不完成**——不是丟例外，是卡住。`try/catch` 完全攔不到。
  ///   3. 於是 `finally` 不執行、`_cctvFrameSending` 永遠停在 `true`，
  ///      之後每一輪都被開頭的 `if (_cctvFrameSending) return;` 擋掉 →
  ///      **推幀徹底停止**，家屬端看到的畫面就凍住。
  ///   4. 家屬端再進一次時，peer connection 重建、軌道重新掛回編碼器，
  ///      那個卡住的 Future 才被原生層以錯誤收掉 → `finally` 終於跑到 →
  ///      旗標歸位 → 「第 2、4、6 次進入就正常」。這正是使用者觀察到的奇偶數規律。
  ///
  ///   修法有三層，缺一不可：
  ///   - **逾時**：`captureFrame()` 與上傳都加 `.timeout(...)`，把「永遠卡住」
  ///     變成「會拋 TimeoutException」，`finally` 就一定跑得到。
  ///   - **連續失敗計數**：連續 3 輪失敗 → 重建擷取管線。
  ///   - **無成功影格看門狗**：30 秒內一張都沒成功 → 重建擷取管線。
  void _startCctvFrameLoop() {
    _cctvFrameTimer?.cancel();
    _cctvLastFrameOkAt = DateTime.now();
    _cctvFrameFailStreak = 0;
    _cctvFrameTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _cctvFrameSending || _cctvRecovering) return;

      // 看門狗：30 秒沒有任何一張成功送出就重建擷取管線。
      //   放在 localStream 檢查**之前**，因為「localStream 變成 null / 沒有視訊軌」
      //   本身就是需要重建的故障態，擺在後面會被 return 掉而永遠不觸發。
      final lastOk = _cctvLastFrameOkAt;
      if (lastOk != null && DateTime.now().difference(lastOk).inSeconds >= 30) {
        debugPrint('🚑 [CCTV] 看門狗：30 秒內沒有任何影格成功送出，重建擷取管線');
        await _recoverCctvCapture();
        return;
      }

      final videoTracks = _signaling.localStream?.getVideoTracks();
      if (videoTracks == null || videoTracks.isEmpty) return;

      _cctvFrameSending = true;
      try {
        // ★ 第二十二輪：captureFrame 沒有逾時就是本輪需求 3 的直接死因。
        //   6 秒遠大於正常擷取時間（實測數十毫秒），只在真的卡死時才會觸發。
        final buffer = await videoTracks.first
            .captureFrame()
            .timeout(const Duration(seconds: 6));
        await ApiService.pushCctvFrame(
          elderId: _rawElderId,
          // ★ 第十九輪（D4）：改用 _currentDeviceName（可隨 monitor-renamed 更新），
          //   避免改名後這個每 2 秒跑一次的迴圈仍持續用舊名稱推幀，
          //   導致 YOLO 偵測結果被後端歸到「改名前」的裝置、與家屬端看到的新名稱對不上。
          deviceName: _currentDeviceName,
          frameBytes: buffer.asUint8List(),
        ).timeout(const Duration(seconds: 10));
        _cctvFrameFailStreak = 0;
        _cctvLastFrameOkAt = DateTime.now();
      } catch (e) {
        _cctvFrameFailStreak++;
        debugPrint('⚠️ [CCTV] 影格推送失敗（第 $_cctvFrameFailStreak 次，略過本輪，不中斷迴圈）: $e');
      } finally {
        // ★ 絕對不可移除：這一行是「畫面停住」的解鎖點。
        _cctvFrameSending = false;
      }

      // 連續 3 輪失敗＝擷取管線已壞（軌道被 removeTrack 拆掉、相機被搶走…），
      // 單純再等下一輪不會自己好，直接重建。
      if (_cctvFrameFailStreak >= 3 && !_cctvRecovering) {
        debugPrint('🚑 [CCTV] 連續 $_cctvFrameFailStreak 輪失敗，重建擷取管線');
        await _recoverCctvCapture();
      }
    });
    debugPrint('🎥 [CCTV] 已啟動影格推送迴圈 (elder=$_rawElderId, device=$_currentDeviceName)');
  }

  /// ★ 2026-08-11 第二十二輪（需求 3）：重建監控機的本機擷取管線。
  ///
  /// 只在 CCTV 模式下有意義；一般通話路徑永遠不會呼叫到（呼叫端都在
  /// [_startCctvFrameLoop] 內，而該迴圈只在 `widget.isCCTVMode` 時啟動）。
  ///
  /// 步驟刻意是「先停迴圈 → 釋放媒體 → 重新取得 → 重掛預覽 → 重啟迴圈」：
  /// 直接呼叫 `_initializeMedia()` 是沒用的，它開頭就有 `if (_mediaInitialized) return;`。
  Future<void> _recoverCctvCapture() async {
    if (_cctvRecovering) return;
    _cctvRecovering = true;
    debugPrint('🚑 [CCTV] 開始重建擷取管線…');
    try {
      _cctvFrameTimer?.cancel();
      _cctvFrameTimer = null;

      // 釋放舊的相機資源。stopMedia() 會 stop 每一條 track 再 dispose stream，
      // 卡住的 captureFrame 也會因為軌道被停止而被原生層以錯誤收掉。
      _signaling.stopMedia();
      _localRenderer.srcObject = null;
      _mediaInitialized = false;

      // 給原生層一點時間真正釋放相機，否則某些機型會立刻 getUserMedia 失敗。
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      await _initializeMedia();
      if (!mounted) return;

      _cctvFrameSending = false;
      _cctvFrameFailStreak = 0;
      _cctvLastFrameOkAt = DateTime.now();
      _startCctvFrameLoop();
      debugPrint('✅ [CCTV] 擷取管線重建完成');
    } catch (e) {
      debugPrint('❌ [CCTV] 重建擷取管線失敗（下一輪看門狗會再試一次）: $e');
      // 失敗也要把旗標歸位並保住迴圈，否則監控機就此徹底停擺。
      _cctvFrameSending = false;
      if (mounted && _cctvFrameTimer == null) {
        _cctvLastFrameOkAt = DateTime.now();
        _startCctvFrameLoop();
      }
    } finally {
      _cctvRecovering = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _checkPermissions();
    
    // ★ 初始化格式化的房間ID
    _formattedRoomId = _getFormattedRoomId(widget.roomId);
    // ★ 第十九輪（D4）：CCTV 目前裝置名稱初始值，改名事件會更新它
    _currentDeviceName = widget.deviceName;

    // 「電話」與「視訊」共用同一套 call-request 後端邏輯；
    // 唯一差異只在進房時鏡頭預設狀態。
    if (widget.isCCTVMode) {
      _isCameraOff = false;
    } else {
      _isCameraOff = !widget.isVideoCall;
    }

    // ★ 2026-08-10 第二十輪（D4）：視訊通話／CCTV 監控預設擴音，一般語音通話預設聽筒。
    _isSpeakerOn = widget.isVideoCall || widget.isCCTVMode;

    // ★ Bug 16 解決方案：監聽從系統層 (main.dart) 傳進來的 CallKit 接聽動作
    pendingAcceptedCall.addListener(_onPendingCallChanged);

    // ★ 2026-08-10 第二十輪（D1-c）：改為等待 _initElderMode() 完成（含 socket 連線與
    //   媒體初始化）後才嘗試自動撥號，取代原本固定等待 2 秒的猜測值——2 秒不夠時
    //   會在 socket 尚未連上就呼叫 _makeCall()，導致 sendCallRequest 送不出去。
    // ★ 2026-08-11 第二十一輪（需求 1）：補上 onError。
    //   `.then()` 沒有 onError 時，`_initElderMode()` 只要拋出任何例外，
    //   回呼就整個被跳過 → 自動撥號靜默消失，畫面永遠停在「等待連線...」，
    //   而且例外會變成無人處理的非同步錯誤，release 版連 log 都看不到。
    //   初始化失敗不代表不能撥號（socket 可能已在別處連上），一律仍嘗試撥出，
    //   真的送不出去時 `_makeCall()` 內部會顯示「連線中斷，無法撥出」。
    void tryAutoCall() {
      if (!mounted || !widget.autoCall || _isInCall) return;
      _makeCall();
    }

    _initElderMode().then(
      (_) => tryAutoCall(),
      onError: (Object e, StackTrace s) {
        debugPrint('❌ [ElderScreen] _initElderMode 失敗（仍嘗試撥號）: $e');
        tryAutoCall();
      },
    );
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  void _onPendingCallChanged() {
    debugPrint("🔔 pendingAcceptedCall Changed: ${pendingAcceptedCall.value}");
    _checkPendingAcceptedCall();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingEmergency();
      _checkPendingAcceptedCall();
    }
  }

  Future<void> _checkPendingEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingRoom = prefs.getString('pending_emergency_room');
    final pendingSender = prefs.getString('pending_emergency_sender');

    // ★ 支持新的房間ID格式以及舊的 elder_id 格式（向後兼容）
    if (pendingRoom != null && pendingSender != null) {
      bool isMatching = pendingRoom == _formattedRoomId || 
                        pendingRoom == widget.roomId;  // 舊格式相容性
      if (isMatching) {
        await prefs.remove('pending_emergency_room');
        await prefs.remove('pending_emergency_sender');
        _handleEmergencyAccept(pendingSender);
      }
    }
  }

  // ★ Bug 16 解決方案：檢查是否有從系統層 (main.dart) 傳進來的 CallKit 接聽動作
  void _checkPendingAcceptedCall() {
    if (pendingAcceptedCall.value != null) {
      final args = pendingAcceptedCall.value!;
      pendingAcceptedCall.value = null; // Consume the event

      final senderId = args['senderId']!;
      final roomId = args['roomId']!;
      final callId = args['callId'];
      final rawEmergency = args['isEmergency'];
      final isEmergency = rawEmergency?.toString() == 'true';

      debugPrint("📞 Detected Accepted Call from $senderId (Room: $roomId, CallId: $callId, Emergency: $isEmergency). Bridging...");

      // ★ issue 5：CallKit 接聽與背景 FCM 路徑可能對「同一通」來電各自寫入一次
      //   pendingAcceptedCall。若 callId 與目前正在處理/已建立的通話相同，視為重複觸發，
      //   不可結束已建立好的通話（否則會造成 issue 5 的「連線後立刻斷線」）。
      // ★ 2026-07-27 第十三輪：加入 _activeCallId 比對作為第二判準。
      //   原本只比 _signaling.lastProcessedCallId，而緊急通話路徑從未設定它，
      //   使本判斷恆為 false → 落入下方 hangUp() 分支 → 對端瞬間掛斷。
      final bool isSameOngoingCall = _isInCall &&
          callId != null &&
          (callId == _signaling.lastProcessedCallId || callId == _activeCallId);

      if (isSameOngoingCall) {
        debugPrint("ℹ️ [ElderScreen] 略過重複的 pendingAcceptedCall（與目前通話 callId 相同: $callId）");
        return;
      }

      // ★ issue 4：一般通話房與緊急通話房不可並存。
      //   若目前已有「不同」通話進行中，先結束舊連線，再接聽新來電。
      if (_isInCall) {
        debugPrint("⚠️ [ElderScreen] 已有通話進行中，先結束舊通話以接聽新來電");
        _callTimer?.cancel();
        _activeCallId = null;
        _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = null;
            _isInCall = false;
          });
        }
      }

      if (isEmergency) {
        _handleEmergencyAccept(senderId, callId: callId);
      } else {
        _handleAcceptedCallFromBackground(senderId, callId: callId);
      }
    }
  }

  Future<void> _handleAcceptedCallFromBackground(String senderId, {String? callId}) async {
    if (!_isInCall && mounted) {
      _activeCallId = callId; // ★ 第十三輪：記錄進行中通話，供 isSameOngoingCall 去重
      setState(() {
        _isInCall = true;
        _status = "通話建立中...";
      });
      
      // Clear CallKit ringing
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint("Failed to end CallKit calls: $e");
      }
      
      // 確保畫面被喚醒到最上層 (針對 Android 14+)
      try {
        final platform = MethodChannel('com.example.app/bring_to_front');
        await platform.invokeMethod('bringToFront');
      } catch (e) {
        debugPrint("Bring to front failed: $e");
      }

      // 回報已接聽，讓家屬端發送 Offer
      _signaling.sendCallAccept(senderId, callId: callId);
    }
  }

  /// ★ 2026-08-11 第二十二輪（需求 9）：緊急通話**無條件接聽**。
  ///
  /// 使用者要求：無論長輩端在 APP 內或外、是否在背景被殺死、螢幕是否關閉，
  /// 只要家屬端撥打緊急通話，長輩端就必須進入緊急通話視訊房，無視長輩是否同意。
  ///
  /// 舊版開頭是 `if (!_isInCall && mounted)`——只要本機自認「已在通話中」，
  /// 整個函式就**什麼都不做**：不 `endAllCalls()`、不 `sendCallAccept()`，
  /// 家屬端一路等到逾時，使用者看到的就是「緊急通話打不通」。
  /// 而 `_isInCall` 殘留為 true 的情況並不罕見：上一通已結束但 `end-call` 沒送達、
  /// CCTV 模式下的自動接聽尚未歸零、前一次緊急通話被對端取消卻沒收到事件。
  /// 緊急通話的語意就是「壓過一切」，不該被這種殘留狀態擋下。
  ///
  /// 新行為：
  ///   1. `callId` 與進行中的同一通 → 直接 return（避免重複 `sendCallAccept`
  ///      造成對端收到兩次 accept 而重送 Offer）。
  ///   2. 不同通但 `_isInCall` → **先拆掉舊通話**，再接這通緊急通話。
  ///      `disposeLocalStream: false` 是刻意的：緊急通話下一步就要用同一顆相機，
  ///      釋放再重開會多花數百毫秒，且 Android Camera2 重開期間可能卡住。
  ///   3. 其餘一律往下接聽。
  Future<void> _handleEmergencyAccept(String senderId, {String? callId}) async {
    if (!mounted) return;

    // 1. 同一通的重複觸發（CallKit accept 與 FCM 兩條路徑常各寫一次）
    if (_isInCall && callId != null && callId == _activeCallId) {
      debugPrint("ℹ️ [ElderScreen] 略過重複的緊急接聽（callId 相同: $callId）");
      return;
    }

    // 2. 不同通進行中 → 先讓位給緊急通話
    if (_isInCall) {
      debugPrint("🚨 [ElderScreen] 緊急通話優先：先結束進行中的通話再接聽");
      _callTimer?.cancel();
      _activeCallId = null;
      _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
      _isInCall = false;
    }

    _activeCallId = callId; // ★ 第十三輪：記錄進行中通話，供 isSameOngoingCall 去重
    setState(() {
      _isInCall = true;
      _status = "緊急通話接通中...";
    });

    // Clear CallKit ringing
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint("Failed to end CallKit calls: $e");
    }

    // ★ 2026-08-06 第十九輪（B）：監視機（CCTV）自動接聽必須完全靜音——
    //   家屬端開啟監控不該觸發長輩端的提示音，也不該讓長輩察覺監控端正在觀看。
    // ★ 2026-08-11 第二十二輪（需求 9）：一般緊急通話**移除 TTS 語音播報**
    //   （原本是「緊急通話，自動接聽中。」唸兩遍），改為約 7 秒的緊急提示音。
    //   TTS 會與剛接通的通話語音搶同一條輸出、還會被系統的語音佇列延後，
    //   提示音則是單純的音檔播放，長輩也更容易辨識。
    if (!widget.isCCTVMode) {
      _playEmergencyTone();
    }

    // Notify the Family App that we are awake and ready to receive the Offer!
    _signaling.sendCallAccept(senderId, callId: callId);
  }

  /// ★ 2026-08-11 第二十二輪（需求 9）：播放約 7 秒的緊急提示音。
  /// ★ 2026-08-12 第二十三輪：播放器搬到全域單例 [EmergencyTone]，音檔換成
  ///   救護車雙音（`sounds/emergency_siren.wav`）。
  ///
  /// 搬家的原因：緊急通話會從 Socket／FCM 前景／FCM 背景冷啟動三條路抵達，
  /// 使用者要求「不論 APP 狀況皆須播放」，所以提示音會在 `main.dart` 收到緊急
  /// 通話的當下就開始響，本畫面只是**補播**（冷啟動時本畫面才是最早的觸發點）。
  /// 單例保證三條路只會有一顆播放器，任何一處 `stop()` 都停得掉（護欄 G77）。
  Future<void> _playEmergencyTone() => EmergencyTone.instance.play();

  /// 停止並釋放緊急提示音。接通（`onPeerConnected`）與離開畫面時都會呼叫，
  /// 避免「已經看到對方了、提示音還在響」。
  Future<void> _stopEmergencyTone() => EmergencyTone.instance.stop();

  Future<void> _initElderMode() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onLocalStream = ((stream) {
      debugPrint("🤳 [ElderScreen] Local stream set! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onAddRemoteStream = ((stream) {
      debugPrint("📺 [ElderScreen] Remote stream added! Tracks: ${stream.getTracks().length}");
      // ★ 2026-08-05 第十七輪：onAddRemoteStream 只代表 SDP 談成，不代表 ICE 已連通、
      //   有任何媒體在流動，_startCallTimer() 改移到真正連上時才觸發的 onPeerConnected。
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _status = "通話中";
          _isInCall = true;
          _callDuration = 0;
        });
      }
    });

    // ★ 2026-08-05 第十七輪：ICE 真正連通時才開始計時，避免「有通話計時卻沒有影音」的假象。
    _signaling.onPeerConnected = () {
      // ★ 2026-08-11 第二十二輪（需求 9）：真的看到對方了就停掉緊急提示音，
      //   否則會出現「畫面已接通、警示音還在響」。
      _stopEmergencyTone();
      if (mounted) {
        _startCallTimer();
      }
    };

    _signaling.onJoinFailed = (errorMessage, {String? reason}) {
      // ★ issue 5：通話已建立時，忽略遲到的 join-failed（例如重新 join 房間時的競態），
      //   避免誤把進行中的通話導向「連線失敗」對話框，間接觸發 dispose -> hangUp ->
      //   end-call，導致家屬端被彈回主畫面、長輩端畫面變黑。
      if (_isInCall || _signaling.peerConnection != null) {
        debugPrint("⚠️ [ElderScreen] 忽略通話進行中收到的 join-failed: $errorMessage");
        return;
      }
      if (mounted) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 200), () {
          HapticFeedback.mediumImpact();
        });

        // ★ 2026-08-06 第十九輪（A5）：monitor-limit／ip_limit_exceeded 代表這台
        //   監視機從一開始就不該綁定成功（額度已滿），不是暫時性的連線問題。
        //   改用不可關閉的專屬「綁定失敗」畫面把原因講清楚，並提供「返回」
        //   走既有的 _exitCCTVMode() 清理流程（清 prefs、斷線、導回身分選擇畫面）。
        if (widget.isCCTVMode &&
            (reason == 'monitor-limit' || reason == 'ip_limit_exceeded')) {
          final String explanation = reason == 'monitor-limit'
              ? '此長輩的監控設備數量已達訂閱方案上限，請先在家屬端移除一台舊設備後再試。'
              : '同一網路下的監控設備數量已達上限。';
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('綁定失敗'),
              content: Text(explanation),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // 關閉對話框
                    _exitCCTVMode();
                  },
                  child: const Text('返回'),
                )
              ],
            ),
          );
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('連線失敗'),
            content: Text(
              (reason != null && reason.isNotEmpty)
                  ? '$errorMessage\n錯誤代碼：$reason'
                  : errorMessage,
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // 關閉對話框
                  // ★ issue 10：安全返回主畫面，避免 pop 後無上一頁造成黑屏
                  safeNavigateBack(context, _buildFallbackHome());
                },
                child: const Text('確定')
              )
            ],
          ),
        );
      }
    };

    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      debugPrint("✅ 家屬($accepterId) 已接聽 (CallId: $callId)，開始定向發送 Offer...");
      if (mounted) setState(() { _status = "連線建立中..."; _isInCall = true; });
      _signaling.createOffer(targetId: accepterId, isEmergency: false);
    };

    // ★ 只要是通話（無論是語音還是視訊），在連線前都必須初始化媒體以取得音訊軌道
    if (!_mediaInitialized) {
      await _initializeMedia();
    }

    // ★ 2026-08-04 第 7 項：只有監視機（CCTV）才推送影格做 YOLO 偵測。
    //   必須等 _initializeMedia 成功後才啟動，否則 localStream 還是 null，
    //   整個迴圈會空轉到相機就緒為止（雖然安全，但白費計時器）。
    if (widget.isCCTVMode && _mediaInitialized) {
      _startCctvFrameLoop();
    }


    // ★ 修復：從 SharedPreferences 讀取真正的 user_id（caregiver_id），
    //    而不是誤用 elder_id 當作 userId。
    //    elder_id（widget.roomId，如 '0343'）≠ user_id（資料庫帳號整數 ID）
    final prefs = await SharedPreferences.getInstance();
    final int? actualUserId = prefs.getInt('caregiver_id');
    final String? actualUserName = prefs.getString('caregiver_name');
    final dynamic resolvedUserId = actualUserId ?? widget.roomId;
    _userId = actualUserId;
    // ★ Issue 1 硬化：一併記住真實使用者名稱，供 _buildFallbackHome 導航使用，
    //   避免通話結束回退時錯用 widget.deviceName（裝置暱稱，非長輩本名）。
    _prefsUserName = actualUserName;
    
    // ★ 2026-08-05 第十八輪（需求 5）根因修復：
    //   原本「socket 已連線就完全不呼叫 connect()」會讓監控機在配對後
    //   停留在 comm_elder_<id>，永遠沒有以 deviceMode:'monitor' 加入
    //   monitor_elder_<id>，家屬端的遠端視訊列表因此永遠是空的。
    //   `Signaling.connect()` 內部已有「已連線則只重新 join」的重用分支
    //   （signaling.dart:169-173），不會重新註冊 listener 或覆寫 callback，
    //   因此一律呼叫是安全的，且能確保房間與 deviceMode 永遠正確。
    // ★ 2026-08-11 第二十一輪（需求 1）根因修復：這行原本是裸的
    //   `await FirebaseMessaging.instance.getToken()`，既沒有 try/catch 也沒有逾時。
    //   getToken() 在真機上會拋 `SERVICE_NOT_AVAILABLE` / `AUTHENTICATION_FAILED`，
    //   或在網路半死時長時間不回。第二十輪把「自動撥號」改成等
    //   `_initElderMode()` 完成（見 initState 的 .then），於是這一行一旦拋例外或卡住：
    //     1. 下方的 `_signaling.connect()` 永遠不會執行 → 長輩根本沒進房；
    //     2. initState 的 .then() 永遠不會觸發 → `_makeCall()` 從未被呼叫。
    //   結果就是使用者回報的「長輩端在 APP 內按下撥打完全沒反應」。
    //   FCM token 只影響「對端被殺死時的推播喚醒」，拿不到頂多退回純 socket 通知，
    //   絕不該連帶把進房與撥號一起擋掉——因此改為容錯取得。
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ [ElderScreen] 取得 FCM token 失敗／逾時，改以無 token 進房: $e');
    }
    debugPrint(
        "🔌 [ElderScreen] 加入房間 $_formattedRoomId "
        "(mode=${widget.isCCTVMode ? 'monitor' : 'comm'}, "
        "socketConnected=${_signaling.socket?.connected == true})");
    _signaling.connect(
      _formattedRoomId,
      'elder',
      userId: resolvedUserId,
      deviceName: widget.deviceName,
      deviceMode: widget.isCCTVMode ? 'monitor' : 'comm',
      fcmToken: fcmToken,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      _checkPendingEmergency();
      _checkPendingAcceptedCall();
      if (widget.initialCallData != null) {
        final senderId = widget.initialCallData!['senderId']?.toString();
        final callId = widget.initialCallData!['callId']?.toString();
        final isEmergency = widget.initialCallData!['isEmergency'] == 'true' || widget.initialCallData!['isEmergency'] == true;
        if (senderId != null) {
          debugPrint("📞 [ElderScreen] Handling initialCallData: senderId=$senderId, isEmergency=$isEmergency");
          if (isEmergency) {
            _handleEmergencyAccept(senderId, callId: callId);
          } else {
            _handleAcceptedCallFromBackground(senderId, callId: callId);
          }
        }
      }
    });

    // ★ Issue 1：緊急通話強制開啟攝像頭
    final bool isEmergencyCall = widget.initialCallData?['isEmergency'] == 'true' ||
                                  widget.initialCallData?['isEmergency'] == true;
    if (isEmergencyCall && _signaling.localStream != null) {
      debugPrint("🚨 [ElderScreen] 緊急通話：強制開啟攝像頭");
      for (var track in _signaling.localStream!.getVideoTracks()) {
        track.enabled = true;
      }
      if (mounted) setState(() => _isCameraOff = false);
    }

    _signaling.onCallEnded = () {
      _callTimer?.cancel();
      _activeCallId = null;
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "通話結束";
          _isInCall = false;
        });

        // ★ 只有非 CCTV 模式才退出畫面
        if (!widget.isCCTVMode) {
          // ★ issue 3/10：通話結束後安全返回，若無上一頁則回到長輩主畫面，避免黑屏
          safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    _signaling.onCallBusy = (targetId, callId) {
      if (mounted) {
        _showElderCallFailToast(callBusyMessageFor(_signaling.lastCallBusyReason));
        // ★ issue 15：對方拒接/忙線時，呼叫端結束「等待連線」狀態並安全返回
        _callTimer?.cancel();
        _activeCallId = null;
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "通話結束";
          _isInCall = false;
        });
        if (!widget.isCCTVMode) {
          safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    // ★ issue 5：通話中發生無法復原的連線中斷（已超過 signaling.dart 的 2 秒重連寬限期）
    _signaling.onConnectionLost = () {
      _callTimer?.cancel();
      if (!mounted) return;

      // ── 一般通話路徑：與第二十二輪修改前**完全相同**，不得更動 ──
      if (!widget.isCCTVMode) {
        _showElderCallFailToast(kCallFailDisconnected);
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "連線中斷";
          _isInCall = false;
        });
        safeNavigateBack(context, _buildFallbackHome());
        return;
      }

      // ── 監控機路徑（★ 2026-08-11 第二十二輪／需求 6）──
      //   監控機斷線有兩種完全不同的成因，過去一律顯示「連線中斷」：
      //     (a) 網路真的斷了 → 「連線中斷」才是實話
      //     (b) 家屬端把這台監控設備刪掉了，後端把它踢線 → 設備明明還在運轉，
      //         使用者卻看到「連線中斷」，只會以為是自己家的網路壞了。
      //   這裡不再走 `_showElderCallFailToast`（那是「沒接通」的通話語意，
      //   監控機沒有在通話），也不導航——監控機被刪除的導航由
      //   `onMonitorRemoved` 負責（它會先 releaseSession 再回身分選擇頁）。
      setState(() {
        _remoteRenderer.srcObject = null;
        _isInCall = false;
        _status = _monitorRemoved ? "該監控機已被刪除" : "連線中斷，檢查中…";
      });
      if (!_monitorRemoved) {
        // `monitor-removed` 事件與「被踢線」的到達順序不保證，甚至可能因為
        // socket 先斷而永遠收不到事件，所以再用 REST 清單交叉驗證一次。
        _verifyMonitorStillExists();
      }
    };

    // ★ 2026-08-05 第十七輪：ICE 連線失敗時據實回報並安全返回主畫面，避免通話停在
    //   「已連線」卻完全沒有影音的假狀態。沿用本檔既有的「掛斷後安全導航」方法。
    _signaling.onPeerConnectionFailed = (msg) {
      _callTimer?.cancel();
      if (mounted) {
        debugPrint('⚠️ [ElderScreen] PeerConnection 失敗: $msg');
        _showElderCallFailToast(kCallFailUnreachable);
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "連線失敗";
          _isInCall = false;
        });
        if (!widget.isCCTVMode) {
          safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    // ★ 2026-08-11 第二十二輪（需求 8）：這是本畫面唯一一個**直接掛在 socket 上**
    //   的原生監聽（其餘都是 Signaling 的 callback 欄位，dispose() 時設 null 即可解除）。
    //   過去它註冊後**從不解除**：離開監控機、回到長輩端、再進通話畫面，
    //   同一個 socket 上就疊了好幾份 force-logout handler，各自持有已 dispose 的
    //   State 與 BuildContext；一旦後端真的送 force-logout，多份 handler 併發
    //   remove prefs 並各自 pushAndRemoveUntil，正是使用者回報的
    //   「在後台徹底死機（ANR）」的成因之一。
    //   存成欄位，dispose() 時用 socket.off('force-logout', _forceLogoutHandler) 精準移除
    //   （**不可**用不帶 handler 的 off()，那會把其他地方註冊的同名監聽一併清掉）。
    _forceLogoutHandler = (_) async {
      debugPrint('🚪 [ElderScreen] force-logout 觸發');
      final prefs = await SharedPreferences.getInstance();
      // ★ Issue 3 硬化：force-logout 只應清除「登入/角色/裝置身分」相關鍵，
      //   不可用 prefs.clear() 清光全部本機資料，避免波及與登入狀態無關的設定。
      const List<String> keysToRemove = [
        'caregiver_id',
        'caregiver_name',
        'user_role',
        'saved_role',
        'saved_id',
        'saved_device_name',
        'saved_is_cctv',
        'elder_room_id',
        'access_token',
        // ★ 2026-07-27 第十三輪：force-logout 是家屬端「強制解綁本裝置」，
        //   語意上這台裝置已被移除授權，不該還能用「快速登入同一長輩」一鍵登回，
        //   故連快速登入記憶鍵一併清除。（使用者自己按「切換身分／登出」則保留。）
        'last_elder_id',
        'last_elder_name',
        'last_elder_room_id',
        'last_elder_device_role',
      ];
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
      final deviceRoleKeys =
          prefs.getKeys().where((k) => k.startsWith('device_role_')).toList();
      for (final key in deviceRoleKeys) {
        await prefs.remove(key);
      }
      if (mounted) {
         Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const IdentificationScreen()),
          (route) => false,
        );
      }
    };
    _signaling.socket?.on('force-logout', _forceLogoutHandler!);

    _signaling.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [ElderScreen] Incoming Offer from $callerId (Type: $callType)");
      // ★ 只要是在 ElderScreen，就代表已經進入通話準備狀態，一律接聽！
      if (mounted) setState(() => _isInCall = true);
      return true;
    };

    _signaling.onHeartbeatMessage = (message) async {
      debugPrint("💓 [ElderScreen] Heartbeat: $message");
      if (mounted && !_isInCall) {
        String displayText = message;
        String type = 'chat';
        String emotion = 'caring';

        try {
          final data = jsonDecode(message);
          if (data is Map && data.containsKey('reply')) {
            displayText = data['reply'];
            type = data['type'] ?? 'chat';
            emotion = data['emotion'] ?? 'caring';
          }
        } catch (e) {
          debugPrint("Heartbeat is plain text or malformed JSON.");
        }

        // 統一顯示精美的毛玻璃對話框
        showDialog(
          context: context,
          barrierColor: Colors.black54,
          builder: (context) => HeartbeatOverlay(
            message: displayText,
            type: type,
            emotion: emotion,
            onDismiss: () => Navigator.pop(context),
          ),
        );

        // 語音播放
        FlutterTts flutterTts = FlutterTts();
        await flutterTts.setLanguage("zh-TW");
        await flutterTts.setVolume(1.0);
        await flutterTts.speak(displayText);
      }
    };

    // ★ 2026-08-06 第十九輪（D4）：監視機被家屬端改名時，同步更新本機記憶
    //   （SharedPreferences saved_device_name）與畫面內部狀態，避免退出監控時
    //   仍用改名前的舊名稱去比對後端（後端以 device_name 字串精確比對）。
    //   只在監視機模式註冊，一般通訊模式沒有「監控設備改名」這個概念。
    if (widget.isCCTVMode) {
      _signaling.onMonitorRenamed = (data) async {
        final String eventElderId = (data['elderId'] ?? '').toString();
        final String oldName = (data['oldDeviceName'] ?? '').toString();
        final String newName = (data['newDeviceName'] ?? '').toString();
        if (newName.isEmpty) return;
        // 只處理「自己」被改名的事件：elderId 對得上、且事件回報的舊名稱與目前
        // 顯示名稱相同——避免同一長輩底下有多台監控設備時，誤把別台設備的
        // 改名事件套用到自己身上。
        if (eventElderId.isNotEmpty && eventElderId != _rawElderId) return;
        if (oldName.isNotEmpty && oldName != _currentDeviceName) return;
        debugPrint('✏️ [ElderScreen] 監視機已被改名: $_currentDeviceName → $newName');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_device_name', newName);
        if (mounted) {
          setState(() => _currentDeviceName = newName);
        }
      };

      // ★ 2026-08-10 第二十輪（需求 4＋5）：家屬端刪除本監視器時，立刻退回主畫面。
      //   過去後端只是把這台裝置踢線，監控機端無從區分「被刪除」與「網路斷線」，
      //   於是留在 CCTV 畫面等重連；使用者只好按「退出並重置」，而那條路徑
      //   舊版只清 7 個 prefs 鍵、不通知後端註銷 FCM token，於是 session 被綁死
      //   ——同一台裝置之後輸入正確綁定碼也一律「綁定碼過期或錯誤」（需求 5）。
      //   現在改為：收到事件 → 走 SessionManager 完整釋放 → pushAndRemoveUntil
      //   回身分選擇頁（護欄：回首頁一律 pushAndRemoveUntil，不可 pop）。
      _signaling.onMonitorRemoved = (data) async {
        final String eventElderId = (data['elderId'] ?? '').toString();
        final String deviceName = (data['deviceName'] ?? '').toString();
        // 同一長輩底下可能有多台監控設備，必須確認被刪的就是自己。
        if (eventElderId.isNotEmpty && eventElderId != _rawElderId) return;
        if (deviceName.isNotEmpty && deviceName != _currentDeviceName) return;
        debugPrint('🗑️ [ElderScreen] 本監視器已被家屬端刪除，釋放 session 並退回身分選擇頁');
        // ★ 2026-08-11 第二十二輪（需求 6）：**先立旗標、再做任何 await**。
        //   後端是「先 emit monitor-removed、再把這台踢線」，踢線觸發的
        //   onConnectionLost 極可能在下面 releaseSession() 的 await 期間插進來；
        //   旗標沒先立好，使用者就會先看到一瞬間的「連線中斷」。
        _monitorRemoved = true;
        if (mounted) setState(() => _status = "該監控機已被刪除");
        // 先釋放 session（含通知後端註銷 FCM token、forceDisconnect、清 prefs），
        // 再導航——順序顛倒的話畫面已切走、await 可能被中斷而漏清。
        await SessionManager.releaseSession();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const IdentificationScreen()),
          (route) => false,
        );
      };
    }

  }

  /// ★ 2026-08-11 第二十二輪（需求 6）：監控機斷線後，用 REST 交叉驗證
  /// 「這台監控設備是否還存在於家屬端清單」，據以把畫面上的
  /// 「連線中斷，檢查中…」定案成「該監控機已被刪除」或「連線中斷」。
  ///
  /// 為什麼不能只靠 `monitor-removed` 事件：後端刪除時是「先 emit、再踢線」，
  /// 但兩者都經由同一條已在崩解中的 socket，事件很可能根本送不到；
  /// 反過來若網路真的斷了，HTTP 也會失敗——所以用
  /// [ApiService.fetchMonitorDevicesOrNull]（失敗回 `null`、成功回清單）來區分：
  ///   - `null`（查詢失敗，含無權 404）→ 無從判斷 → 維持「連線中斷」
  ///   - 清單裡**找不到**自己 → 確定已被刪除
  ///   - 清單裡找得到自己 → 真的只是網路問題 → 「連線中斷」
  ///
  /// 這裡**只改文字、不導航**：被刪除的導航屬於 `onMonitorRemoved`
  /// （它會先 `SessionManager.releaseSession()` 再回身分選擇頁），
  /// 在這裡重複一次會變成兩條併行的清理路徑互相打架。
  Future<void> _verifyMonitorStillExists() async {
    final int? userId = _userId;
    if (userId == null) {
      if (mounted) setState(() => _status = "連線中斷");
      return;
    }
    List<dynamic>? devices;
    try {
      devices = await ApiService.fetchMonitorDevicesOrNull(
        elderId: _rawElderId,
        userId: userId,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('⚠️ [CCTV] 交叉驗證監控設備是否仍存在失敗（維持「連線中斷」）: $e');
      devices = null;
    }
    if (!mounted) return;
    if (devices == null) {
      setState(() => _status = "連線中斷");
      return;
    }
    final bool stillExists = devices.any((d) =>
        d is Map && (d['deviceName'] ?? '').toString() == _currentDeviceName);
    if (!stillExists) {
      debugPrint('🗑️ [CCTV] 交叉驗證：本監控機已不在家屬端清單中 → 判定為已被刪除');
    }
    setState(() {
      _monitorRemoved = !stillExists;
      _status = stillExists ? "連線中斷" : "該監控機已被刪除";
    });
  }

  /// ★ 2026-08-06 第十九輪（需求 3）：長輩端「沒接通」提示。
  /// 樣式沿用第十八輪需求 3 敲定的大字級＋深綠底，四種情境只換文案不換樣式。
  void _showElderCallFailToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A472A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        content: Row(
          children: [
            const Icon(Icons.phone_missed, color: Colors.white, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ★ 新增：懶加載媒體初始化
  Future<void> _initializeMedia() async {
    if (_mediaInitialized) return;
    try {
      // ★ 2026-08-10 第二十輪（D5）：ElderScreen 內鏡頭／麥克風硬體存取的唯一入口。
      //   本函式開頭已用 _mediaInitialized 擋掉重複呼叫（見上方 if (_mediaInitialized) return;），
      //   確保同一個畫面實例只會跟系統要一次硬體權限與媒體軌道。
      //   這裡固定不帶 videoEnabled 參數（沿用預設值 true）＝一律連視訊軌道一併要求，
      //   不是依當下 _isCameraOff 決定要不要開鏡頭；真正決定鏡頭是否可見／LED 是否亮起的
      //   是緊接在下面的 track.enabled = !_isCameraOff。之後使用者按下切換鏡頭鈕
      //   （_toggleCamera）也只是翻轉既有 track 的 enabled，並不會重新呼叫
      //   getUserMedia、也不會 replaceTrack 或重建 PeerConnection——維持本輪
      //   D5「不可加 replaceTrack、不可更動取得媒體時機」的要求。
      //   又因為 ElderScreen 只會在真正撥打／接聽通話或進入 CCTV 監控模式時才會被
      //   導航進入（非通話情境不會建立這個畫面），鏡頭與麥克風實質上只在通話／監控
      //   進行中才會被要求，並非在長輩主畫面背景常駐存取硬體。
      await _signaling.openUserMedia(_localRenderer);
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        for (var track in videoTracks) {
          track.enabled = !_isCameraOff; // 預設關閉，保護隱私
        }
      }

      // ★ 2026-08-05 第十八輪：無論是否開攝像頭，都要進入通話音訊模式，
      //   否則 setSpeakerphoneOn 在部分機型上不會生效。
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await Helper.setAndroidAudioConfiguration(
            AndroidAudioConfiguration.communication,
          );
        } catch (e) {
          debugPrint('⚠️ [ElderScreen] setAndroidAudioConfiguration 失敗: $e');
        }
      }
      _signaling.enableSpeakerphone(_isSpeakerOn);

      if (mounted) {
        setState(() => _mediaInitialized = true);
      }
    } catch (e) {
      debugPrint("❌ Media initialization failed: $e");
    }
  }

  // ★ 新增：切換攝像頭
  Future<void> _toggleCamera() async {
    if (!_mediaInitialized && !_isCameraOff) {
      await _initializeMedia();
    }
    
    if (!_mediaInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('攝像頭初始化失敗')),
        );
      }
      return;
    }

    if (mounted) {
      final bool turningCameraOn = _isCameraOff; // 切換前是關的，代表這次操作是要開鏡頭
      // ★ 2026-08-10 第二十輪（D4）：語音通話中途開鏡頭時，比照一般通話 App 的習慣
      //   自動切成擴音（用鏡頭代表要跟對方視訊互動，貼耳聽筒既拿不穩也看不到畫面）。
      //   只在「原本是語音通話、且擴音目前是關的」時觸發一次，用 _speakerAutoSwitched
      //   確保整通電話只自動切一次——使用者若切回聽筒後再開一次鏡頭，不會被再次強制拉回擴音。
      final bool shouldAutoSwitchSpeaker = turningCameraOn &&
          !widget.isVideoCall &&
          !widget.isCCTVMode &&
          !_isSpeakerOn &&
          !_speakerAutoSwitched;

      setState(() {
        _isCameraOff = !_isCameraOff;
        if (shouldAutoSwitchSpeaker) {
          _isSpeakerOn = true;
          _speakerAutoSwitched = true;
        }
      });

      if (_isCameraOff) {
        _signaling.localStream?.getVideoTracks().forEach((track) => track.enabled = false);
      } else {
        _signaling.localStream?.getVideoTracks().forEach((track) => track.enabled = true);
      }

      if (shouldAutoSwitchSpeaker) {
        _signaling.enableSpeakerphone(true);
        debugPrint("🔊 [ElderScreen] 語音通話中開啟鏡頭，自動切換為擴音");
      }
    }
  }

  // ★ issue 12：切換前後鏡頭
  Future<void> _switchCamera() async {
    final videoTracks = _signaling.localStream?.getVideoTracks();
    if (videoTracks == null || videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    if (mounted) {
      setState(() => _isFrontCamera = !_isFrontCamera);
    }
  }

  // ★ 新增：切換靜音
  void _toggleMute() {
    if (mounted) {
      setState(() => _isMuted = !_isMuted);
      _signaling.localStream?.getAudioTracks().forEach((track) => track.enabled = !_isMuted);
    }
  }

  /// ★ 2026-08-05 第十八輪（需求 1）：切換音訊輸出來源。
  /// 與攝像頭狀態完全無關——關鏡頭的純語音通話一樣可以切換擴音／聽筒（比照 LINE）。
  void _toggleSpeaker() {
    if (!mounted) return;
    // ★ 2026-08-10 第二十輪（需求 9）：使用者手動選過之後就不再自動切換。
    _speakerAutoSwitched = true;
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _signaling.enableSpeakerphone(_isSpeakerOn);
    debugPrint("🔊 [ElderScreen] 音訊輸出切換為 ${_isSpeakerOn ? '擴音' : '聽筒'}");
  }

  // ★ 新增：通話計時器
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  /// ★ 2026-08-05 第十七輪：暫時性測試入口——模擬 YOLO 判定跌倒。
  /// 後端 `POST /api/cctv/test-fall` 走的是與真實偵測完全相同的
  /// `dispatch_yolo_alert()`（寫入 emergency_alerts → Socket 'cctv-alert' → FCM 高優先級），
  /// 只跳過「影像判定」那一段。YOLO 可實測後，此方法與對應按鈕可一併移除。
  Future<void> _sendTestFallAlert() async {
    if (_testFallSending) return;
    setState(() => _testFallSending = true);
    // 🚨 必須傳 _rawElderId（去掉 monitor_elder_ / comm_elder_ 前綴的原始 elder_id）。
    //    後端以 monitor_device_id(elder_id, device_name) 推導 device_id，
    //    若送整串 room_id，推導值會與 /cctv/frame 那條路徑算出來的不一致，
    //    家屬端的設備卡片高亮就永遠對不上。
    // ★ 2026-08-05 第十七輪（安全）：後端此端點預設關閉，回傳的字串即為原因
    //   （未啟用開關／密鑰錯誤／查無此監視機），null 才代表成功。
    //   直接把原因顯示出來，否則使用者只會看到「送出失敗」而不知道要去 .env 開開關。
    final err = await ApiService.triggerTestFall(
      elderId: _rawElderId,
      deviceName: widget.deviceName,
    );
    if (!mounted) return;
    setState(() => _testFallSending = false);

    // ★ 2026-08-11 第二十二輪（需求 2）：後端 `CCTV_TEST_FALL_ENABLED` 預設 false，
    //   回的原文是「測試端點未啟用（請在後端 .env 設定 CCTV_TEST_FALL_ENABLED=true）」，
    //   使用者看到只會以為是 App 壞了。這裡把它換成「說明這不是故障、以及該找誰開」的
    //   完整句子；**其餘錯誤字串一律原樣顯示**（密鑰錯誤／查無此監視機都要看得到原因）。
    //   ⚠️ 這是純 UI 文案，`triggerTestFall` 的回傳語意（null=成功）完全不動。
    final bool disabledByServer = err != null && err.contains('測試端點未啟用');
    final String message = disabledByServer
        ? '測試端點未啟用。這是後端的安全預設值，不是 App 故障——'
            '需由伺服器管理者在後端 .env 設定 CCTV_TEST_FALL_ENABLED=true 並重啟服務後才能使用。'
        : (err ?? '已送出跌倒測試警報');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: err == null ? 2 : (disabledByServer ? 10 : 6)),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // 主動呼叫 (先響鈴)
  Future<void> _makeCall() async {
    setState(() { _status = "正在呼叫家人..."; _isInCall = true; });
    // ★ 2026-08-10 第二十輪（D1-d）：sendCallRequest 現在會回傳是否成功送出
    //   （內部會等待 socket 連線，逾時視為失敗）。過去無論是否送出成功都直接
    //   進入 30 秒逾時計時，socket 尚未連上時長輩端會白白卡在「正在呼叫家人...」
    //   30 秒，期間其實從頭到尾沒送出任何請求。
    final bool sent = await _signaling.sendCallRequest(
      _formattedRoomId,
      role: 'elder',
      isVideoCall: widget.isVideoCall,
    ); // ★ 使用格式化的房間ID
    if (!mounted) return;
    if (!sent) {
      setState(() {
        _status = "連線中斷，無法撥出";
        _isInCall = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法連上伺服器，請確認網路後再試')),
      );
      return;
    }
    _armCallTimeout();
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：撥打「世代編號」。
  ///
  /// 與家屬端 `video_call_screen.dart::_connectAttempt` 同一套機制：
  /// `Future.delayed` 無法取消，使用者選「重新撥打」後舊那一顆仍會在原定
  /// 時間醒來，靠世代比對讓它變成 no-op，否則會冒出第二個逾時對話框。
  int _callAttempt = 0;

  /// ★ 2026-08-12 第二十三輪（需求 3）：啟動一次 30 秒撥打逾時看門狗。
  void _armCallTimeout() {
    final int attempt = ++_callAttempt;
    // ★ 2026-07-18：長輩端主動撥打新增 30 秒逾時。原本完全沒有逾時，
    //   家屬未接時只能靠手動掛斷，被叫方 CallKit 也會一直響。逾時自動取消。
    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (attempt != _callAttempt) return; // 已重新撥打，這一輪作廢
      if (_status != "正在呼叫家人...") return;
      _handleCallTimeout();
    });
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：家屬沒有接聽。
  ///
  /// 舊行為是把狀態字改成「對方未接聽」後**直接**退回主畫面，長輩根本來不及
  /// 看清楚發生什麼事，也沒有再撥一次的機會（要重新從主畫面點一次）。
  /// 改為與家屬端共用的 [showCallRetryDialog]：離開通話，或重新撥打。
  Future<void> _handleCallTimeout() async {
    debugPrint("⏰ [ElderScreen] 撥打逾時，自動取消通話");
    _signaling.sendCancelCall(_formattedRoomId, role: 'elder');
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    if (!mounted) return;
    setState(() {
      _remoteRenderer.srcObject = null;
      _status = "對方未接聽";
      _isInCall = false;
    });

    // ★ CCTV 監控機不彈對話框：它旁邊沒有人可以操作，彈出後會永久卡在畫面上
    //   （護欄 G56「監控機自動接聽必須完全靜默」的同一精神）。維持原本的
    //   「留在監控模式、不導航」行為。
    if (widget.isCCTVMode) return;

    final CallRetryChoice? choice = await showCallRetryDialog(
      context,
      title: '家人沒有接聽',
      message: '要離開通話畫面，還是重新撥打一次？',
      largeText: true, // 長輩端字級加大
    );
    if (!mounted) return;

    if (choice == CallRetryChoice.retry) {
      // `_makeCall()` 自己會重設 _status / _isInCall 並重新武裝逾時看門狗。
      _makeCall();
    } else {
      safeNavigateBack(context, _buildFallbackHome());
    }
  }

  void _hangUp() {
    // If we are hanging up while the status is "正在呼叫家人..." (Calling Family),
    // it means the family hasn't answered yet. We should send a cancel-call so 
    // the family's CallKit dismisses.
    if (_status == "正在呼叫家人...") {
      _signaling.sendCancelCall(_formattedRoomId);  // ★ 使用格式化的房間ID
    }
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    setState(() {
      _remoteRenderer.srcObject = null;
      _status = "通話結束";
      _isInCall = false;
    });

    // ★ 只有非 CCTV 模式才自動回到首頁
    if (!widget.isCCTVMode) {
      // ★ issue 3/10：安全返回，若無上一頁則回到長輩主畫面，避免黑屏
      safeNavigateBack(context, _buildFallbackHome());
    }
  }

  // ★ issue 3/10：安全導航用的長輩主畫面（在無法 pop 時作為退路）
  Widget _buildFallbackHome() {
    return ElderHomeScreen(
      userId: _userId ?? 0,
      // ★ Issue 1 硬化：優先使用 prefs 讀到的真實 caregiver_name，
      //   讀不到才退回舊有的 widget.deviceName（裝置暱稱）。
      userName: _prefsUserName ?? widget.deviceName,
      roomId: widget.roomId,
    );
  }

  Future<void> _exitCCTVMode() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('退出監視機模式'),
        content: const Text('確定要退出監視機模式並重新選擇身分？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('退出並重置'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ★ 2026-08-10 第二十輪（需求 5）：這裡原本只 remove 七個 prefs 鍵，
      //   漏掉 `access_token`、`user_id`、`elder_room_id`、`device_role_*` 等等，
      //   而且**從不通知後端註銷 FCM token**。後果就是使用者回報的：
      //   同一台裝置曾當過監控機、退出並重置之後，再輸入正確的 6 位綁定碼
      //   一律顯示「綁定碼過期或錯誤」——因為後端 `user_fcm_token` 仍留著這台
      //   裝置綁在舊長輩房間的列，而殘留的 `device_role_*` 又讓本機自我判定
      //   成監控機，兩邊狀態互相打架。
      //   改走 SessionManager 這唯一入口（見 services/session_manager.dart），
      //   任何新的登出／退出路徑都不得再自行 remove 鍵位。
      //   刪除設備 API 必須排在 releaseSession() **之前**：releaseSession 會清掉
      //   caregiver_id 等鍵，且 deleteMonitorDevice 需要它們才能通過後端授權。

      // ★ 2026-08-11 第二十二輪（需求 8）：**先停推幀、先還相機，再做其他清理。**
      //   使用者回報「從監視機跳回長輩端後，通話完全不能用，還有 >50% 機率 ANR」。
      //   其中一半的根因就在這裡：這條退出路徑從不釋放 `localStream`。
      //   監控機模式下相機是**一直開著**在推幀的，退出時只 releaseSession + 導航，
      //   攝影機與麥克風軌道就一路活到下一個畫面；接著長輩端要通話時
      //   `openUserMedia()` 會去搶同一顆相機，Android Camera2 在被佔用時
      //   不是丟例外而是**卡住不返回**——按下「接聽」沒有任何反應、
      //   `createOffer` 永遠等不到 localStream，主執行緒被拖住就變成系統的
      //   「要停止還是等待」對話框。
      //   排在 `deleteMonitorDevice` 之前：釋放相機是純本機操作、不需要網路，
      //   不該被一個可能逾時的 HTTP 請求擋住。
      _cctvFrameTimer?.cancel();
      _cctvFrameTimer = null;
      _cctvFrameSending = false;
      try {
        _signaling.stopMedia();
        _localRenderer.srcObject = null;
        _mediaInitialized = false;
      } catch (e) {
        debugPrint('⚠️ [ElderScreen] 退出監控時釋放媒體失敗（續行）: $e');
      }

      // ★ 2026-08-06 第十九輪（D4）：監視機主動退出監控模式時，同步通知後端刪除
      //   這台監控設備，家屬端的遠端監控清單才不會留下永久殘影。走 HTTP REST，
      //   不依賴 socket 是否還活著，故排在 forceDisconnect() 之前呼叫。
      //   elderId 用 _rawElderId（純 elder_id，與後端 device_id 推導基準一致）、
      //   deviceName 用 _currentDeviceName（若中途被 monitor-renamed 改過名，
      //   後端是用「改名後」的名稱比對，仍送初始的 widget.deviceName 會比對不到
      //   而刪除失敗）、userId 用已快取的 _userId（此時 caregiver_id 已被上面的
      //   prefs.remove 清掉，此刻才去重新讀 prefs 會拿到 null）。
      //   成功與否都不影響既有清理流程——刪除失敗頂多是家屬端清單殘影，
      //   不該卡住長輩端本身的登出流程。
      try {
        await ApiService.deleteMonitorDevice(
          elderId: _rawElderId,
          deviceName: _currentDeviceName,
          userId: _userId,
        );
      } catch (e) {
        debugPrint('⚠️ [ElderScreen] 退出監控時刪除設備失敗（不影響登出流程）: $e');
      }

      // SessionManager 內部已包含 clearSession() + forceDisconnect()，
      // 不需要（也不可以）在這裡再呼叫一次 disconnect()。
      await SessionManager.releaseSession();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const IdentificationScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _cctvFrameTimer?.cancel();  // ★ 第 7 項：離開監視機畫面必須停止推幀，否則相機釋放後會持續拋例外
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    // ★ 2026-08-11 第二十二輪（需求 8）：解除本畫面掛在 socket 上的原生監聽。
    //   必須帶上 handler 參數精準移除；不帶參數的 off('force-logout') 會連
    //   其他地方註冊的同名監聽一起清掉。
    if (_forceLogoutHandler != null) {
      try {
        _signaling.socket?.off('force-logout', _forceLogoutHandler);
      } catch (e) {
        debugPrint('⚠️ [ElderScreen] 解除 force-logout 監聽失敗（續行）: $e');
      }
      _forceLogoutHandler = null;
    }

    // ★ 修復：只結束 WebRTC，不要斷開 Socket，這樣回到 ElderHomeScreen 時才能繼續接收推播
    // ★ 2026-08-11 第二十二輪（需求 8）：`disposeLocalStream` 改為**視模式而定**。
    //   一般通話仍維持 `false`（原行為不變：通話結束後 localStream 留著，
    //   下一通可以立刻復用、不必重開相機，這是接通速度的一部分）。
    //   監控機（CCTV）模式則必須 `true`：監控機的相機是長時間持續開啟的，
    //   離開畫面卻不釋放，下一個畫面要用相機時 Android Camera2 會卡死不返回
    //   （「按接聽沒反應」＋ ANR）。`_exitCCTVMode()` 已先釋放過一次，
    //   這裡是涵蓋其他離開路徑（被刪除、force-logout、系統回收）的兜底。
    _signaling.hangUp(
      disconnectSocket: false,
      disposeLocalStream: widget.isCCTVMode,
    );

    // ★ 2026-08-05 第十八輪（需求 4）：通話畫面離開 → 還原鎖屏行為，讓裝置回到原本的螢幕鎖。
    //   `showOverLockScreen()` 會設 setShowWhenLocked(true) + FLAG_KEEP_SCREEN_ON，
    //   不還原的話 APP 會永久蓋在鎖定畫面之上、螢幕也永不休眠。
    //   監控機（CCTV）刻意排除——它本來就必須維持恆亮才能持續推幀。
    //   這裡涵蓋所有離開路徑（掛斷／對方掛斷／忙線／斷線／連線失敗／撥打逾時），
    //   它們最終都會讓本 route 被 pop 或 pushAndRemoveUntil 移除而觸發 dispose()。
    if (!widget.isCCTVMode) {
      const MethodChannel('com.example.app/bring_to_front')
          .invokeMethod('restoreLockScreen')
          .catchError((e) {
        debugPrint('⚠️ [ElderScreen] restoreLockScreen 失敗: $e');
        return null;
      });
    }


    // ★ 清空 UI 相關的 callbacks，讓全域的 callbacks 重拾控制權
    _signaling.onCallAcceptedByRemote = null;
    _signaling.onCallBusy = null;
    _signaling.onCallEnded = null;
    _signaling.onConnectionLost = null;
    _signaling.onPeerConnected = null;
    _signaling.onPeerConnectionFailed = null;
    _signaling.onAddRemoteStream = null;
    _signaling.onLocalStream = null;
    _signaling.onJoinFailed = null;
    _signaling.onIncomingCall = null;
    _signaling.onHeartbeatMessage = null;
    _signaling.onMonitorRenamed = null;
    _signaling.onMonitorRemoved = null;

    // ★ 2026-08-11 第二十二輪（需求 9）：離開畫面一定要停掉緊急提示音，
    //   否則掛斷後音效還會繼續在背景播完剩下的秒數。
    _stopEmergencyTone();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder(
        valueListenable: pendingAcceptedCall,
        builder: (context, pendingCall, _) {
          return Stack(
            children: [
              // 1. 全螢幕視訊區塊
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF121212),
                  child: widget.isCCTVMode
                      ? RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : _remoteRenderer.srcObject != null
                          ? RTCVideoView(
                              _remoteRenderer,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isInCall)
                                    const CircularProgressIndicator(color: Colors.orangeAccent),
                                  const SizedBox(height: 24),
                                  Text(
                                    _status,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                ),
              ),

              // 2. 本地 PIP（僅雙向通話模式顯示）
              if (!widget.isCCTVMode)
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 20,
                  width: 110,
                  height: 160,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),

              // ★ CCTV 模式：頂部退出按鈕與底部「CCTV 監視中」標籤
              if (widget.isCCTVMode) ...[
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 16,
                  child: GestureDetector(
                    onTap: _exitCCTVMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            '退出監視機',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ★ 2026-08-05 第十七輪：暫時性的跌倒測試入口，位於「退出監視機」正下方。
                //   按下後走與 YOLO 真實偵測完全相同的派送路徑（見 _sendTestFallAlert）。
                //   YOLO 可實測後，這整個 Positioned 可以直接刪除。
                Positioned(
                  top: MediaQuery.of(context).padding.top + 56,
                  right: 16,
                  child: GestureDetector(
                    onTap: _testFallSending ? null : _sendTestFallAlert,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_testFallSending)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          else
                            const Text('🚨', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          const Text(
                            '跌倒測試',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'CCTV 監視中…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],

                            // 4. 底部控制列 (大按鈕，便於操作)
              if (!widget.isCCTVMode)
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ★ 通話時長顯示（僅在通話中顯示）
                      if (_isInCall)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: Text(
                              '通話時間: ${_formatDuration(_callDuration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      
                      // ★ 通話控制按鈕（水平排列）
                      if (_isInCall)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // 攝像頭開關
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: FloatingActionButton(
                                  onPressed: _toggleCamera,
                                  heroTag: 'camera',
                                  mini: true,
                                  backgroundColor: _isCameraOff ? Colors.grey.shade600 : Colors.blue.shade500,
                                  child: Icon(
                                    _isCameraOff ? Icons.videocam_off : Icons.videocam,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              
                              // ★ issue 12：前後鏡頭切換按鈕
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: FloatingActionButton(
                                  onPressed: _isCameraOff ? null : _switchCamera,
                                  heroTag: 'switchCamera',
                                  mini: true,
                                  backgroundColor: _isCameraOff ? Colors.grey.shade400 : Colors.blue.shade500,
                                  child: Icon(
                                    _isFrontCamera ? Icons.cameraswitch : Icons.cameraswitch_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              // 靜音按鈕
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: FloatingActionButton(
                                  onPressed: _toggleMute,
                                  heroTag: 'mute',
                                  mini: true,
                                  backgroundColor: _isMuted ? Colors.red.shade600 : Colors.blue.shade500,
                                  child: Icon(
                                    _isMuted ? Icons.mic_off : Icons.mic,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              // ★ 2026-08-05 第十八輪（需求 1）：擴音／聽筒切換
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: FloatingActionButton(
                                  onPressed: _toggleSpeaker,
                                  heroTag: 'speaker',
                                  mini: true,
                                  backgroundColor: _isSpeakerOn ? Colors.blue.shade500 : Colors.grey.shade600,
                                  child: Icon(
                                    _isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              // 掛斷按鈕（紅色、較大）
                              GestureDetector(
                                onTap: _hangUp,
                                child: Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.shade300.withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.call_end, color: Colors.white, size: 48),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        // 呼叫按鈕（未在通話中時）
                        GestureDetector(
                          onTap: _makeCall,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                              ),
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call, color: Colors.white, size: 28),
                                SizedBox(width: 12),
                                Text(
                                  "呼叫家人",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // 5. 測試/登出按鈕 (已移除，避免長輩誤觸登出)
            ],
          );
        },
      ),
    );
  }
}
