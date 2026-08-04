import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/signaling.dart';
import '../services/api_service.dart';
import '../widgets/heartbeat_overlay.dart';
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
  bool _mediaInitialized = false;
  Timer? _callTimer;
  int _callDuration = 0; // 秒數

  /// ★ 2026-08-04 第 7 項：CCTV 影格推送給後端做 YOLO 跌倒偵測。
  /// 只在 `widget.isCCTVMode == true` 時啟動——一般通話路徑完全不建立這個計時器、
  /// 不呼叫 captureFrame，位元組層級與修改前相同，不影響通話品質與時序。
  Timer? _cctvFrameTimer;

  /// 上一張影格是否仍在上傳中。網路變慢時直接跳過該輪，**絕不排隊**，
  /// 避免計時器堆積把長輩機的記憶體與上行頻寬吃光（與後端限流丟幀策略一致）。
  bool _cctvFrameSending = false;
  int? _userId; // ★ issue 3/10：用於安全導航回主畫面時建構 ElderHomeScreen
  String? _prefsUserName; // ★ Issue 1 硬化：真實 caregiver_name，供 _buildFallbackHome 使用

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
  void _startCctvFrameLoop() {
    _cctvFrameTimer?.cancel();
    _cctvFrameTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _cctvFrameSending) return;
      final videoTracks = _signaling.localStream?.getVideoTracks();
      if (videoTracks == null || videoTracks.isEmpty) return;

      _cctvFrameSending = true;
      try {
        final buffer = await videoTracks.first.captureFrame();
        await ApiService.pushCctvFrame(
          elderId: _rawElderId,
          deviceName: widget.deviceName,
          frameBytes: buffer.asUint8List(),
        );
      } catch (e) {
        debugPrint('⚠️ [CCTV] 影格推送失敗（略過本輪，不中斷迴圈）: $e');
      } finally {
        _cctvFrameSending = false;
      }
    });
    debugPrint('🎥 [CCTV] 已啟動影格推送迴圈 (elder=$_rawElderId, device=${widget.deviceName})');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _checkPermissions();
    
    // ★ 初始化格式化的房間ID
    _formattedRoomId = _getFormattedRoomId(widget.roomId);

    // 「電話」與「視訊」共用同一套 call-request 後端邏輯；
    // 唯一差異只在進房時鏡頭預設狀態。
    if (widget.isCCTVMode) {
      _isCameraOff = false;
    } else {
      _isCameraOff = !widget.isVideoCall;
    }

    // ★ Bug 16 解決方案：監聽從系統層 (main.dart) 傳進來的 CallKit 接聽動作
    pendingAcceptedCall.addListener(_onPendingCallChanged);

    _initElderMode();

    if (widget.autoCall) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isInCall) {
          _makeCall();
        }
      });
    }
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

  Future<void> _handleEmergencyAccept(String senderId, {String? callId}) async {
    if(!_isInCall && mounted) {
      _activeCallId = callId; // ★ 第十三輪：記錄進行中通話，供 isSameOngoingCall 去重
      setState(() {
        _isInCall = true;
        _status = "緊急通話自動接聽中...";
      });
      
      // Clear CallKit ringing
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint("Failed to end CallKit calls: $e");
      }
      
      FlutterTts flutterTts = FlutterTts();
      await flutterTts.setLanguage("zh-TW");
      await flutterTts.setVolume(1.0);
      await flutterTts.speak("緊急通話，自動接聽中。緊急通話，自動接聽中。");

      // Notify the Family App that we are awake and ready to receive the Offer!
      _signaling.sendCallAccept(senderId, callId: callId);
    }
  }

  Future<void> _initElderMode() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onLocalStream = ((stream) {
      debugPrint("🤳 [ElderScreen] Local stream set! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onAddRemoteStream = ((stream) {
      debugPrint("📺 [ElderScreen] Remote stream added! Tracks: ${stream.getTracks().length}");
      if (mounted) {
        setState(() { 
          _remoteRenderer.srcObject = stream; 
          _status = "通話中"; 
          _isInCall = true;
          _callDuration = 0;
        });
        _startCallTimer();
      }
    });

    _signaling.onJoinFailed = (errorMessage) {
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
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('連線失敗'),
            content: Text(errorMessage),
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
    
    // ★ 修復：若 Socket 已經連線（從 ElderHomeScreen 傳承下來），則不要重新連線，
    //   否則會導致原本的 callbacks 被覆寫。若是從 CCTV 模式直接進入，則會在此處連線。
    if (_signaling.socket?.connected != true) {
      debugPrint("🔌 [ElderScreen] Socket 未連線，開始連線 (room: $_formattedRoomId)...");
      final String? fcmToken = await FirebaseMessaging.instance.getToken();
      _signaling.connect(
        _formattedRoomId,  // ★ 使用格式化的房間ID，而不是原始的 roomId
        'elder', 
        userId: resolvedUserId,  // ★ 修復：使用真正的 user_id（caregiver_id）或 elder_id 作為備用
        deviceName: widget.deviceName,
        deviceMode: widget.isCCTVMode ? 'monitor' : 'comm',
        fcmToken: fcmToken,
      );
    } else {
      debugPrint("🔌 [ElderScreen] Socket 已連線，重用現有連線 (room: $_formattedRoomId)");
    }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("家人目前無法接聽通話")),
        );
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
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "連線中斷";
          _isInCall = false;
        });
        if (!widget.isCCTVMode) {
          safeNavigateBack(context, _buildFallbackHome());
        }
      }
    };

    _signaling.socket?.on('force-logout', (_) async {
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
    });

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

  }

  // ★ 新增：懶加載媒體初始化
  Future<void> _initializeMedia() async {
    if (_mediaInitialized) return;
    try {
      await _signaling.openUserMedia(_localRenderer); // 永遠要求影像軌道
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        for (var track in videoTracks) {
          track.enabled = !_isCameraOff; // 預設關閉，保護隱私
        }
      }
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
      setState(() => _isCameraOff = !_isCameraOff);
      
      if (_isCameraOff) {
        _signaling.localStream?.getVideoTracks().forEach((track) => track.enabled = false);
      } else {
        _signaling.localStream?.getVideoTracks().forEach((track) => track.enabled = true);
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

  // ★ 新增：通話計時器
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // 主動呼叫 (先響鈴)
  void _makeCall() {
    setState(() { _status = "正在呼叫家人..."; _isInCall = true; });
    _signaling.sendCallRequest(_formattedRoomId, role: 'elder', isVideoCall: widget.isVideoCall);  // ★ 使用格式化的房間ID
    // ★ 2026-07-18：長輩端主動撥打新增 30 秒逾時。原本完全沒有逾時，
    //   家屬未接時只能靠手動掛斷，被叫方 CallKit 也會一直響。逾時自動取消。
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _status == "正在呼叫家人...") {
        debugPrint("⏰ [ElderScreen] 撥打逾時，自動取消通話");
        _signaling.sendCancelCall(_formattedRoomId, role: 'elder');
        _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
        setState(() {
          _remoteRenderer.srcObject = null;
          _status = "對方未接聽";
          _isInCall = false;
        });
        if (!widget.isCCTVMode) {
          safeNavigateBack(context, _buildFallbackHome());
        }
      }
    });
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_is_cctv');
      await prefs.remove('saved_role');
      await prefs.remove('saved_id');
      await prefs.remove('saved_device_name');
      await prefs.remove('user_role');
      await prefs.remove('caregiver_id');
      await prefs.remove('caregiver_name');

      _signaling.clearSession();
      _signaling.forceDisconnect();

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
    
    // ★ 修復：只結束 WebRTC，不要斷開 Socket，這樣回到 ElderHomeScreen 時才能繼續接收推播
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    
    // ★ 清空 UI 相關的 callbacks，讓全域的 callbacks 重拾控制權
    _signaling.onCallAcceptedByRemote = null;
    _signaling.onCallBusy = null;
    _signaling.onCallEnded = null;
    _signaling.onConnectionLost = null;
    _signaling.onAddRemoteStream = null;
    _signaling.onLocalStream = null;
    _signaling.onJoinFailed = null;
    _signaling.onIncomingCall = null;
    _signaling.onHeartbeatMessage = null;
    
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
