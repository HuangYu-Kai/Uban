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

  /// ★ 第四十二輪：長輩↔長輩好友通話。
  ///
  /// `null`（預設）＝現有行為完全不變：以 `role:'elder'` 加入 `widget.roomId`
  /// （呼叫者自己）的房間。
  ///
  /// 非 `null` 時＝本次要以 `role:'friend'` 加入**對方**（此欄位指定的
  /// elder_id）的 `comm_elder_<對方>` 房間撥打，`widget.roomId` 仍維持「呼叫者
  /// 自己的房間」語意不變（供 [_buildFallbackHome] 等既有邏輯使用）。
  /// 後端 `_verify_room_access` 會查呼叫者與對方之間是否存在 `status='accepted'`
  /// 的 `elder_friendship` 才放行，且只能進 `comm_elder_*`（不可為監控房）。
  final String? friendCallTargetElderId;

  const ElderScreen({
    super.key,
    required this.roomId,
    this.isCCTVMode = false,
    this.deviceName = 'Elder Device',
    this.autoCall = false,
    this.isVideoCall = true, // 預設視訊通話
    this.initialCallData,
    this.friendCallTargetElderId,
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

  /// ★ 2026-08-25：最近一次 `pushCctvFrame` 結果的繁體中文說明，顯示在 CCTV
  /// 畫面上——使用者無法查後端 log 或呼叫診斷端點，只能站在監視機前面看畫面，
  /// 故把後端早退原因（`yolo_disabled`／`busy_frame_dropped`…）直接翻成人看得懂
  /// 的句子。純顯示用途，見 [_recordCctvPushResult]。
  String _cctvPushStatusText = '尚未推送影格';

  /// 與 [_cctvPushStatusText] 成對的後端原始 reason 字串（或 transportError
  /// sentinel），小字顯示、方便使用者原樣回報給我們核對。`null` 代表尚無結果，
  /// 或本次推送 `detected == true`（後端不帶 reason）。
  String? _cctvPushRawReason;

  /// ★ 2026-08-26：`reason == 'yolo_unavailable'` 時後端一併帶回的
  /// `load_error`（見 [CctvPushResult.loadError]／`routers/alert.py`）——
  /// 使用者不是伺服器管理員，查不了 `/cctv/yolo_status` 之類的診斷端點，
  /// 這是他們唯一拿得到、可以原樣回報給我們核對的「偵測器為什麼沒載入」線索。
  /// `null` 代表尚無結果，或本次推送的 reason 不是 `yolo_unavailable`。
  String? _cctvPushLoadError;

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
  bool _isExiting = false; // ★ 退出監控/刪除重入防護，避免與 onMonitorRemoved 競爭

  /// ★ 2026-08-23：本畫面「離場只做一次」的重入防護。
  ///
  /// 起因：對方掛斷時後端 `end-call` 觸發 [Signaling.onCallEnded]，幾乎同一
  /// 時刻 WebRTC 連線也會斷線觸發 [Signaling.onConnectionLost]（有時還加上
  /// [Signaling.onPeerConnectionFailed]）——三者是各自獨立偵測到「這通電話
  /// 結束了」的回呼，不是同一事件的重複觸發，卻都會呼叫 `safeNavigateBack`
  /// 想清空導航堆疊回到主畫面。第一次呼叫已經把 `ElderScreen` 從堆疊上換
  /// 掉，但 State 要到下一個 frame 才真正 dispose，第二次呼叫發生當下
  /// `context.mounted` 仍是 true，若不攔下就會在已經清空過一次的堆疊上再
  /// 操作一次，輕則多餘重繪、重則直接卡死（白屏／黑屏、無法操作）。
  ///
  /// 與 `globals.dart::safeNavigateBack` 新增的 `ModalRoute.isCurrent` 檢查
  /// 是兩道互補防線：那一層擋的是「路由本身是否還在最上層」的通用防呆，
  /// 這一層擋的是「本畫面自己是否已經決定要走」的畫面內狀態，任一道生效
  /// 都足以擋下重入。
  ///
  /// 只在**確定即將呼叫** `safeNavigateBack` 的當下才設為 true，因此 CCTV
  /// 模式永遠不會把它設起——onCallEnded／onCallBusy／onConnectionLost／
  /// onPeerConnectionFailed／`_handleCallTimeout()`／`_hangUp()` 各自的
  /// `if (!widget.isCCTVMode)` 守衛，讓 CCTV 分支從不到達這個旗標。
  ///
  /// 🚫 刻意**不提供重置**：一旦真的離場，這個 State 實例的生命週期也隨之
  /// 結束（被 `pop()` 或被 `pushAndRemoveUntil()` 換掉），不存在「同一個
  /// 實例事後又重新撥打」的情境——`_makeCall()` 僅有的兩個呼叫點（initState
  /// 的 autoCall、`_handleCallTimeout()` 選擇「重新撥打」）都發生在尚未離場
  /// 之前。加一個沒有對應合法使用場景的重置，只會多一個「忘記重置」的
  /// 風險點。
  bool _navigatedAway = false;

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

  /// ★ 2026-08-25（需求 3）：這個畫面「進場當下」裝置是否處於鎖定狀態——
  /// 用來分辨「這通電話是從鎖屏／背景喚醒才進來的」還是「使用者本來就已經在
  /// App 裡」。只有前者結束通話（`dispose()`）時才呼叫原生
  /// `finishAndRemoveTask`，把整個 App 連同背景 Task 一併關閉、回到裝置的
  /// 鎖定畫面；長輩自己主動撥出／在 App 內接聽的一般情境完全不受影響。
  /// CCTV 監控模式恆為 false（見 initState／dispose 對應的 `!widget.isCCTVMode`
  /// 守衛）。查詢方式見 `MainActivity.kt::isKeyguardLocked()` 的完整說明
  /// （已知的唯一誤差方向是「低估」，不會錯殺使用中的畫面）。
  bool _enteredWhileLocked = false;

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
        final pushResult = await ApiService.pushCctvFrame(
          elderId: _rawElderId,
          // ★ 第十九輪（D4）：改用 _currentDeviceName（可隨 monitor-renamed 更新），
          //   避免改名後這個每 2 秒跑一次的迴圈仍持續用舊名稱推幀，
          //   導致 YOLO 偵測結果被後端歸到「改名前」的裝置、與家屬端看到的新名稱對不上。
          deviceName: _currentDeviceName,
          frameBytes: buffer.asUint8List(),
        ).timeout(const Duration(seconds: 10));
        _cctvFrameFailStreak = 0;
        _cctvLastFrameOkAt = DateTime.now();
        // ★ 2026-08-25：只是把這一幀的後端回應寫進畫面狀態，純顯示、不影響
        //   上面兩行的自癒計數；_recordCctvPushResult 內部自帶 try/catch，
        //   絕不會讓顯示邏輯反過來拖垮這個迴圈（見 G75）。
        _recordCctvPushResult(pushResult);
      } catch (e) {
        _cctvFrameFailStreak++;
        debugPrint('⚠️ [CCTV] 影格推送失敗（第 $_cctvFrameFailStreak 次，略過本輪，不中斷迴圈）: $e');
        _recordCctvPushResult(null);
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

  /// ★ 2026-08-25：把 [CctvPushResult] 翻成繁體中文，讓拿著監視機的人不必查
  /// 後端 log、不必呼叫任何診斷端點，站在裝置前面看畫面就知道「偵測到底有沒有
  /// 在跑」。純字串轉換，不做任何 I/O 或狀態異動。
  ///
  /// `result == null` 代表這一輪整段流程（擷取影格／呼叫 API／外層 10 秒逾時）
  /// 沒能得出任何結果，與 [ApiService.pushCctvFrame] 內部已知的 HTTP 層失敗
  /// （[CctvPushResult.transportError]）呈現同一句文案，因為對使用者而言兩者
  /// 都是「這一幀沒送出去」，差別只在於是否連到後端一事本身有沒有明確答案。
  String _describeCctvPushResult(CctvPushResult? result) {
    if (result == null) return '推送失敗';
    if (result.detected) return '偵測到異常';
    switch (result.reason) {
      case 'yolo_disabled':
        return '後端已停用此監視機的偵測';
      case 'busy_frame_dropped':
        return '伺服器忙碌，本幀略過';
      case 'yolo_unavailable':
        return '偵測器未載入';
      case 'no_event':
        return '偵測中，未發現異常';
      case 'unknown_elder':
        return '後端查無此長輩帳號';
      case 'server_error':
        return '伺服器內部錯誤';
      case CctvPushResult.transportError:
        return '推送失敗';
      default:
        return '狀態不明';
    }
  }

  /// ★ 2026-08-25：把最新一次推幀結果寫進畫面狀態，供 CCTV 畫面上的小標籤呈現
  /// （見 build() 內「CCTV 監視中…」旁邊那個 Positioned）。
  ///
  /// 🚫 純顯示用途，內部自帶 try/catch 吞掉一切例外（例如 `setState` 剛好在
  /// dispose 競態下被呼叫）——**絕不能**讓顯示邏輯反過來影響
  /// [_startCctvFrameLoop] 的三層自癒（見 CLAUDE_call-monitor.md §7 G75）。
  /// 呼叫端已經在 try 區塊內先完成 `_cctvFrameFailStreak`／`_cctvLastFrameOkAt`
  /// 的正常記帳才呼叫這裡，即使以下 setState 失敗也不影響那兩者。
  void _recordCctvPushResult(CctvPushResult? result) {
    if (!mounted) return;
    try {
      final text = _describeCctvPushResult(result);
      setState(() {
        _cctvPushStatusText = text;
        _cctvPushRawReason = result?.reason;
        // ★ 2026-08-26：同一顆 setState，同一層 try/catch——沿用既有機制，
        //   不為 loadError 另開一條路徑（見 CLAUDE_call-monitor.md §7 G75，
        //   顯示邏輯絕不能反過來影響三層自癒推幀迴圈）。
        _cctvPushLoadError = result?.loadError;
      });
    } catch (e) {
      debugPrint('⚠️ [CCTV] 更新推送狀態顯示失敗（不影響推幀迴圈）: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    // ★ 2026-08-24：通話畫面「進場」時開啟鎖屏覆蓋，與 dispose()（約 :1555）
    //   呼叫的 restoreLockScreen 對稱（見 CLAUDE_call-monitor.md §7 G49）。
    //   緊急通話透過背景 AndroidIntent 強制喚醒時會觸發原生
    //   onCreate/onNewIntent → showOverLockScreen()，但一般通話若只是把既有
    //   Activity 從背景恢復（CallKit 接聽，未必有新 Intent），原生端不會再
    //   次呼叫，於是沿用上一通通話結束時 restoreLockScreen 留下的
    //   setShowWhenLocked(false)，畫面就無法蓋過鎖定畫面——這正是「一般通話
    //   房間無法像緊急通話一樣繞過鎖定畫面」的成因。
    //   🚫 CCTV 監控模式（isCCTVMode）刻意不呼叫：dispose() 對監控模式本來就
    //   不呼叫 restoreLockScreen（監控機必須維持恆亮才能持續推幀，見
    //   dispose() 對應註解），若進場時蓋上鎖定畫面卻永遠不會在退出時還原，
    //   會變成「退出監控後 App 永久蓋在鎖定畫面之上」的隱私缺陷。這次需求
    //   只提到「一般通話房間」，監控模式維持現狀（不主動蓋鎖定畫面）。
    //   ⚠️ 這不是「強制開啟」：本畫面是使用者自己的操作（撥打／接聽）已經
    //   進入的畫面，這裡只讓它能蓋過鎖定畫面顯示，不呼叫 bringToFront，
    //   也不觸發任何 AndroidIntent——不要把它「升級」成強制喚醒。
    if (!widget.isCCTVMode) {
      const MethodChannel('com.example.app/bring_to_front')
          .invokeMethod('showOverLockScreen')
          .catchError((e) {
        debugPrint('⚠️ [ElderScreen] showOverLockScreen 失敗: $e');
        return null;
      });

      // ★ 2026-08-25（需求 3）：記錄「進場當下」是否鎖定，供 dispose() 決定
      //   要不要關閉整個 App（見 _enteredWhileLocked 欄位說明）。與上面的
      //   showOverLockScreen 同一個 `!isCCTVMode` 守衛——監控模式本來就不蓋
      //   鎖定畫面，也不該在退出監視機時把整個 App 關掉。
      const MethodChannel('com.example.app/bring_to_front')
          .invokeMethod('isKeyguardLocked')
          .then((locked) {
        if (mounted) _enteredWhileLocked = locked == true;
      }).catchError((e) {
        debugPrint('⚠️ [ElderScreen] isKeyguardLocked 查詢失敗: $e');
        return null;
      });
    }

    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _checkPermissions();
    
    // ★ 初始化格式化的房間ID
    // ★ 第四十二輪：好友通話進「對方」的房間；friendCallTargetElderId 為 null
    //   時（絕大多數情境）完全等同原本的 _getFormattedRoomId(widget.roomId)。
    _formattedRoomId = widget.friendCallTargetElderId != null
        ? _getFormattedRoomId(widget.friendCallTargetElderId!)
        : _getFormattedRoomId(widget.roomId);
    // ★ 第十九輪（D4）：CCTV 目前裝置名稱初始值，改名事件會更新它
    _currentDeviceName = widget.deviceName;

    // ★ 2026-08-20（FIX 2：喚醒畫面不再被 FCM token 卡住）：
    //   下面 _initElderMode() 會先 await 取得 FCM token（最多 5 秒逾時）才呼叫
    //   _signaling.connect()，而喚醒畫面的 _checkPendingEmergency() 又排在
    //   connect() 之後才觸發——網路差時 getToken() 真的會卡滿 5 秒，畫面因此多
    //   黑 5 秒才亮，但喚醒動作本身根本不需要 token。這裡不等待、不阻塞地提前
    //   「偷看」一次同樣的 pending_emergency_* 鍵位，命中就先把畫面喚醒；真正的
    //   接聽（sendCallAccept、prefs 清除、去重判斷）仍完整交給 _initElderMode()
    //   裡原封不動的 _checkPendingEmergency() 處理一次。詳見
    //   _earlyWakeForPendingEmergency() 的方法註解。
    _earlyWakeForPendingEmergency();

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

  /// ★ 2026-08-20（FIX 2）：[_checkPendingEmergency] 的「唯讀偷看」版本，供
  ///   initState 在 [_initElderMode] 等待 FCM token（最多 5 秒）之前就先呼叫，
  ///   讓螢幕喚醒不必等 token。刻意只做「讀 prefs → 比對房間 → bringToFront」，
  ///   **不**移除 prefs、**不**呼叫 [_handleEmergencyAccept]、**不**碰任何通話
  ///   狀態旗標——pending-emergency 這個呼叫點的 [_handleEmergencyAccept] 沒有帶
  ///   callId（見下方 [_checkPendingEmergency]），若被呼叫兩次不會被 callId 去重
  ///   擋下，反而會誤判成「另一通新來電」而把剛接通的緊急通話掛斷重連——正是
  ///   第十三輪修復過的問題。真正的接聽動作仍完全交給 [_checkPendingEmergency]
  ///   處理一次，本方法只負責讓畫面提早亮起來。
  Future<void> _earlyWakeForPendingEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingRoom = prefs.getString('pending_emergency_room');
    final pendingSender = prefs.getString('pending_emergency_sender');
    if (pendingRoom == null || pendingSender == null || !mounted) return;

    final bool isMatching =
        pendingRoom == _formattedRoomId || pendingRoom == widget.roomId;
    if (!isMatching) return;

    try {
      final platform = MethodChannel('com.example.app/bring_to_front');
      await platform.invokeMethod('bringToFront');
    } catch (e) {
      debugPrint('⚠️ [ElderScreen] 提前喚醒畫面失敗（稍後仍會由正常接聽流程重試）: $e');
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

    // ★ 2026-08-19 第二十九輪：喚醒被鎖屏／背景化的長輩畫面（Android 14+）。
    //   全專案唯一會點亮螢幕、蓋過鎖屏的機制就是這個 MethodChannel
    //   （`MainActivity.forceBringToFront()` → `showOverLockScreen()`，見 G49），
    //   而緊急通話過去完全沒有路徑呼叫到它——`_showIncomingCallDialog` 一偵測到
    //   長輩端緊急通話就直接短路進本函式，從未走過 `_navigateToVideoCall` 那條
    //   會叫它的路徑。結果是：即使下面 `sendCallAccept` 成功、`_isInCall` 也已經
    //   變 true，長輩端螢幕未開啟或被鎖屏時畫面仍是黑的／鎖定畫面，只有實體按下
    //   電源鍵才會發現「原來已經自動接聽了」。
    //   與 `_handleAcceptedCallFromBackground`（上方 :433-439）用完全相同的
    //   channel／method／錯誤處理，刻意放在 `sendCallAccept` 之前——即使接聽之後
    //   失敗，畫面也要先盡量喚醒。
    try {
      final platform = MethodChannel('com.example.app/bring_to_front');
      await platform.invokeMethod('bringToFront');
    } catch (e) {
      debugPrint("Bring to front failed (emergency): $e");
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
    // ★ 2026-08-19 第二十九輪：冷啟動（Firebase 初始化＋Flutter engine＋
    //   AndroidIntent 喚醒＋splash＋本畫面掛載）常規性地超過 sendCallAccept
    //   預設的 10 秒逾時，導致這個 accept 從未送出、家屬端只能乾等 60 秒逾時。
    //   緊急通話改傳 30 秒 maxWait；sendCallAccept 現在回傳 Future<bool>，
    //   送不出去時不再靜默——把「緊急通話接通中...」換成誠實的失敗文案，
    //   避免畫面卡在一個永遠不會連通的假狀態。
    final bool accepted = await _signaling.sendCallAccept(
      senderId,
      callId: callId,
      maxWait: const Duration(seconds: 30),
    );
    if (!mounted) return;
    if (!accepted) {
      setState(() {
        _status = "連線逾時，家屬端可能收不到接聽通知";
      });
    }
  }

  /// ★ 2026-08-25（第三十三輪）：一般通話在 ElderScreen 內收到 offer、但畫面上
  /// 沒有任何已同意紀錄時的接聽／拒絕選擇（見 `onIncomingCall` 回呼註解）。
  ///
  /// 畫面與動作刻意比照 `elder_home_screen.dart::_showIncomingCallDialog`——
  /// 同樣的 AlertDialog、綠色主題、圖示、「拒接」／「接聽」按鈕與
  /// `barrierDismissible: false`。沒有直接呼叫那個函式，是因為它是另一個
  /// State（`_ElderHomeScreenState`）的 private 方法，且接聽後還會自行
  /// `Navigator.push` 到新的 `ElderScreen`——本函式的呼叫情境是「已經身處
  /// ElderScreen」，不需要也不能重複那段導航，因此另外準備一份外觀對稱、
  /// 但動作範圍不同的版本，而不是新發明一套不同風格的 UI。
  Future<bool> _showNormalIncomingCallChoice() async {
    if (!mounted) return false;
    bool accepted = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.phone_in_talk, color: Colors.green, size: 28),
              ),
              const SizedBox(width: 12),
              const Text('家屬來電'),
            ],
          ),
          content: const Text('您的家人正在呼叫您！', style: TextStyle(fontSize: 18)),
          backgroundColor: Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                accepted = false;
                Navigator.of(dialogContext).pop();
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
                accepted = true;
                Navigator.of(dialogContext).pop();
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
    );
    return accepted;
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
          builder: (dialogContext) => AlertDialog(
            title: const Text('連線失敗'),
            content: Text(
              (reason != null && reason.isNotEmpty)
                  ? '$errorMessage\n錯誤代碼：$reason'
                  : errorMessage,
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext); // 關閉對話框
                  // ★ issue 10：安全返回主畫面，避免 pop 後無上一頁造成黑屏
                  // ★ 2026-08-23：見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
                  // ★ 2026-08-24：builder 參數改名為 dialogContext，避免遮蔽
                  //   State 自己的 context——下面改用未被遮蔽的 State context
                  //   呼叫 safeNavigateBack（對話框已用 dialogContext 關閉，
                  //   它對應的路由隨即不再是最上層，若誤用它呼叫會恆回傳
                  //   false），且改成「呼叫後才鎖旗標」：先鎖再呼叫的話，一旦
                  //   safeNavigateBack 因故拒絕導航，_navigatedAway 會被錯誤
                  //   鎖死，長輩就永久卡在這個「連線失敗」畫面出不去。
                  if (_navigatedAway) return;
                  _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
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
      // ★ 第四十二輪：好友通話以 'friend' 身分加入對方的房間，讓後端
      //   _verify_room_access 走好友關係驗證分支（一般情境不變，仍是 'elder'）。
      widget.friendCallTargetElderId != null ? 'friend' : 'elder',
      userId: resolvedUserId,
      deviceName: widget.deviceName,
      // deviceMode 不因好友通話改變邏輯：isCCTVMode 對好友通話恆為 false，
      // 故此處自然結果就是 'comm'——好友通話絕不可用 'monitor'（見
      // friendCallTargetElderId 欄位說明；'monitor' 會誤觸監控房授權與
      // 監控機額度計算）。
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
          // ★ 2026-08-23：onConnectionLost／onPeerConnectionFailed 可能幾乎同時
          //   觸發，見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
          if (_navigatedAway) return;
          _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
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
          // ★ 2026-08-23：見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
          if (_navigatedAway) return;
          _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    // ★ issue 5：通話中發生無法復原的連線中斷（已超過 signaling.dart 的 2 秒重連寬限期）
    _signaling.onConnectionLost = () {
      _callTimer?.cancel();
      if (!mounted) return;

      // ── 一般通話路徑：與第二十二輪修改前的業務邏輯（文案／狀態）完全
      //    相同，不得更動；2026-08-23 僅在離場前補上 _navigatedAway 重入
      //    防護，見該欄位宣告處的說明 ──
      if (!widget.isCCTVMode) {
        _showElderCallFailToast(kCallFailDisconnected);
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "連線中斷";
          _isInCall = false;
        });
        if (_navigatedAway) return;
        _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
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
          // ★ 2026-08-23：見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
          if (_navigatedAway) return;
          _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    // ★ 2026-08-23：本畫面過去在這裡直接掛一個 `force-logout` 原生 socket
    //   監聽（對應 dispose() 內原本的 `socket.off('force-logout',
    //   _forceLogoutHandler)` 精準解除，該段清理也已一併移除）。但
    //   `main.dart::handleForceLogout()` 透過 `Signaling.onForceLogout`
    //   回呼也在處理同一個後端事件——同一個 `force-logout` 事件因此有兩個
    //   互不知情的接收端，各自 remove prefs、各自 `pushAndRemoveUntil` 到
    //   不同畫面（這裡曾經是 `IdentificationScreen`，`main.dart` 當時是
    //   `RoleSelectionScreen`）。兩者幾乎同時觸發時，第二個會在第一個已經
    //   清空過的導航堆疊上再操作一次，正是使用者回報「長輩端在背景徹底
    //   死機（ANR）」的成因之一。
    //   修法：force-logout 只留 `main.dart::handleForceLogout()` 一個唯一
    //   擁有者——它經由全域 `navigatorKey` 執行，即使本畫面未掛載也能觸發；
    //   且逐一比對過，它清除的 prefs 鍵集合是本畫面舊版清單的超集（多清了
    //   `pendingAcceptedCall`／`pendingRingCallData`／`pendingRingCall`／
    //   `selected_elder_id`／`selected_elder_name`／`selected_elder_room_id`
    //   六個鍵，沒有任何一邊獨有而對方漏清的鍵），並已把目的地從
    //   `RoleSelectionScreen` 改成現行入口 `IdentificationScreen`。
    //   🚫 不要在這裡加回 `_signaling.socket?.on('force-logout', ...)`——
    //   這正是本次要移除的重複註冊。
    _signaling.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [ElderScreen] Incoming Offer from $callerId (Type: $callType)");
      // ★ 2026-08-25（第三十三輪）：舊註解「只要在 ElderScreen 內就代表已經
      //   進入通話準備狀態，一律接聽」不成立——長輩端可能因為上一通通話、
      //   CCTV 監控或任何原因已經停留在本畫面，此時收到一般通話的 offer，
      //   使用者從未被問過是否接聽（尤其螢幕關閉時更不會發現）。
      //   `callType` 不是新旗標，是 `signaling.dart`（收到 offer 時依這通電話
      //   登記的 isEmergency 換算）既有就會傳進來的既有參數，只是原本被忽略。
      //
      //   緊急通話：維持 G81「長輩端永遠不得出現接聽／拒絕 UI」，行為與改動前
      //   完全相同——無條件接聽。
      if (callType == 'emergency') {
        if (mounted) setState(() => _isInCall = true);
        return true;
      }

      // 一般通話：`_isInCall` 為 true 代表這通電話已經在別處被使用者同意過
      //   （`ElderHomeScreen` 來電對話框／`main.dart` 全域來電對話框／CallKit
      //   接聽，見 `_handleAcceptedCallFromBackground`／`_checkPendingAcceptedCall`
      //   都會先設定 `_isInCall = true` 才送 `sendCallAccept`）——這裡只是同一
      //   通電話後續送達的 WebRTC offer，照常接聽，行為與改動前完全相同。
      if (_isInCall) {
        return true;
      }

      // 走到這裡代表畫面上沒有任何「已同意」的通話紀錄卻收到一般通話的
      // offer，不可再直接接聽。監控機模式旁邊沒有人可以操作，彈對話框只會
      // 永久卡住畫面（比照 `_handleCallTimeout` 對 CCTV 模式的既有處理），
      // 直接回忙線即可，不彈 UI。
      if (widget.isCCTVMode) {
        try {
          _signaling.sendCallBusy(callerId);
        } catch (e) {
          debugPrint('⚠️ [ElderScreen] sendCallBusy (CCTV) 失敗: $e');
        }
        return false;
      }
      if (!mounted) return false;

      // 一般通訊機：讓使用者自己選——沿用 `elder_home_screen.dart` 既有來電
      // 對話框的外觀與拒接動作（sendCallBusy），見 `_showNormalIncomingCallChoice`
      // 的函式註解（無法直接呼叫那個 private 方法，故另外準備一份外觀對稱的）。
      final bool accepted = await _showNormalIncomingCallChoice();
      if (accepted) {
        if (mounted) setState(() => _isInCall = true);
      } else {
        try {
          _signaling.sendCallBusy(callerId);
        } catch (e) {
          debugPrint('⚠️ [ElderScreen] sendCallBusy 失敗: $e');
        }
      }
      return accepted;
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
        if (_isExiting) return;
        final String eventElderId = (data['elderId'] ?? '').toString();
        final String deviceName = (data['deviceName'] ?? '').toString();
        // 同一長輩底下可能有多台監控設備，必須確認被刪的就是自己。
        if (eventElderId.isNotEmpty && eventElderId != _rawElderId) return;
        if (deviceName.isNotEmpty && deviceName != _currentDeviceName) return;
        _isExiting = true;
        debugPrint('🗑️ [ElderScreen] 本監視器已被家屬端刪除，釋放 session 並退回身分選擇頁');
        // ★ 2026-08-11 第二十二輪（需求 6）：**先立旗標、再做任何 await**。
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
      // ★ 第四十二輪：好友通話必須送 'friend'，不可沿用 'elder'。後端路由公式
      //   是 `target_role = 'elder' if sender_role in ('family','friend') else
      //   'family'`——送 'elder' 會讓 target_role 變成 'family'，call-request
      //   被誤送去對方的家屬而不是對方本人（對方完全收不到來電，無任何錯誤）。
      role: widget.friendCallTargetElderId != null ? 'friend' : 'elder',
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
  ///
  /// ★ 2026-08-24 稽核記錄：家屬端 `video_call_screen.dart` 曾有「對方已接聽，
  /// 但 WebRTC 協商還沒談完時逾時窗仍把電話當『沒人接』」的臭蟲（誤送多餘的
  /// `sendCancelCall`，見該檔 `_remoteAccepted` 欄位的完整說明）。本檔逐行核對
  /// 後**沒有**同一種毛病，不需要移植同一套修法——下面 `Future.delayed` 裡的
  /// guard 用的是 `_status != "正在呼叫家人..."`，而 [onCallAcceptedByRemote]
  /// （:755-759）一收到接聽就同步把 `_status` 改成「連線建立中...」，全檔找過
  /// 一輪沒有任何其他賦值會把 `_status` 改回「正在呼叫家人...」，所以這顆逾時
  /// 一旦跨過接聽時刻就會在下面的 guard 自動變成 no-op，`_handleCallTimeout`
  /// 根本不會被叫到，`sendCancelCall` 自然也不會誤送。
  ///
  /// ⚠️ 但這只是「字串比對恰好順帶擋掉了」，不是刻意設計的等價機制，代價是
  /// 接聽之後若協商真的卡死，**沒有任何逾時會再次介入**——只能等
  /// `onPeerConnectionFailed`（:935，只有 `onConnectionState==Failed` 才會觸發，
  /// 見 G37）或使用者自己手動掛斷。這是與家屬端不同、目前刻意不修的殘留缺口：
  /// 本輪任務只要求「有相同毛病才修」，這裡沒有相同毛病；若日後要補「已接聽
  /// 但協商卡死」的專屬逾時，可比照家屬端 `_remoteAccepted` +
  /// `_negotiationTimeoutSeconds` 的模式另外設計，不要直接沿用 `_status`
  /// 字串比對這條路——那是巧合生效，不是為這個用途設計的。
  void _armCallTimeout() {
    final int attempt = ++_callAttempt;
    // ★ 2026-07-18：長輩端主動撥打新增 30 秒逾時。原本完全沒有逾時，
    //   家屬未接時只能靠手動掛斷，被叫方 CallKit 也會一直響。逾時自動取消。
    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (attempt != _callAttempt) return; // 已重新撥打，這一輪作廢
      // ★ 2026-08-24 稽核：這一行恰好也是「已接聽」的隱性守門——見上方
      //   本方法的稽核記錄，_status 一旦被 onCallAcceptedByRemote 改掉就不會
      //   再等於這個字串，本逾時就此失效，不會誤送 cancel-call。
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
    // ★ 第四十二輪：同 _makeCall 的 sendCallRequest，role 必須跟著撥打時一致，
    //   否則後端算出的 target_role 會反過來查錯房間成員（見該處註解）。
    _signaling.sendCancelCall(
      _formattedRoomId,
      role: widget.friendCallTargetElderId != null ? 'friend' : 'elder',
    );
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
      // ★ 2026-08-23：見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
      if (_navigatedAway) return;
      _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
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
      // ★ 2026-08-23：見 _navigatedAway 欄位宣告處的說明——本畫面只離開一次。
      if (_navigatedAway) return;
      _navigatedAway = safeNavigateBack(context, _buildFallbackHome());
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
      if (_isExiting) return;
      _isExiting = true;
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

      // ★ 2026-08-18 房間洩漏修復：過去這裡完全沒有主動離開房間，是靠
      //   releaseSession() 內的 forceDisconnect() 斷線後，後端 on_disconnect
      //   才把 socket 順帶清出房間——這個依賴關係是隱性的，一旦未來有人
      //   改動斷線流程使其不再真的斷線，這裡就會悄悄開始累積房間成員而
      //   不會有任何錯誤訊息。改成顯式呼叫 leaveRoom，離開意圖不再依賴
      //   斷線的副作用。`_formattedRoomId` 已含正確的
      //   monitor_elder_/comm_elder_ 前綴（見 initState 賦值處），故沿用
      //   既有欄位、不重新計算。
      _signaling.leaveRoom(_formattedRoomId);

      // SessionManager 內部已包含 clearSession() + forceDisconnect()，
      // 不需要（也不可以）在這裡再呼叫一次 disconnect()。
      // ★ 2026-08-26：這是使用者在本裝置上主動按「退出並重置」，語意等同
      //   長輩自己登出（見 CLAUDE_call-monitor.md §7 G24／G125），保留快速
      //   登入記憶鍵，讓由長輩通訊帳號登出轉監控設備、再轉回長輩通訊帳號時
      //   仍能一鍵登回同一長輩。與上面的 onMonitorRemoved（家屬端強制刪除本
      //   監控機、授權已被收回）不同——那裡維持預設全清，不可套用同樣邏輯。
      await SessionManager.releaseSession(preserveQuickLogin: true);

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
    // ★ 2026-08-05 第十八輪（需求 4）：通話畫面離開 → 還原鎖屏行為，讓裝置回到原本的螢幕鎖。
    //   `showOverLockScreen()` 會設 setShowWhenLocked(true) + FLAG_KEEP_SCREEN_ON，
    //   不還原的話 APP 會永久蓋在鎖定畫面之上、螢幕也永不休眠。
    //   監控機（CCTV）刻意排除——它本來就必須維持恆亮才能持續推幀。
    //   這裡涵蓋所有離開路徑（掛斷／對方掛斷／忙線／斷線／連線失敗／撥打逾時），
    //   它們最終都會讓本 route 被 pop 或 pushAndRemoveUntil 移除而觸發 dispose()。
    // ★ 2026-08-24：搬到 dispose() 最前面、所有既有陳述式之前（見 CLAUDE_call-monitor.md
    //   §7 G49）。原本排在 `_signaling.hangUp(...)` 之後，若前面任何一步
    //   （`_cctvFrameTimer?.cancel()`、renderer.dispose()、`_signaling.hangUp(...)`…）
    //   同步丟出例外，這段就會被跳過、鎖屏還原不會執行，App 永久蓋在鎖定畫面之上——
    //   放最前面才不會被後面任何一步擋住。
    if (!widget.isCCTVMode) {
      const MethodChannel('com.example.app/bring_to_front')
          .invokeMethod('restoreLockScreen')
          .catchError((e) {
        debugPrint('⚠️ [ElderScreen] restoreLockScreen 失敗: $e');
        return null;
      });
    }

    // ★ 2026-08-25（需求 3）：這通電話是從鎖屏／背景喚醒才進來的
    //   （_enteredWhileLocked，見欄位宣告處說明）→ 通話結束時不留在 App
    //   任何畫面，直接關閉整個 App 與背景 Task，回到裝置鎖定畫面。
    //   🚫 必須排在上面的 restoreLockScreen 之後——先把「蓋過鎖定畫面」的
    //   視窗旗標清乾淨，App 的最後一幀才不會殘留蓋在鎖定畫面之上。
    //   `!widget.isCCTVMode` 是防禦性重複守衛：_enteredWhileLocked 依建構
    //   只會在非 CCTV 模式被設成 true，這裡再檢查一次，監控模式下即使欄位
    //   萬一被誤設也不會把監視機整個關掉。長輩自己主動撥出／在 App 內接聽
    //   的一般情境 _enteredWhileLocked 為 false，這裡不會呼叫，結束通話後
    //   照舊回到 ElderHomeScreen（行為不變）。
    if (!widget.isCCTVMode && _enteredWhileLocked) {
      const MethodChannel('com.example.app/bring_to_front')
          .invokeMethod('finishAndRemoveTask')
          .catchError((e) {
        debugPrint('⚠️ [ElderScreen] finishAndRemoveTask 失敗: $e');
        return null;
      });
    }

    _callTimer?.cancel();
    _cctvFrameTimer?.cancel();  // ★ 第 7 項：離開監視機畫面必須停止推幀，否則相機釋放後會持續拋例外
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // ★ 2026-08-23：本畫面已不再自行註冊 `force-logout` 監聽，原本掛在這裡的
    //   `socket.off('force-logout', _forceLogoutHandler)` 精準解除也隨之移除。
    //   見 initState 對應位置的說明——唯一擁有者現在是
    //   `main.dart::handleForceLogout()`。

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

    // ★ 第四十二輪：好友通話結束時，必須離開對方的房間並重新以 'elder' 身分
    //   加入「自己」的房間。`Signaling` 是單例，`_currentRoomId`/`_role` 此刻
    //   仍停在對方的房間／'friend'（見 connect() 的實作，`_asyncJoin`/`onConnect`
    //   重連都是讀這兩個 instance 欄位，見 CLAUDE_call-monitor-guardrails.md
    //   G47/G101/G103）。不做這一步，這位長輩之後就再也收不到「自己」家人打來
    //   的電話——沒有任何錯誤訊息，純粹靜默失效。
    //   leaveRoom 在前、connect 在後：同一條 socket 連線上先送出的事件必定先
    //   送達伺服器，不會有『先加入新房間才離開舊房間』的競態。
    //   一般情境（friendCallTargetElderId 為 null）完全不進入這個分支，行為不變。
    if (widget.friendCallTargetElderId != null) {
      _signaling.leaveRoom(_formattedRoomId);
      final String ownRoomId = _getFormattedRoomId(widget.roomId);
      debugPrint(
          '👋 [ElderScreen] 好友通話結束，離開 $_formattedRoomId，重新加入自己的房間 $ownRoomId');
      _signaling.connect(
        ownRoomId,
        'elder',
        userId: _userId ?? widget.roomId,
        deviceName: widget.deviceName,
        deviceMode: 'comm',
      );
    }

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
                      // ★ 2026-08-25：新增的推送狀態文字是執行期資料（後端 reason
                      //   字串長度不定），限制最大寬度＋下面 Text 的
                      //   maxLines/overflow 雙重保險，避免撐爆版面或造成
                      //   RenderFlex overflow。
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CCTV 監視中…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1.0,
                            ),
                          ),
                          // ★ 2026-08-25：把每 2 秒一輪 pushCctvFrame 的最新結果翻成
                          //   中文顯示在這裡（見 _recordCctvPushResult／
                          //   _describeCctvPushResult）。這是使用者唯一拿得到的
                          //   推幀診斷資訊來源——他們不是伺服器管理員，查不了
                          //   /cctv/yolo_status 之類的診斷端點，只能站在監視機
                          //   前面看畫面。純顯示，不影響 G75 的三層自癒推幀迴圈。
                          const SizedBox(height: 2),
                          Text(
                            _cctvPushStatusText,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // 原始 reason 字串（小字），方便使用者原樣回報給我們核對。
                          if (_cctvPushRawReason != null)
                            Text(
                              _cctvPushRawReason!,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 9,
                              ),
                            ),
                          // ★ 2026-08-26：偵測器載入失敗的原因（後端
                          //   `routers/alert.py` 在 reason == 'yolo_unavailable'
                          //   時才附上，已由後端 _sanitize_load_error() 折單行、
                          //   裁切至 200 字並遮蔽 URL 內嵌憑證樣式）。使用者不是
                          //   伺服器管理員，查不了 /cctv/yolo_status 之類的診斷
                          //   端點，這行字是他們唯一拿得到、可以原樣回報給我們
                          //   核對的線索——因此刻意**不**用 maxLines: 1 +
                          //   ellipsis 單行截斷（那樣會把最關鍵的內容切掉，等於
                          //   白顯示）。改用較高的 maxLines 讓它自然換行；外層
                          //   Container 已有 maxWidth: 300 限制寬度，這裡的
                          //   maxLines: 5 在該寬度、此字級下足以完整顯示後端
                          //   裁切後的 200 字上限，overflow: ellipsis 只是防禦
                          //   性上限（正常情況不會觸發），不是主要截斷手段。
                          //   純顯示、不影響 G75 的三層自癒推幀迴圈。
                          if (_cctvPushLoadError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _cctvPushLoadError!,
                                textAlign: TextAlign.center,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 9,
                                ),
                              ),
                            ),
                        ],
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
