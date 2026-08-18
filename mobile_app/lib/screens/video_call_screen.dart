// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/signaling.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../screens/family_main_screen.dart';
import '../screens/elder_home_screen.dart';
import '../globals.dart' as globals;
import '../widgets/call_retry_dialog.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String? targetSocketId;
  final bool isIncomingCall;
  final bool autoStart;
  final bool isEmergency;
  final String? callId;
  final bool sendAcceptOnOpen;
  final bool isVideoCall; // ★ Fix E：是否為視訊通話（false = 純語音/電話）
  // ★ 2026-08-05 第十七輪：是否以 pop() 返回上一頁（而非 pushAndRemoveUntil 重建主畫面）。
  //   預設 false，維持所有現有建構點的行為完全不變；只有監控檢視入口會傳 true。
  final bool returnByPop;

  /// ★ 2026-08-10 第十九輪（需求 2）：單向監控檢視模式。
  ///
  /// `true` 時本畫面只「看」對方、不送出自己的影像：不取視訊軌、不顯示本地
  /// 預覽 PiP、隱藏鏡頭開關與前後鏡頭切換，只保留麥克風 / 擴音 / 掛斷 / 返回。
  ///
  /// ⚠️ **這是護欄 G8「`_isCameraOff` 宣告式初值必須為 false」的唯一明文例外**
  /// （見 `CLAUDE_call-monitor.md` §7 G55）。預設 `false`，全專案**只有**家屬端
  /// 「觀看 CCTV」那一個建構點可以傳 `true`；一般通話（含緊急通話）的鏡頭
  /// 仍必須預設開啟。看到這個欄位不要以為它違反 G8 而刪掉。
  final bool monitorViewOnly;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    this.targetSocketId,
    this.isIncomingCall = false,
    this.autoStart = false,
    this.isEmergency = false,
    this.callId,
    this.sendAcceptOnOpen = true,
    this.isVideoCall = true, // 預設視訊通話
    this.returnByPop = false,
    this.monitorViewOnly = false,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCall = false;

  // ★ 通話控制狀態
  bool _isMicMuted = false;
  bool _isCameraOff = false;  // 視訊房間預設開啟鏡頭
  /// ★ 2026-08-10 第二十輪（需求 9）：音量來源（聽筒／擴音）。
  ///   規則：一般語音通話預設**聽筒**、視訊通話預設**擴音**；
  ///   語音通話中途開啟鏡頭時自動切成擴音（見 [_toggleCamera]）。
  ///   原本無條件 `= true` 又在 `_initCall` 裡寫死 `enableSpeakerphone(true)`，
  ///   語音通話貼著耳朵講也是外放，長輩端很容易造成回授嘯叫。
  late bool _isSpeakerOn;

  /// 是否已因「語音通話中開啟鏡頭」自動切過一次擴音。
  /// 只自動切一次，之後尊重使用者手動的選擇，不再覆蓋。
  bool _speakerAutoSwitched = false;
  bool _isFrontCamera = true;
  bool _mediaInitialized = false;  // ★ 追蹤媒體是否已初始化
  bool _callConnecting = true;   // ★ 追蹤通話是否正在連線中
  bool _callConnected = false;   // ★ 追蹤通話是否已成功連線
  bool _callFailed = false;      // ★ 追蹤通話是否連線失敗
  // ★ 2026-08-12 第二十三輪（需求 3）：移除 `_callErrorMessage`。
  //   它唯一的讀取點是被本輪刪掉的失敗畫面（紅色 wifi_off ＋「重試連線」）；
  //   失敗原因現在由 `showCallRetryDialog` / `_showCallProblemThenGoHome` 的
  //   文案直接呈現，原始例外訊息仍保留在 debugPrint。
  //   `_callFailed` 則**必須留著**——`initState` 的 5 秒 periodic 守衛在讀它。

  // ★ 通話計時器
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  // ★ 通話逾時計時器
  Timer? _callTimeoutTimer;

  /// ★ 2026-08-12 第二十三輪（需求 3）：撥打「世代編號」。
  ///
  /// 每呼叫一次 [_armConnectTimeout] 就 +1，逾時回呼裡先比對自己是不是最新世代，
  /// 不是就直接作廢。沒有這個守衛的話，使用者選「重新撥打」之後會同時存在
  /// 兩個 `Future.delayed`，第一輪的那個仍會在原定時間彈出第二個逾時對話框
  /// （`Future.delayed` 無法取消，只能靠世代比對讓它變成 no-op）。
  int _connectAttempt = 0;

  // ★ 情境 3 修復：暫存返回主畫面所需的真實使用者資料（於 _initCall 從 prefs 讀取）
  int _resolvedUserId = 0;
  String _resolvedUserName = '家屬端';
  String _resolvedUserRole = 'family';

  @override
  void initState() {
    super.initState();
    // ★ 2026-08-10 第二十輪（需求 9）：決定音量來源預設值。
    //   視訊通話／緊急通話／監控檢視都是「放在面前看」的情境 → 擴音；
    //   一般語音通話是「貼著耳朵講」 → 聽筒。
    _isSpeakerOn =
        widget.isVideoCall || widget.isEmergency || widget.monitorViewOnly;
    if (!kIsWeb && Platform.isAndroid) {
      Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication);
    }
    _initCall();
    // 設定通話逾時（30秒）
    _callTimeoutTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_callConnecting && !_callConnected && !_callFailed) {
        // 如果已經連線中超過30秒且仍未連線，則視為失敗
        // 這裡其實是每5秒檢查一次，但實際逾時時間在 _initCall 中控制
      }
    });
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onAddRemoteStream = ((stream) {
      debugPrint("📺 [VideoCallScreen] Remote stream added! Tracks: ${stream.getTracks().length}");
      // ★ 2026-08-05 第十七輪：onAddRemoteStream 只代表 SDP 談成（setRemoteDescription
      //   當下就會觸發），不代表 ICE 已連通、有任何媒體在流動，因此 _startCallTimer()
      //   與 _callConnected 改移到真正連上時才觸發的 onPeerConnected（見下方）。
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _inCall = true;
          _callConnecting = false;
          _callFailed = false;
        });
      }
    });

    // ★ 2026-08-05 第十七輪：ICE 真正連通（RTCPeerConnectionStateConnected）時才開始計時，
    //   避免「有通話計時卻雙方都看不到聽不到」的假象。
    _signaling.onPeerConnected = () {
      if (mounted) {
        setState(() => _callConnected = true);
        _startCallTimer();
      }
    };

    // ★ 2026-08-05 第十七輪：ICE 連線失敗時據實回報並安全返回主畫面，而不是讓通話停在
    //   「已連線」但零影音的假狀態。
    _signaling.onPeerConnectionFailed = (msg) {
      debugPrint('⚠️ [VideoCall] PeerConnection 失敗: $msg');
      if (mounted) {
        _stopCallTimer();
        _showCallProblemThenGoHome(kCallFailUnreachable);
      }
    };

    _signaling.onLocalStream = ((stream) {
      debugPrint("🤳 [VideoCallScreen] Local stream set! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [VideoCallScreen] Incoming Call/Offer detected while in UI!");
      return true;
    };

    _signaling.onCallEnded = () {
      if (mounted) {
        _stopCallTimer();
        // ★ 2026-08-05 第十八輪（需求 3）：正常掛斷改為靜默直接返回主介面。
        //   （第十三輪為了讓提示不被 pushAndRemoveUntil 吞掉而改用 dialog，
        //    現在依使用者要求連提示本身一併移除，dialog 的必要性隨之消失。）
        _endCallAndGoHome('對方已掛斷通話');
      }
    };

    _signaling.onCallBusy = (targetId, callId) {
      if (mounted) {
        _stopCallTimer();
        _showCallProblemThenGoHome(callBusyMessageFor(_signaling.lastCallBusyReason));
      }
    };

    // ★ issue 5：通話中發生無法復原的連線中斷（已超過 signaling.dart 的 2 秒重連寬限期）
    _signaling.onConnectionLost = () {
      if (mounted) {
        _stopCallTimer();
        // ★ 2026-07-27 第十三輪：SnackBar 會被 pushAndRemoveUntil 吞掉，必須用 dialog。
        _showCallProblemThenGoHome(kCallFailDisconnected);
      }
    };

    // ★ 接聽回達後由家屬端觸發 createOffer（唯一入口，防止重複 Offer）
    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      debugPrint("✅ [VideoCallScreen] Target Accepted ($accepterId), sending Offer...");
      _signaling.createOffer(targetId: accepterId, isEmergency: widget.isEmergency);
    };

    // ★ 2026-08-17 第二十五輪（需求 6）：使用者角色／ID／名稱解析必須排在媒體初始化
    //   之前。原本這段（讀 SharedPreferences 判斷 role、算出 _resolvedUserRole／
    //   _resolvedUserId／_resolvedUserName）排在媒體初始化 try/catch **之後**，但媒體
    //   初始化失敗時 catch 區塊會呼叫 _showCallProblemThenGoHome() 並 return——這條
    //   提早 return 的路徑永遠不會執行到角色解析，於是 _resolvedUserRole 停在宣告式
    //   初值 'family'（:107）。_buildFallbackHome()（:567）依 _resolvedUserRole 決定要不
    //   要導去 ElderHomeScreen，長輩因此被誤導向 FamilyMainScreen（一個沒有任何綁定
    //   長輩的家屬端主畫面）。角色必須在任何可能提早 return 的路徑之前解析完成，
    //   否則 _buildFallbackHome() 會把長輩導到家屬端主畫面。以下邏輯與搬移前逐位元組
    //   相同，只是提前執行；role/userId/userName 仍在函式本體作用域內，後面
    //   _signaling.connect(...) 等處照樣讀得到。
    final prefs = await SharedPreferences.getInstance();
    final String role = prefs.getString('user_role') ?? prefs.getString('saved_role') ?? globals.appRole ?? 'family';
    _resolvedUserRole = role;
    final int? userId = (role == 'elder')
        ? prefs.getInt('caregiver_id')
        : (prefs.getInt('user_id') ?? prefs.getInt('caregiver_id'));
    final String userName = (role == 'elder')
        ? (prefs.getString('caregiver_name') ?? '長輩')
        : (prefs.getString('user_name') ?? prefs.getString('caregiver_name') ?? '家屬端');

    // ★ 情境 3 修復：暫存真實使用者資料，供通話結束後重建主畫面使用（避免 userId:0 導致主畫面失效）
    _resolvedUserId = userId ?? 0;
    _resolvedUserName = userName;

    // ★ 初始化媒體：通話必須有音軌才能建立 WebRTC 連線
    // 我們先開啟媒體，但預設將鏡頭的軌道設為停用 (黑屏)，保護隱私
    try {
      // ★ 2026-08-10 第十九輪（需求 2）：單向監控檢視只取音訊軌。
      //   刻意沿用既有的 openUserMedia 呼叫「位置」與時序（仍在 createOffer 之前
      //   取得 localStream），只改 constraint——不可改成「不呼叫 openUserMedia」，
      //   那會讓 localStream 為 null 而違反護欄「localStream 必須先於 createOffer 存在」，
      //   且監控需要雙向語音，音訊軌一定要有。
      await _signaling.openUserMedia(
        _localRenderer,
        videoEnabled: !widget.monitorViewOnly,
      );
      _mediaInitialized = true;
      // ★ Fix E：語音通話（isVideoCall=false）預設關閉鏡頭，與發起端對稱；
      //   鏡頭按鈕仍可手動開啟（見 _toggleCamera），此處僅決定進房初始狀態。
      //   monitorViewOnly 時根本沒有視訊軌，同樣視為鏡頭關閉。
      if ((!widget.isVideoCall || widget.monitorViewOnly) && mounted) {
        setState(() => _isCameraOff = true);
      }
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        for (var track in videoTracks) {
          track.enabled = widget.isVideoCall && !widget.monitorViewOnly;
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to initialize media: $e");
      if (mounted) {
        setState(() {
          _callConnecting = false;
          _callFailed = true;
        });
        // ★ 2026-08-12 第二十三輪（需求 3）：原本這裡只設旗標，靠畫面上那個
        //   紅色 `wifi_off` 失敗區塊呈現。該區塊已依需求移除，若不補提示，
        //   鏡頭權限被拒的使用者只會看到永遠轉不停的「正在連線中...」。
        //   媒體開不起來**不適用**「重新撥打」（重撥一百次也還是沒有鏡頭），
        //   所以走既有的 `_showCallProblemThenGoHome`（提示 2 秒後回主畫面），
        //   不彈重撥對話框。
        _showCallProblemThenGoHome('無法開啟攝像頭或麥克風，請檢查權限設定');
        return;
      }
    }

    // ★ 修復：若 Socket 已經連線（從 FamilyMainScreen 傳承下來），則不要重新連線，
    //   否則會導致原本的 callbacks 被覆寫且 SocketId 改變。
    if (_signaling.socket?.connected != true) {
      debugPrint("🔌 [VideoCallScreen] Socket 未連線，開始連線...");
      final String? fcmToken = await FirebaseMessaging.instance.getToken();
      _signaling.connect(
        widget.roomId,
        'family',
        userId: userId,
        deviceName: userName,
        fcmToken: fcmToken,
      );
    } else {
      debugPrint("🔌 [VideoCallScreen] Socket 已連線，重用現有連線 (room: ${widget.roomId})");
    }

    // ★ 2026-08-10 第二十輪（需求 9）：套用 initState 決定的音量來源，
    //   不再無條件開擴音（語音通話預設走聽筒）。
    _signaling.enableSpeakerphone(_isSpeakerOn);

    _sendCallInvite();
    _armConnectTimeout();
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：送出（或**重**送）一次通話封包。
  ///
  /// 從 `_initCall` 抽出來，讓「重新撥打」可以只重跑這一段。
  /// **不可以**把 `_initCall()` 整個重跑當成重撥——那會再次
  /// `openUserMedia`，真機上常因鏡頭仍被前一次佔用而拿不到視訊軌變黑畫面
  /// （原本那顆「重試連線」按鈕就是這樣做的，見 [showCallRetryDialog] 的註解）。
  void _sendCallInvite() {
    if (widget.isIncomingCall) {
      // 接聽方：這裡的「重送封包」是再送一次 call-accept 給發起方。
      if (widget.sendAcceptOnOpen && widget.targetSocketId != null) {
        _signaling.sendCallAccept(widget.targetSocketId!, callId: widget.callId);
      }
      return;
    }
    if (!widget.autoStart) return;

    Future.microtask(() async {
      int retries = 50; // 最多等待 5 秒
      while (_signaling.socket?.connected != true && retries > 0) {
        await Future.delayed(const Duration(milliseconds: 100));
        retries--;
      }
      if (!mounted) return;

      if (widget.isEmergency) {
        _signaling.sendEmergencyCall(widget.roomId, targetId: widget.targetSocketId);
      } else {
        // 如果是主動呼叫，先發送 Request 給對方點擊接聽 (確保觸發 FCM 與資料庫記錄)
        _signaling.sendCallRequest(widget.roomId, role: 'family', targetId: widget.targetSocketId);
      }
    });
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：啟動一次連線逾時看門狗。
  ///
  /// `Future.delayed` 無法取消，所以用 [_connectAttempt] 世代編號讓過期的那一輪
  /// 自行作廢；重新撥打時只要再呼叫本方法就會讓舊的那顆失效。
  void _armConnectTimeout() {
    // 緊急通話需等待對端被喚醒與自動接聽，逾時窗拉長避免家屬端誤判自動掛斷
    final int connectTimeoutSeconds = widget.isEmergency ? 60 : 20;
    final int attempt = ++_connectAttempt;
    Future.delayed(Duration(seconds: connectTimeoutSeconds), () {
      if (!mounted) return;
      if (attempt != _connectAttempt) return; // 已重新撥打，這一輪作廢
      if (!_callConnecting || _callConnected) return;
      _handleConnectTimeout();
    });
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：無人接聽／連線逾時。
  ///
  /// 舊行為是把 `_callFailed` 設起來、讓畫面中央顯示紅色 `wifi_off` 區塊
  /// 加一顆「重試連線」按鈕（該按鈕會重跑整個 `_initCall`）。依需求改為
  /// LINE 式的對話框：離開通話房間，或重新送一次通話封包。
  ///
  /// `_callFailed` 這個欄位**刻意保留**——`initState` 的 5 秒 periodic 守衛與
  /// 媒體初始化失敗路徑都在用它，移除會讓「已經失敗過」失去判斷依據。
  Future<void> _handleConnectTimeout() async {
    // ★ 2026-07-18：逾時未接通時，主動通知對方取消／掛斷，避免被叫方 CallKit
    //   繼續響到 45 秒。僅撥打方（非來電接聽方）需要送取消。
    if (!widget.isIncomingCall) {
      try {
        _signaling.sendCancelCall(widget.roomId, role: 'family');
      } catch (e) {
        debugPrint('⚠️ [VideoCall] timeout sendCancelCall failed: $e');
      }
    }
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    if (!mounted) return;
    setState(() {
      _callConnecting = false;
      _callFailed = true;
    });

    final CallRetryChoice? choice = await showCallRetryDialog(
      context,
      title: widget.isIncomingCall ? '通話連線逾時' : '對方沒有接聽',
      message: widget.isIncomingCall
          ? '這通來電一直無法接通。要離開通話房間，還是重新嘗試連線？'
          : '對方一直沒有接聽。要離開通話房間，還是重新撥打一次？',
    );
    if (!mounted) return;

    if (choice == CallRetryChoice.retry) {
      _retryCall();
    } else {
      // 含 `null`（理論上不會發生，`barrierDismissible: false` + `PopScope`）——
      // 任何非 retry 的結果都當作離開，不要把使用者留在死掉的通話畫面上。
      _goHomeAfterCall();
    }
  }

  /// ★ 2026-08-12 第二十三輪（需求 3）：重新撥打。
  ///
  /// 只重置通話狀態 + 重送封包 + 重新武裝逾時看門狗；
  /// **不重跑** `_initCall()`（媒體與 Socket 都還在，重跑會搶鏡頭）。
  void _retryCall() {
    debugPrint('🔁 [VideoCall] 使用者選擇重新撥打（第 ${_connectAttempt + 1} 次）');
    setState(() {
      _callConnecting = true;
      _callConnected = false;
      _callFailed = false;
      _inCall = false;
    });
    _sendCallInvite();
    _armConnectTimeout();
  }

  // ★ 通話計時器
  void _startCallTimer() {
    _callTimer?.cancel();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String get _formattedDuration {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ★ 麥克風靜音切換
  void _toggleMic() {
    if (_signaling.localStream == null) return;
    final audioTracks = _signaling.localStream!.getAudioTracks();
    if (audioTracks.isEmpty) return;
    setState(() {
      _isMicMuted = !_isMicMuted;
      for (var track in audioTracks) {
        track.enabled = !_isMicMuted;
      }
    });
    debugPrint("🎤 Mic ${_isMicMuted ? 'Muted' : 'Unmuted'}");
  }

  // ★ 鏡頭開關切換 — 同時初始化媒體（如果還未初始化）
  void _toggleCamera() {
    if (!_mediaInitialized) {
      _initializeAndToggleCamera();
      return;
    }
    
    if (_signaling.localStream == null) return;
    final videoTracks = _signaling.localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    setState(() {
      _isCameraOff = !_isCameraOff;
      for (var track in videoTracks) {
        track.enabled = !_isCameraOff;
      }
    });
    debugPrint("📷 Camera ${_isCameraOff ? 'Off' : 'On'}");
    _autoSwitchToSpeakerOnCameraOn();
  }

  /// ★ 2026-08-10 第二十輪（需求 9）：一般語音通話中途開啟鏡頭 → 自動切擴音。
  ///   使用者一旦把鏡頭打開，手機就會從耳邊移開，此時仍走聽筒等於聽不到。
  ///   只自動切一次（`_speakerAutoSwitched`），之後尊重使用者手動的選擇。
  void _autoSwitchToSpeakerOnCameraOn() {
    if (widget.isVideoCall) return; // 視訊通話本來就預設擴音
    if (_isCameraOff) return;
    if (_speakerAutoSwitched) return;
    if (_isSpeakerOn) return;
    _speakerAutoSwitched = true;
    setState(() => _isSpeakerOn = true);
    _signaling.enableSpeakerphone(true);
    debugPrint('🔊 [VideoCall] 語音通話開啟鏡頭，音量來源自動切換為擴音');
  }

  // ★ 初始化媒體並打開攝像頭
  Future<void> _initializeAndToggleCamera() async {
    try {
      debugPrint("🎬 Initializing media stream...");
      await _signaling.openUserMedia(_localRenderer);
      setState(() => _mediaInitialized = true);
      
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          setState(() {
            _isCameraOff = false;  // 開啟攝像頭
            for (var track in videoTracks) {
              track.enabled = true;
            }
          });
          debugPrint("📷 Camera initialized and turned On");
          _autoSwitchToSpeakerOnCameraOn();
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to initialize media: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("無法開啟攝像頭: $e")),
        );
      }
    }
  }

  // ★ 前後鏡頭切換 — 必須先初始化媒體
  void _switchCamera() {
    if (!_mediaInitialized || _signaling.localStream == null) return;
    final videoTracks = _signaling.localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    Helper.switchCamera(videoTracks[0]);
    setState(() => _isFrontCamera = !_isFrontCamera);
    debugPrint("🔄 Camera switched to ${_isFrontCamera ? 'Front' : 'Back'}");
  }

  // ★ 揚聲器切換
  void _toggleSpeaker() {
    // 使用者手動選過之後就不再自動切換（需求 9）。
    _speakerAutoSwitched = true;
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _signaling.enableSpeakerphone(_isSpeakerOn);
    debugPrint("🔊 Speaker ${_isSpeakerOn ? 'On' : 'Off'}");
  }

  @override
  void dispose() {
    _stopCallTimer();
    _callTimeoutTimer?.cancel();
    // ★ 修復：只結束 WebRTC，不要斷開 Socket，這樣回到 FamilyMainScreen 時才能繼續接收推播
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);

    // ★ 清空 UI 相關的 callbacks，讓全域的 callbacks 重拾控制權
    _signaling.onCallAcceptedByRemote = null;
    _signaling.onAddRemoteStream = null;
    _signaling.onLocalStream = null;
    _signaling.onIncomingCall = null;
    _signaling.onCallEnded = null;
    _signaling.onCallBusy = null;
    _signaling.onJoinFailed = null;
    _signaling.onConnectionLost = null;
    _signaling.onPeerConnected = null;
    _signaling.onPeerConnectionFailed = null;

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    if (!kIsWeb && Platform.isAndroid) {
      Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration(
        manageAudioFocus: false,
        androidAudioMode: AndroidAudioMode.normal,
        androidAudioFocusMode: AndroidAudioFocusMode.gain,
        androidAudioStreamType: AndroidAudioStreamType.music,
        androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
        androidAudioAttributesContentType: AndroidAudioAttributesContentType.unknown,
      ));
      Helper.clearAndroidCommunicationDevice();
    }

    super.dispose();
  }


  // ★ issue 3 fix: 安全掛斷並導航，防止冷啟動進入時 pop 後黑屏
  void _safeHangUp() {
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    _stopCallTimer();
    if (mounted) {
      _goHomeAfterCall();
    }
  }

  // ★ issue 3 fix: 冷啟動時無上一頁，退回 FamilyMainScreen（帶入真實使用者資料）
  Widget _buildFallbackHome() {
    if (globals.appRole == 'elder' || _resolvedUserRole == 'elder') {
      // ★ 2026-08-11 第二十一輪（需求 1）：補上 roomId。
      //   原本沒有帶，長輩從這條路徑回到主畫面後，FriendsScreen 拿到的 roomId 是
      //   null，撥出時就會退回用 caregiver_id 拼房名（`comm_elder_<caregiver_id>`），
      //   後端查不到對應家屬 → 撥打完全沒反應。`widget.roomId` 就是這通通話的房名
      //   （可能已帶 `comm_elder_` 前綴），ElderScreen 的 `_getFormattedRoomId()`
      //   有冪等保護，重複前綴不會發生。
      return ElderHomeScreen(
        userId: _resolvedUserId,
        userName: _resolvedUserName,
        roomId: widget.roomId,
      );
    }
    return FamilyMainScreen(
      userId: _resolvedUserId,
      userName: _resolvedUserName,
    );
  }

  // ★ 情境 3 修復：通話結束/拒接/斷線後，一律用 pushAndRemoveUntil 導向「重建的」主畫面。
  //   家屬端在 APP 外接聽時，VideoCallScreen 會被疊在 SplashScreen 之上；若用 pop()
  //   會回到已完成任務的 SplashScreen 造成黑屏。改用 pushAndRemoveUntil 可確定性返回
  //   主畫面、清空堆疊，杜絕任何黑屏。
  // ★ 2026-08-05 第十七輪：監控檢視是由家屬端主畫面 Navigator.push 疊上來的，
  //   pop 回去可保留互動分頁與既有 signaling 狀態。上述「一律 pushAndRemoveUntil」的護欄
  //   針對的是冷啟動時疊在 SplashScreen 上的來電路徑——那條路徑 widget.returnByPop 為 false，
  //   行為完全不變；這裡另外再檢查一次 canPop，pop 不了就退回原本的重建主畫面。
  void _goHomeAfterCall() {
    if (!mounted) return;
    // ★ 2026-08-05 第十八輪（需求 4）：通話結束 → 還原鎖屏行為，
    //   否則 setShowWhenLocked(true) 會讓 APP 一直蓋在鎖定畫面之上。
    //   `invokeMethod` 是非同步的，PlatformException 會以 Future 錯誤丟出，
    //   同步 try/catch 接不到，必須用 catchError。
    const MethodChannel('com.example.app/bring_to_front')
        .invokeMethod('restoreLockScreen')
        .catchError((e) {
      debugPrint('⚠️ [VideoCall] restoreLockScreen 失敗: $e');
      return null;
    });
    if (widget.returnByPop && Navigator.of(context).canPop()) {
      // ★ 2026-08-18 房間洩漏修復：CCTV 監控檢視離開時，過去只有 pop() 返回，
      //   從未告知後端「已離開監控房」，socket 會一直留在 `monitor_elder_<id>`
      //   房間裡直到整條連線斷線為止；反覆開關監控畫面會不斷疊加房間成員。
      //   這裡刻意加上 `monitor_elder_` 前綴判斷才呼叫 leaveRoom——`returnByPop`
      //   是通用旗標，若日後被通話路徑重用，貿然無條件 leaveRoom 會誤離開
      //   正在進行中的通話房，此處只精準處理監控檢視這一種情境。
      if (widget.roomId.startsWith('monitor_elder_')) {
        _signaling.leaveRoom(widget.roomId);
      }
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildFallbackHome()),
      (route) => false,
    );
  }

  /// ★ 2026-08-05 第十八輪（需求 3）：依使用者要求移除「通話已結束」對話框。
  /// **正常結束**的通話（雙方任一端掛斷）不再顯示任何視窗，直接返回主介面。
  ///
  /// ⚠️ 只有這條路徑是靜默的。拒接／忙線／斷線／連線失敗仍必須回饋，
  /// 走 [_showCallProblemThenGoHome] —— 家屬撥出後若毫無提示就跳回主畫面，
  /// 會分不清是被拒接還是自己誤觸（第八輪拒接回饋、第十七輪媒體看門狗都依賴它）。
  void _endCallAndGoHome(String reason) {
    if (!mounted) return;
    debugPrint('📴 [VideoCall] 通話結束（$reason），直接返回主畫面');
    _goHomeAfterCall();
  }

  /// ★ 2026-08-05 第十八輪（需求 3）：**異常**結束時的提示。
  /// 文案由呼叫端指定（見 `signaling.dart` 的 `kCallFail*` 常數），刻意不再叫「通話已結束」——那個視窗依需求 3 已移除；
  /// 這裡保留的是「為什麼沒接通」的診斷資訊。
  ///
  /// 護欄 G23 仍然適用：**不可改用 `SnackBar`**——緊接的 `_goHomeAfterCall()`
  /// 是 `pushAndRemoveUntil((route) => false)`，會當場移除本 route
  /// 讓 SnackBar 一起消失，變成「瞬間跳回主畫面、毫無提示」。
  void _showCallProblemThenGoHome(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _goHomeAfterCall();
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 遠端影像 (全螢幕沉浸式)
          Positioned.fill(
            child: _inCall
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1A1A1A), Colors.black],
                      ),
                    ),
                    // ★ 2026-08-12 第二十三輪（需求 3）：移除原本的失敗畫面
                    //   （紅色 `Icons.wifi_off` ＋「連線逾時，請檢查網路連接或稍後再試」
                    //   ＋藍色「重試連線」按鈕）。無人接聽／連線逾時改由
                    //   `showCallRetryDialog` 的「離開通話／重新撥打」對話框處理，
                    //   雙端一致（長輩端在 `elder_screen.dart::_makeCall` 走同一個對話框）。
                    //   這裡只剩單純的「正在連線中...」，失敗狀態不再有自己的版面。
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white70),
                          const SizedBox(height: 24),
                          Text(
                            "正在連線中...",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 18,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // 2. 頂部資訊欄
          // ★ 2026-08-11 第二十二輪（需求 4）：CCTV 監控檢視（monitorViewOnly）不顯示
          //   這一整條資訊欄——裡面的「緊急通話」字樣與紅點通話計時器都是**通話**語意。
          //   監控是單向看畫面、不是在通話，顯示「緊急通話 + 計時」只會讓家屬誤以為
          //   正在跟長輩通話（甚至誤以為長輩端也在響）。
          //   ⚠️ 這是**純顯示**的移除：`_inCall` / `_formattedDuration` / `_callTimer`
          //   的既有邏輯完全不動（掛斷、逾時、通話紀錄都還依賴它們）。
          if (!widget.monitorViewOnly)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 通話類型標示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isEmergency
                            ? Icons.warning
                            : (widget.isVideoCall ? Icons.shield : Icons.call),
                        color: widget.isEmergency
                            ? Colors.orangeAccent
                            : (widget.isVideoCall ? Colors.greenAccent : Colors.lightBlueAccent),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        // ★ Fix E：非緊急且非視訊時顯示「語音通話」，其餘沿用原邏輯。
                        widget.isEmergency
                            ? "緊急通話"
                            : (widget.isVideoCall ? "視訊通話" : "語音通話"),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // ★ 通話計時器
                if (_inCall)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          _formattedDuration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ★ 2026-08-05 第十七輪：CCTV 監控檢視的返回鍵。僅 widget.returnByPop == true
          //   （目前只有 family_interaction_tab.dart 的「觀看 CCTV」入口會傳入）才顯示，
          //   樣式比照 elder_screen.dart 的「退出監視機」按鈕；水平位置沿用規格的 left: 16，
          //   但垂直位置從 padding.top + 10 下移到 + 56，避免與上方「2. 頂部資訊欄」的
          //   通話類型膠囊（同樣 top: padding.top + 10、left: 20）互相重疊。
          //   onTap 沿用 _safeHangUp（既有掛斷 → 導航流程），不自行寫 pop。
          if (widget.returnByPop)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              child: GestureDetector(
                onTap: _safeHangUp,
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
                      Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '返回',
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

          // 3. 本地預覽 (PIP) — 鏡頭關閉時顯示圖標
          // ★ 2026-08-10 第十九輪（需求 2）：單向監控檢視完全不顯示自己的畫面，
          //   連「鏡頭已關閉」的佔位框都不要——家屬只是在看監視器，不是在通話。
          if (!widget.monitorViewOnly)
          Positioned(
            right: 20,
            bottom: 220,  // ★ 從 140 改為 220，避免與按鈕重疊
            width: 110,
            height: 160,
            child: GestureDetector(
              onTap: (_mediaInitialized && !_isCameraOff) ? _switchCamera : null,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: _isCameraOff ? Colors.white12 : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _isCameraOff
                      ? Container(
                          color: const Color(0xFF2A2A2A),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.videocam_off,
                                color: Colors.white38,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '鏡頭已關閉',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RTCVideoView(
                          _localRenderer,
                          mirror: _isFrontCamera,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                ),
              ),
            ),
          ),

          // ★ 鏡頭切換提示 (PIP 右下角小圖標)
          // ★ 2026-08-10 第十九輪（需求 2）：監控檢視沒有 PiP，提示自然也不該出現。
          if (!widget.monitorViewOnly && _mediaInitialized && !_isCameraOff)
            Positioned(
              right: 24,
              bottom: 224,  // ★ 與 PIP 位置同步（220 + 4）
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cameraswitch, color: Colors.white70, size: 16),
              ),
            ),

          // 4. 底部控制列 (Glassmorphism)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 音量來源（擴音／聽筒）
                      // ★ 2026-08-10 第二十輪（需求 9）：原本用 volume_up/volume_off，
                      //   語意是「有聲／靜音」，使用者會誤以為按了會靜音。
                      //   改為 volume_up（擴音）／phone_in_talk（聽筒），且關閉狀態
                      //   不再用灰階——聽筒不是「停用」，兩態都是正常可用的來源。
                      _buildControlButton(
                        icon: _isSpeakerOn
                            ? Icons.volume_up
                            : Icons.phone_in_talk,
                        onPressed: _toggleSpeaker,
                        color: Colors.white,
                      ),
                      // 麥克風
                      _buildControlButton(
                        icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                        onPressed: _toggleMic,
                        color: _isMicMuted ? Colors.redAccent : Colors.white,
                        bgColor: _isMicMuted ? Colors.white24 : null,
                      ),
                      // 掛斷
                      // ★ 2026-08-10 第二十輪（需求 3）：家屬端監控檢視不再顯示
                      //   「掛電話」按鈕，只保留左上角的返回鍵。監控是單向觀看、
                      //   不是一通「電話」，掛斷的隱喻本身就是錯的；而且返回鍵
                      //   走的是 `returnByPop: true` 的既有離開路徑（護欄 G31 的
                      //   唯一例外），兩個出口並存只會讓使用者選到錯的那個。
                      if (!widget.monitorViewOnly)
                        _buildControlButton(
                          icon: Icons.call_end,
                          onPressed: _safeHangUp,
                          isEndCall: true,
                        ),
                      // 鏡頭
                      // ★ 2026-08-10 第十九輪（需求 2）：單向監控只留麥克風／擴音／掛斷，
                      //   兩個鏡頭類按鈕整組隱藏（見 CLAUDE_call-monitor.md §7 G55）。
                      if (!widget.monitorViewOnly)
                        _buildControlButton(
                          icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                          onPressed: _toggleCamera,
                          color: _isCameraOff ? Colors.redAccent : Colors.white,
                          bgColor: _isCameraOff ? Colors.white24 : null,
                        ),
                      // 翻轉鏡頭
                      if (!widget.monitorViewOnly)
                        _buildControlButton(
                          icon: Icons.cameraswitch,
                          onPressed: (_mediaInitialized && !_isCameraOff) ? _switchCamera : null,
                          color: (_mediaInitialized && !_isCameraOff) ? Colors.white : Colors.white24,
                          bgColor: (_mediaInitialized && !_isCameraOff) ? null : Colors.white.withValues(alpha: 0.1),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    VoidCallback? onPressed,
    Color color = Colors.white,
    Color? bgColor,
    bool isEndCall = false,
  }) {
    final isDisabled = onPressed == null;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isEndCall 
          ? Colors.redAccent 
          : (bgColor ?? (isDisabled ? Colors.white.withValues(alpha: 0.05) : Colors.white12)),
        shape: BoxShape.circle,
        border: isDisabled ? Border.all(color: Colors.white12, width: 1) : null,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}
