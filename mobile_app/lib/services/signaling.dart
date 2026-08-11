// lib/services/signaling.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../globals.dart';
import 'api_service.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef IncomingCallCallback = Future<bool> Function(String callerId, String callType);
// NOTE: 不要重新定義 VoidCallback，Flutter 已內建
typedef ErrorCallback = void Function(String message);
typedef CallRequestCallback = void Function(String roomId, String senderId, String? callId, [String? senderName]);
typedef CallAcceptedCallback = void Function(String accepterId, String? callId);

/// ★ 2026-08-06 第十九輪（需求 3）：四種「沒接通」情境的固定文案。
/// 由使用者指定，四種必須彼此可區分。集中在這裡，避免三個畫面各自漂移。
const String kCallFailDeclined = '對方暫時無法接聽';   // 對方按下拒接
const String kCallFailBusy = '對方正在通話中';         // 對方正在另一通通話中
const String kCallFailDisconnected = '連線中斷';       // 通話中連線掉了
const String kCallFailUnreachable = '無法連線';        // ICE 或伺服器層面根本連不上

/// 把 `call-busy` 帶回來的 reason 轉成給使用者看的文案。
/// 未知或缺漏一律退回「拒接」文案（安全預設：不會謊稱對方在通話中）。
String callBusyMessageFor(String reason) {
  switch (reason) {
    case 'busy':
      return kCallFailBusy;
    case 'server-error':
      return kCallFailUnreachable;
    default:
      return kCallFailDeclined;
  }
}

class Signaling {
  static const String _serverIp = String.fromEnvironment('SERVER_IP', defaultValue: 'localhost-0.tail5abf5e.ts.net');
  static const String _turnServer = String.fromEnvironment('TURN_SERVER', defaultValue: '152.69.196.5:3478');
  static const String _turnUser = String.fromEnvironment('TURN_USER', defaultValue: 'uban');
  static const String _turnPass = String.fromEnvironment('TURN_PASS', defaultValue: '115207');
  
  static String? _overrideServerUrl;

  static String get serverUrl {
    if (_overrideServerUrl != null) return _overrideServerUrl!;
    if (_serverIp.startsWith('http://') || _serverIp.startsWith('https://')) {
      return _serverIp;
    }
    if (_serverIp.contains('ts.net') || _serverIp.contains('ngrok')) {
      return 'https://$_serverIp';
    }
    return 'http://$_serverIp:8000';
  }

  static const platform = MethodChannel('com.example.app/bring_to_front');

  // ★ Singleton Pattern
  static final Signaling _instance = Signaling._internal();
  factory Signaling() => _instance;
  Signaling._internal();

  io.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  
  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onLocalStream;
  Function(List<dynamic>)? onElderDevicesUpdate;
  IncomingCallCallback? onIncomingCall;
  VoidCallback? onCallEnded;
  /// ★ 2026-08-06 第十九輪（A5）：join 被後端拒絕時觸發。原本只有 message，
  ///   family/monitor 綁定失敗時看不出真正原因（missing_room／invalid_room／
  ///   missing_user／unauthorized／monitor-limit／ip_limit_exceeded）。
  ///   新增具名參數 reason 帶出後端原文代碼，message 維持給使用者看的文字不變。
  Function(String message, {String? reason})? onJoinFailed;
  CallRequestCallback? onCallRequest;
  /// ★ 2026-08-04：後端推送 force-logout（家屬端解除本長輩綁定）時觸發。
  ///   由 main.dart 註冊，負責清除 session 並導航回身分選擇介面。
  void Function()? onForceLogout;
  /// ★ 2026-08-06 第十九輪（D4）：後端監視機被家屬端改名時觸發。
  ///   payload: {elderId, oldDeviceName, newDeviceName, deviceId}。
  ///   只由 CCTV 模式的畫面（elder_screen.dart）註冊，一般通訊模式沒有這個概念。
  Function(Map<String, dynamic>)? onMonitorRenamed;
  /// ★ 2026-08-10 第二十輪（需求 4）：家屬端在監控清單刪除本機時觸發。
  ///   payload: {elderId, deviceName, reason}。
  ///   只由 CCTV 模式的畫面（elder_screen.dart）註冊；處理端必須走
  ///   `SessionManager.releaseSession()` 完整釋放 session（需求 5），
  ///   否則這台裝置之後再也綁不回去。
  Function(Map<String, dynamic>)? onMonitorRemoved;
  CallRequestCallback? onCancelCall;
  CallRequestCallback? onEmergencyCall;
  CallAcceptedCallback? onCallAcceptedByRemote;
  CallAcceptedCallback? onCallBusy;
  /// ★ 2026-08-06 第十九輪（需求 3）：與 [onCallBusy] 同步配對的**純資料**欄位。
  /// 在觸發 onCallBusy 之前寫入、回呼內同步讀取，語意與 `lastProcessedCallId` 同一類，
  /// 不是顯示狀態旗標（護欄 G27）。讀不到就是預設的 'declined'。
  String lastCallBusyReason = 'declined';
  VoidCallback? onConnectionLost;
  /// ★ 2026-08-05 第十七輪：ICE **真正**連通（RTCPeerConnectionStateConnected）時觸發。
  /// `onAddRemoteStream` 只代表 SDP 談成，不代表有任何媒體流動，不可用來判定通話已建立。
  VoidCallback? onPeerConnected;
  /// ICE 連線失敗且自動 ICE restart 也救不回來時觸發（參數為給使用者看的訊息）。
  ErrorCallback? onPeerConnectionFailed;
  Function(String message)? onHeartbeatMessage; // 新增：主動式心跳消息回傳
  Function(String text, String type)? onNewPondLeaf; // 新增：記憶落葉話題推播

  String? _currentRoomId;
  String? _peerSocketId;
  String? _currentCallId; // 追蹤當前通話 ID，確保 hangUp 時能傳給後端
  String? lastProcessedCallId; // ★ 問題4修復：記錄最後一個已處理的來電 ID，防止重複
  int lastProcessedCallTime = 0; // ★ 問題4修復：記錄最後一個已處理來電的時間戳，用於去重檢查
  // ★ Fix E：記錄目前處理中來電的 callId 與其視訊/語音旗標，供 main.dart 在
  //   同一 isolate 存活的前景 Socket 接聽路徑（如 _showIncomingCallDialog 直接
  //   呼叫 _navigateToVideoCall）查詢。CallKit/FCM 冷啟動路徑改走
  //   pendingAcceptedCall 攜帶的 isVideoCall 欄位，不依賴此處。
  String? incomingCallIsVideoCallId;
  bool incomingCallIsVideo = true;
  dynamic _userId; // 新增：儲存當前使用者的資料庫 ID
  String? _role; // 新增：儲存當前連線的角色
  String? _deviceName;
  String? _deviceMode;
  String? _elderId; // ★ 新增：儲存當前 elder_id，用於 TURN 隔離
  bool _isCreatingOffer = false; // ⭐ 防重複呼叫 createOffer
  bool _isAppForeground = true;
  final List<RTCIceCandidate> _candidateQueue = [];
  final List<String> _pendingRooms = [];
  final Set<String> _invalidCallIds = <String>{};
  /// ★ 2026-08-05 第十七輪：`onTrack` 只代表 SDP 談成，ICE 是否連通、有沒有位元組
  /// 在流動完全無關。這裡在收到遠端 track 後 12 秒檢查一次 inbound-rtp 的
  /// bytesReceived，仍為 0 就據實回報 —— 這正是「有通話計時卻雙方都看不到聽不到」的症狀。
  Timer? _mediaWatchdogTimer;

  /// ★ 2026-07-22 第八輪 Fix 2C：供 main.dart FCM handler 於拒接/取消時標記
  ///   callId 失效，後續延遲抵達的同一 `call-request`（Socket 或 FCM）將直接丟棄，
  ///   避免「拒接後又響」與角色反轉迴圈。
  bool isCallInvalidated(String? callId) =>
      callId != null && callId.isNotEmpty && _invalidCallIds.contains(callId);

  /// ★ Fix E（2026-08-02 第十四輪修正）：依 callId 查詢是否為視訊通話；
  ///   callId 不吻合或查無紀錄時預設為 true。旗標解析改用 globals.dart 的
  ///   parseIsVideoCall（共用解析器，相容 bool 與後端 str(bool) 產生的大小寫字串）。
  bool isVideoCallFor(String? callId) {
    if (callId != null && callId.isNotEmpty && callId == incomingCallIsVideoCallId) {
      return incomingCallIsVideo;
    }
    return true;
  }

  void invalidateCallId(String? callId) {
    if (callId != null && callId.isNotEmpty) {
      _invalidCallIds.add(callId);
      debugPrint('⛔ [Signaling] callId 已標記失效: $callId');
    }
  }

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': [
          'turn:$_turnServer',
          'turn:$_turnServer?transport=tcp',
        ],
        'username': _turnUser,
        'credential': _turnPass,
      },
    ]
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  StreamSubscription<String>? _tokenRefreshSubscription;

  void _setupTokenMonitor() {
    if (kIsWeb) return; // Firebase Messaging not initialized for web
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🆕 [Signaling] FCM Token Refreshed: ${newToken.substring(0, 10)}...");
      if (socket != null && socket!.connected && _currentRoomId != null) {
        socket!.emit('update-fcm-token', {
          'room': _currentRoomId,
          'token': newToken,
        });
      }
    });
  }

  void connect(String roomId, String role, {dynamic userId, String deviceName = 'Unknown', String deviceMode = 'comm', String? fcmToken}) {
    _currentRoomId = roomId;
    _userId = userId;
    _role = role;
    _deviceName = deviceName;
    _deviceMode = deviceMode;
    
    // ★ 解析房間 ID 以提取 elder_id
    if (roomId.contains('elder_')) {
      _elderId = roomId.split('elder_').last;
      debugPrint("🔐 [Signaling] Extracted elder_id from room: $_elderId");
    }

    if (socket != null && socket!.connected) {
      debugPrint("♻️ Reusing existing socket connection. Joining room $roomId...");
      _asyncJoin(roomId, role, deviceName, deviceMode, fcmToken: fcmToken);
      return;
    }

    // ★ 2026-08-11 第二十二輪（需求 8：從監視機跳回長輩端後通話全滅）：
    //   走到這裡代表 socket 為 null 或**已斷線**。原本的寫法直接用新的 `io.io(...)`
    //   覆蓋掉 `socket`，那個已斷線的舊 Socket 物件既沒被 `dispose()`、也沒被
    //   `clearListeners()`，就這樣變成孤兒——它身上仍掛著上一輪註冊的所有 handler
    //   （`call-request`、`offer`、`force-logout`…），底層 Manager 也還在跑重連排程。
    //   一旦它自己重連成功，就會用**舊的** sid 收到信令，而畫面上的邏輯早已綁在新
    //   socket 上：於是「來電通知收得到（FCM 那條路獨立），但 offer/answer 走錯 socket
    //   → 雙端永遠連不上」，且孤兒 socket 越疊越多（每進出一次監控就多一個），
    //   背景重連風暴最終拖成 ANR。
    //   ⚠️ 監控機模式（`elder_screen` CCTV）進出頻繁，是最容易踩到的路徑。
    _disposeSocket('connect() 建立新連線前清除舊的斷線 socket');

    debugPrint("🔌 Creating new socket connection...");
    socket = io.io(serverUrl, io.OptionBuilder()
      .setTransports(['websocket', 'polling'])
      .disableAutoConnect()
      .build()
    );

    _registerSocketListeners(roomId, role, deviceName, deviceMode, fcmToken);
    socket!.connect();
    _setupTokenMonitor();
  }

  void reconnect() {
    if (_currentRoomId == null || socket == null) return;
    debugPrint("🔄 [Signaling] Manual Reconnect/Rejoin triggered for room $_currentRoomId");
    if (!socket!.connected) {
      socket!.connect();
    } else {
      // 如果已經連著，也要重新 emit join 確保伺服器狀態正確
      _asyncJoin(_currentRoomId!, _role ?? 'family', _deviceName ?? 'Reconnected_Device', _deviceMode ?? 'comm'); 
    }
  }

  Future<void> _asyncJoin(String roomId, String role, String deviceName, String deviceMode, {dynamic userId, String? fcmToken}) async {
    String? effectiveToken = fcmToken;
    if (effectiveToken == null && !kIsWeb) {
      try {
        effectiveToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint("⚠️ Failed to auto-capture FCM Token: $e");
      }
    }
    _emitJoin(roomId, role, deviceName, deviceMode, userId: userId ?? _userId, fcmToken: effectiveToken);
  }

  void _registerSocketListeners(String roomId, String role, String deviceName, String deviceMode, String? fcmToken) {
    int connectErrorCount = 0;
    socket!.onConnectError((err) {
      debugPrint('❌ Socket Connect Error: $err (Server: $serverUrl)');
      connectErrorCount++;
      if (connectErrorCount >= 2 && _overrideServerUrl == null && serverUrl.contains('ts.net')) {
        debugPrint('🔄 [Signaling Fallback] Socket Handshake Error. Fallback to local dev server http://10.0.2.2:8000...');
        _overrideServerUrl = 'http://10.0.2.2:8000';
        try {
          socket?.disconnect();
          socket?.dispose();
        } catch (_) {}
        socket = null;
        connect(roomId, role, userId: _userId, deviceName: _deviceName ?? 'Unknown', deviceMode: _deviceMode ?? 'comm', fcmToken: fcmToken);
      }
    });
    socket!.onError((err) => debugPrint('❌ Socket Error: $err'));

    socket!.onDisconnect((reason) {
      debugPrint('⚠️ [Signaling] Socket disconnected: $reason');
      // ★ issue 5：通話進行中若 Socket 短暫斷線（例如冷啟動切換網路時），
      //   不要立刻觸發 onConnectionLost 把使用者彈回主畫面，給予 15 秒重連寬限期。
      if (peerConnection != null) {
        debugPrint('⚠️ [Signaling] Disconnected during active call, granting 15s reconnect window...');
        Future.delayed(const Duration(seconds: 15), () {
          if (socket != null && !socket!.connected && peerConnection != null) {
            debugPrint('❌ [Signaling] Reconnect window expired, notifying connection lost');
            if (onConnectionLost != null) onConnectionLost!();
          }
        });
      } else {
        if (onConnectionLost != null) onConnectionLost!();
      }
    });

    socket!.onConnect((_) async {
      debugPrint('✅ Socket 連線成功 (SID: ${socket!.id})');
      _asyncJoin(roomId, role, deviceName, deviceMode, fcmToken: fcmToken);
      
      for (var pendingRoom in _pendingRooms) {
        _asyncJoin(pendingRoom, 'family', 'Dashboard_Listener', 'listener', fcmToken: fcmToken);
      }
      _pendingRooms.clear();
    });

    socket!.on('join-failed', (data) {
      if (onJoinFailed != null) {
        onJoinFailed!(data['message']?.toString() ?? '加入房間失敗',
            reason: data['reason']?.toString());
      }
      // 僅在尚未建立有效連線時才斷開 socket，避免通話中因競態 join-failed 斷線
      if (peerConnection == null) {
        socket?.disconnect();
      } else {
        debugPrint('⚠️ [Signaling] Join-failed during call, keeping connection');
      }
    });

    // 響鈴監聽
    socket!.on('call-request', (data) {
      if (data['senderId'] == socket!.id) {
        debugPrint('📞 [Signaling] 忽略自己發出的 call-request (SenderId: ${data['senderId']})');
        return;
      }
      final String? senderRole = data['role']?.toString();
      if (senderRole != null && _role == senderRole) {
        debugPrint('📞 [Signaling] 忽略相同角色發出的 call-request (SenderRole: $senderRole)');
        return;
      }
      
      // ★ 問題4修復：檢查是否已在短時間內處理過此 callId（防止重複）
      final String callId = data['callId'] ?? '';
      if (callId.isNotEmpty && _invalidCallIds.contains(callId)) {
        debugPrint('⛔ [Signaling] Ignore invalidated call-request (callId=$callId)');
        return;
      }
      if (_isExpiredCallPayload(data)) {
        debugPrint('⏰ [Signaling] Ignore expired call-request (callId=$callId)');
        if (callId.isNotEmpty) {
          _invalidCallIds.add(callId);
        }
        return;
      }
      final int currentTime = DateTime.now().millisecondsSinceEpoch;
      if (callId.isNotEmpty && callId == lastProcessedCallId && 
          (currentTime - lastProcessedCallTime) < 2000) { // 2秒去重窗口
        debugPrint('⚠️ [Signaling] 忽略重複的 call-request（CallId 已在 2 秒內處理: $callId）');
        return;
      }
      
      // ★ 更新最後處理的來電 ID 和時間戳
      lastProcessedCallId = callId;
      lastProcessedCallTime = currentTime;

      // ★ Fix E：記錄本通來電是否為視訊，供 isVideoCallFor() 查詢。
      incomingCallIsVideoCallId = callId;
      incomingCallIsVideo = parseIsVideoCall(data['isVideoCall']);

      debugPrint('📞📞📞 [Signaling] ===== 收到 call-request =====');
      debugPrint('📞 [Signaling] data: $data');
      debugPrint('📞 [Signaling] room: ${data['room']}, senderId: ${data['senderId']}, callId: ${data['callId']}');
      debugPrint('📞 [Signaling] onCallRequest callback is ${onCallRequest != null ? "SET" : "NULL"}');
      _currentCallId = data['callId'];
      if (onCallRequest != null) {
        debugPrint('📞 [Signaling] 觸發 onCallRequest 回調...');
        // ★ issue 11：透傳後端解析出的來電者名稱，避免 UI 端用「目前選擇的長輩」誤判來電者
        final String? senderName = (data['senderName'] ?? data['callerName'])?.toString();
        onCallRequest!(data['room'], data['senderId'], data['callId'], senderName);
      } else {
        debugPrint('⚠️ [Signaling] onCallRequest 回調未設置！來電將被忽略！');
      }
    });

    // 取消呼叫監聽
    socket!.on('cancel-call', (data) {
      if (data['senderId'] == socket!.id) {
        debugPrint('🔕 [Signaling] 忽略自己發出的 cancel-call (SenderId: ${data['senderId']})');
        return;
      }
      final String? senderRole = data['role']?.toString();
      if (senderRole != null && _role == senderRole) {
        debugPrint('🔕 [Signaling] 忽略相同角色發出的 cancel-call (SenderRole: $senderRole)');
        return;
      }
      debugPrint('🔕 [Signaling] 收到 cancel-call: $data');
      final String callId = (data['callId'] ?? '').toString();
      if (callId.isNotEmpty) {
        _invalidCallIds.add(callId);
      }
      if (!kIsWeb) {
        FlutterCallkitIncoming.endAllCalls();
      }
      if (onCancelCall != null) onCancelCall!(data['room'], data['senderId'], data['callId']);
    });

    // 緊急呼叫監聽
    socket!.on('emergency-call', (data) {
      debugPrint('🚨 [Signaling] 收到 emergency-call: $data');
      if (data['senderId'] == socket!.id) {
        debugPrint('🚨 [Signaling] 忽略自己發出的 emergency-call');
        return;
      }
      final String? senderRole = data['role']?.toString();
      if (senderRole != null && _role == senderRole) {
        debugPrint('🚨 [Signaling] 忽略相同角色發出的 emergency-call (SenderRole: $senderRole)');
        return;
      }

      // ★ 2026-07-27 第十三輪（緊急通話瞬間掛斷根因修復）：
      //   emergency-call 先前完全沒有記錄 lastProcessedCallId（一般 call-request 有），
      //   導致 ElderScreen._checkPendingAcceptedCall 的 isSameOngoingCall 判斷恆為
      //   false —— 任何第二次寫入 pendingAcceptedCall（Socket/FCM 雙通道、CallKit
      //   兜底輪詢）都會被誤判成「另一通新來電」而 hangUp() 掉正在進行的緊急通話，
      //   對端（家屬）於是收到 end-call 瞬間掛斷。這裡補齊，與 call-request 對齊。
      final String callId = (data['callId'] ?? '').toString();
      if (callId.isNotEmpty && _invalidCallIds.contains(callId)) {
        debugPrint('⛔ [Signaling] Ignore invalidated emergency-call (callId=$callId)');
        return;
      }
      final int currentTime = DateTime.now().millisecondsSinceEpoch;
      if (callId.isNotEmpty &&
          callId == lastProcessedCallId &&
          (currentTime - lastProcessedCallTime) < 2000) {
        debugPrint('⚠️ [Signaling] 忽略重複的 emergency-call（CallId 已在 2 秒內處理: $callId）');
        return;
      }
      if (callId.isNotEmpty) {
        lastProcessedCallId = callId;
        lastProcessedCallTime = currentTime;
      }
      _currentCallId = data['callId'];

      if (onEmergencyCall != null) {
        // ★ issue 11：透傳來電者名稱
        final String? senderName = (data['senderName'] ?? data['callerName'])?.toString();
        onEmergencyCall!(data['room'], data['senderId'], data['callId'], senderName);
      }
    });


    // 對方接聽監聽
    socket!.on('call-accept', (data) {
      debugPrint("📞 [Signaling] Received call-accept (AccepterId: ${data['accepterId']}, CallId: ${data['callId']})");
      _peerSocketId = data['accepterId'];
      _currentCallId = data['callId'];
      
      if (onCallAcceptedByRemote != null) {
        onCallAcceptedByRemote!(data['accepterId'], data['callId']);
      } else {
        // ★ 如果沒有 UI 層處理，才自動發送 Offer（防止重複 Offer）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint("🔄 [Signaling] No UI handler, auto-starting createOffer to ${data['accepterId']}");
          createOffer(targetId: data['accepterId']);
        });
      }
    });

    // 忙線/拒接監聽
    socket!.on('call-busy', (data) {
      debugPrint('🚫 [Signaling] 收到 call-busy: $data');
      // ★ issue 15：對方拒接/忙線時，呼叫端必須立即結束「等待連線」狀態，
      //   避免持續卡在 PeerConnection 已建立但對端永遠不會回應的情形。
      _isCreatingOffer = false;
      _closePeerConnection();
      _currentCallId = null;
      final String callId = (data['callId'] ?? '').toString();
      if (callId.isNotEmpty) {
        _invalidCallIds.add(callId);
      }
      if (!kIsWeb) {
        FlutterCallkitIncoming.endAllCalls();
      }
      // ★ 2026-08-06 第十九輪（需求 3）：先記下原因，讓回呼能區分拒接／忙線／伺服器錯誤。
      lastCallBusyReason = (data['reason'] ?? 'declined').toString();
      if (onCallBusy != null) onCallBusy!(data['targetId'], data['callId']);
    });

    socket!.on('elder-devices-update', (devices) {
      debugPrint("📡 [Signaling] Received elder-devices-update (count: ${devices.length})");
      if (onElderDevicesUpdate != null) onElderDevicesUpdate!(devices);
    });

    // ★ 2026-08-04：force-logout 必須在此註冊。原本寫在 main.dart 的
    //   `s.socket?.on('force-logout', ...)` 於 initState 執行，當時 socket 仍為 null，
    //   `?.` 短路導致從未掛上；即使掛上，connect() 重建 socket 物件後也會失效。
    socket!.on('force-logout', (_) {
      debugPrint("🚪 [Signaling] Received force-logout (家屬端已解除綁定)");
      if (onForceLogout != null) onForceLogout!();
    });

    // ★ 2026-08-06 第十九輪（D4）：監視機被家屬端改名時，即時同步通知該監視機本身。
    socket!.on('monitor-renamed', (data) {
      debugPrint("✏️ [Signaling] Received monitor-renamed: $data");
      if (onMonitorRenamed != null) {
        onMonitorRenamed!(Map<String, dynamic>.from(data as Map));
      }
    });

    // ★ 2026-08-10 第二十輪（需求 4）：家屬端刪除監視器後，監控機必須**立刻**
    //   退回主畫面。原本後端只是 `sio.disconnect(kick_sid)`，監控機端看不出
    //   自己是「被刪除」還是「網路斷線」，於是停在 CCTV 畫面等重連——
    //   使用者只能手動按「退出並重置」，而那條路徑又踩到需求 5 的綁死問題。
    //   後端現在會在 disconnect **之前**先送這個事件（見 pairing.py
    //   delete_monitor_device），順序不可對調，否則事件送不出去。
    socket!.on('monitor-removed', (data) {
      debugPrint("🗑️ [Signaling] Received monitor-removed: $data");
      if (onMonitorRemoved != null) {
        onMonitorRemoved!(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
      }
    });

    socket!.on('offer', (data) async {
      final senderId = data['senderId'];
      final callId = data['callId'];
      debugPrint('📩 [Signaling] RECEIVED OFFER from $senderId (CallId: $callId)');
      
      // ★ 問題4修復：檢查是否已在短時間內處理過此 callId（防止重複）
      final int currentTime = DateTime.now().millisecondsSinceEpoch;
      if (callId != null && callId == lastProcessedCallId && 
          (currentTime - lastProcessedCallTime) < 2000) { // 2秒去重窗口
        debugPrint('⚠️ [Signaling] 忽略重複的 offer（CallId 已在 2 秒內處理: $callId）');
        return;
      }
      
      // ★ 更新最後處理的來電 ID 和時間戳
      if (callId != null) {
        lastProcessedCallId = callId;
        lastProcessedCallTime = currentTime;
      }
      
      _peerSocketId = senderId;
      _candidateQueue.clear();

      bool isEmergency = data['isEmergency'] == true;
      if (isEmergency && !kIsWeb) {
        try { await platform.invokeMethod('bringToFront'); } catch (e) { debugPrint('BringToFront error: $e'); }
        try { 
          VolumeController.instance.showSystemUI = false;
          VolumeController.instance.setVolume(1.0); 
        } catch (e) { debugPrint('Volume control error: $e'); }
      }

      bool shouldAnswer = false;
      if (onIncomingCall != null) {
        shouldAnswer = await onIncomingCall!(_peerSocketId!, isEmergency ? 'emergency' : 'normal');
      } else {
        // !!!!除非要更新視訊通話邏輯，否則禁止更動!!!!
        // onIncomingCall 為空時，不能在 offer 階段再彈第二套 CallKit UI。
        // 來電 UI 只允許由 call-request 路徑（main.dart / 各首頁）處理，
        // 否則會出現隨機雙樣式、雙重推播與錯誤接聽路徑（只開 APP 不進通話房）。
        if (isEmergency) {
          shouldAnswer = true;
        } else {
          final String incomingCallId = (data['callId'] ?? '').toString();
          final bool isKnownAcceptedCall = incomingCallId.isNotEmpty &&
              (incomingCallId == _currentCallId ||
                  incomingCallId == lastProcessedCallId);
          if (isKnownAcceptedCall) {
            debugPrint('✅ [Signaling] onIncomingCall 為空，沿用既有接聽狀態自動應答 (callId=$incomingCallId)');
            shouldAnswer = true;
          } else {
            debugPrint('⏭️ [Signaling] 略過未知 offer（未經 call-request 接聽鏈路）');
            shouldAnswer = false;
          }
        }
      }

      if (shouldAnswer) {
        await _acceptCall(data, useLocalStream: true); 
      }
    });

    socket!.on('answer', (data) async {
      debugPrint('📩 [Signaling] RECEIVED ANSWER from ${data['senderId']}');
      try {
        _peerSocketId = data['senderId'];
        var description = RTCSessionDescription(data['sdp'], data['type']);
        await peerConnection?.setRemoteDescription(description);
        await _processCandidateQueue();
      } catch (e) {
        debugPrint("❌ Answer Error: $e");
      }
    });

    socket!.on('candidate', (data) async {
      debugPrint('🧊 [Signaling] RECEIVED CANDIDATE from ${data['senderId'] ?? 'unknown'}');
      try {
        var candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        if (peerConnection != null) {
          await peerConnection!.addCandidate(candidate);
        } else {
          _candidateQueue.add(candidate);
        }
      } catch (e) {
        debugPrint("❌ Candidate Error: $e");
      }
    });

    socket!.on('end-call', (data) async {
      debugPrint("📴 收到掛斷訊號");
      final String callId = (data is Map ? (data['callId'] ?? '') : '').toString();
      if (callId.isNotEmpty) {
        _invalidCallIds.add(callId);
      }
      if (!kIsWeb) {
        await FlutterCallkitIncoming.endAllCalls();
      }
      await _closePeerConnection();
      if (onCallEnded != null) onCallEnded!();
    });
    
    // 客製化主動式巡檢消息
    socket!.on('heartbeat-message', (data) {
       debugPrint("💓 [Signaling] Received heartbeat-message: ${data['reply']}");
       if (onHeartbeatMessage != null) onHeartbeatMessage!(data['reply']);
    });

    // 記憶落葉話題推播（由後端排程或 API 觸發）
    socket!.on('new-pond-leaf', (data) {
      final text = (data['text'] ?? '').toString();
      final type = (data['type'] ?? 'memory').toString();
      debugPrint("🍂 [Signaling] Received new-pond-leaf: $text");
      if (text.isNotEmpty && onNewPondLeaf != null) {
        onNewPondLeaf!(text, type);
      }
    });
  }

  Future<bool> _showCallkitIncoming(String callerName) async {
    if (kIsWeb) return false;
    final uuid = const Uuid().v4();
    
    // ★ 新增：通知時手機振動（系統級振動）
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      HapticFeedback.heavyImpact();
    });
    
    // ★ 美化通知 UI 的參數配置
    final params = CallKitParams(
      id: uuid,
      nameCaller: callerName,  // 來電者名稱（例如「李奶奶」）
      appName: 'Uban',
      avatar: 'https://i.pravatar.cc/150?name=$callerName',  // ★ 動態頭貼，基於名稱生成
      handle: '📞 視訊通話',  // ★ 改進提示文字
      type: 0,  // 0 = audio, 1 = video
      duration: 45000,  // ★ CallKit 響鈴 45s（獨立於 kCallValidityMs 60s，接聽時限 ≠ FCM 有效期）
      textAccept: '✓ 接聽',  // ★ 加入emoji
      textDecline: '✕ 拒絕',  // ★ 加入emoji
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: '未接來電',
        callbackText: '回撥',
      ),
      extra: <String, dynamic>{'userId': '1a2b3c4d'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1a472a',  // ★ 深綠色背景，更沉靜專業
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',  // ★ 綠色按鈕（接聽）
        textColor: '#ffffff',  // ★ 白色文字
        incomingCallNotificationChannelName: 'Uban_Incoming_Call',
        isShowFullLockedScreen: true,  // ★ 鎖定屏幕時顯示全屏
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);

    bool accepted = false;
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      switch (event!.event) {
        case Event.actionCallAccept:
          accepted = true;
          break;
        case Event.actionCallDecline:
          accepted = false;
          break;
        default:
          break;
      }
    });

    // 等待用戶操作，這裡簡化處理，實際應用中需要更完善的異步等待機制 (Completer)
    await Future.delayed(const Duration(seconds: 5)); 
    return accepted;
  }

  void _emitJoin(String room, String role, String name, String mode, {dynamic userId, String? fcmToken}) async {
    debugPrint("📢 [Signaling] Emitting join: $room ($role) as $name (UID: $userId)");
    
    // ★ 先加入房間，不要被 FCM token 阻塞（避免卡住 join）
    socket!.emit('join', {
      'room': room, 
      'role': role, 
      'deviceName': name, 
      'deviceMode': mode,
      'userId': userId,
      'fcmToken': fcmToken,
      'appState': _isAppForeground ? 'foreground' : 'background',
    });

    // Web 端不需要 FCM token 更新
    if (kIsWeb) return;

    // Non-blocking FCM token retrieval (Mobile Only)
    FirebaseMessaging.instance.getToken().then((token) {
      if (token == null) return;
      debugPrint("🔔 [Signaling] FCM Token retrieved: ${token.substring(0, 8)}...");
      if (socket != null && socket!.connected) {
        socket!.emit('update-fcm-token', {
          'room': room,
          'token': token
        });
      }
    }).catchError((e) {
      debugPrint("⚠️ [Signaling] FCM Token failed: $e");
    });
  }

  void joinRoom(String roomId, {dynamic userId}) {
    if (socket != null && socket!.connected) {
      _emitJoin(roomId, 'family', 'Dashboard_Listener', 'listener', userId: userId ?? _userId);
    } else {
      _pendingRooms.add(roomId);
    }
  }

  void updateAppForeground(bool isForeground) {
    _isAppForeground = isForeground;
    if (socket != null && socket!.connected) {
      socket!.emit('client-state', {
        'appState': isForeground ? 'foreground' : 'background',
      });
    }
  }

  void enableSpeakerphone(bool enable) {
    if (kIsWeb) return;
    Helper.setSpeakerphoneOn(enable);
  }

  /// 送出撥打請求。
  ///
  /// ★ 2026-08-10 第二十輪（需求 7：長輩端在 App 內撥不出去）：
  ///   原本這裡是 `void` 且直接 `socket!.emit(...)`——socket 尚未連上時
  ///   socket.io client 會把事件**丟棄**（不是排隊），呼叫端卻毫不知情，
  ///   於是長輩端停在「正在呼叫家人...」直到 30 秒逾時，全程沒送出任何東西。
  ///   長輩端特別容易踩到：`ElderScreen` 是 initState 就 autoCall，
  ///   而 `connect()` 才剛開始握手。家屬端多半是先進主畫面（socket 早就連好）
  ///   才按撥打，所以只有長輩端會壞——這正是「不對稱失效」的線索。
  ///
  ///   改為與 [sendCallAccept] 同樣的連線輪詢（50 × 100ms，最多 5 秒，
  ///   對齊護欄「送 WebRTC 信令前必須輪詢等待 socket 連線」），
  ///   並回傳是否真的送出，讓呼叫端能立即顯示錯誤而不是空等 30 秒。
  ///
  ///   `_currentCallId` 刻意等到確認會送出才寫入：沒送出去的 callId 若留在
  ///   欄位上，後續 `hangUp()` 會拿它去 emit end-call，對端收到一個從未存在
  ///   的 callId。
  Future<bool> sendCallRequest(String room, {String role = 'family', String? callId, String? targetId, bool isVideoCall = true}) async {
    final String effectiveCallId = callId ?? const Uuid().v4();

    if (socket == null) {
      debugPrint('❌ [CallRequest] socket 為 null，無法送出撥打請求');
      return false;
    }

    int retries = 50;
    while (!socket!.connected && retries > 0) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries--;
    }

    if (!socket!.connected) {
      debugPrint('❌ [CallRequest] 等待 socket 連線逾時（5 秒），撥打請求未送出');
      return false;
    }

    _currentCallId = effectiveCallId;
    // issuedAt 在確認連線後才取，避免等待連線的時間白白吃掉 120 秒有效期。
    final int issuedAt = DateTime.now().millisecondsSinceEpoch;
    socket!.emit('call-request', {
      'room': room,
      'role': role,
      'callId': effectiveCallId,
      'issuedAt': issuedAt.toString(),
      'expiresAt': (issuedAt + kCallValidityMs).toString(),
      if (targetId != null) 'targetId': targetId,
      'callerUserId': _userId, // 新增：主動發送發起者的資料庫 ID
      if (_deviceName != null) 'senderName': _deviceName,
      'isVideoCall': isVideoCall.toString(), // ★ 2026-08-02 第十四輪：送字串，避免後端 str(bool) 產生大寫 "False"
    });
    return true;
  }

  // ★ Feature 13: 請求更新長輩設備列表
  void sendGetElderDevices(String roomId) {
    if (socket != null && socket!.connected) {
      socket!.emit('get-elder-devices', roomId);
    }
  }


  void sendCallAccept(String targetSocketId, {String? callId}) async {
    if (socket == null) return;
    
    int retries = 100;
    while (!socket!.connected && retries > 0) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries--;
    }

    if (socket!.connected) {
      debugPrint("✅ [Accept] Sending call-accept to $targetSocketId (CallId: $callId)");
      socket!.emit('call-accept', {'targetId': targetSocketId, 'callId': callId});
    } else {
      debugPrint("❌ [Accept] Socket connection timed out. Could not send accept.");
    }
  }

  void sendCallBusy(String targetSocketId, {String? callId, String? room, String? reason}) {
    final String? effectiveRoom = room ?? _currentRoomId;
    final String? effectiveCallId = callId ?? _currentCallId;
    // ★ 2026-08-06 第十九輪（需求 3）：區分「拒接」與「忙線」。
    //   peerConnection 不為 null 代表本機此刻真的還在一通通話裡 → 對發起端回報忙線。
    //   這只影響對方看到的**文案**，不會擋掉任何來電。
    final String effectiveReason =
        reason ?? (peerConnection != null ? 'busy' : 'declined');
    // ★ 拒接的 callId 立即失效，避免延遲到達的同一通 call-request 又響起。
    if (effectiveCallId != null && effectiveCallId.isNotEmpty) {
      _invalidCallIds.add(effectiveCallId);
    }
    if (socket != null && socket!.connected) {
      socket!.emit('call-busy', {
        'targetId': targetSocketId,
        'callId': effectiveCallId,
        'reason': effectiveReason,
      });
    } else {
      // ★ 2026-07-18：Socket 未連線（背景/剛斷線）時走 HTTP 備援，
      //   確保發起方仍能收到拒接、雙端同步關閉來電 UI。
      debugPrint('⚠️ [Signaling] sendCallBusy: Socket 未連線，改走 HTTP declineCall');
      if (effectiveRoom != null) {
        ApiService.declineCall(
          roomId: effectiveRoom,
          senderId: targetSocketId,
          callId: effectiveCallId,
        );
      }
    }
  }

  void sendCancelCall(String room, {String role = 'family'}) {
    socket!.emit('cancel-call', {'room': room, 'role': role, 'callId': _currentCallId});
    if (_currentCallId != null && _currentCallId!.isNotEmpty) {
      _invalidCallIds.add(_currentCallId!);
    }
    _currentCallId = null;
  }

  /// ★ 2026-07-27 第十三輪：與 [sendCallRequest] 對齊。
  ///   原本只送 room + targetId，缺 role/callId/callerUserId/senderName，造成：
  ///     1. 後端只能靠 rooms_manager 反查發起者角色，查不到就回發 call-busy 給自己；
  ///     2. 發起端 _currentCallId 為 null → hangUp() 的 end-call 不帶 callId →
  ///        後端 call_registry 查無此通話 → 雙端同步終止不完整。
  void sendEmergencyCall(String room, {String? targetId, String? callId, String role = 'family'}) {
    final String effectiveCallId = callId ?? const Uuid().v4();
    _currentCallId = effectiveCallId;
    final int issuedAt = DateTime.now().millisecondsSinceEpoch;
    socket!.emit('emergency-call', {
      'room': room,
      'role': role,
      'callId': effectiveCallId,
      'issuedAt': issuedAt.toString(),
      'expiresAt': (issuedAt + kCallValidityMs).toString(),
      if (targetId != null) 'targetId': targetId,
      'callerUserId': _userId,
      if (_deviceName != null) 'senderName': _deviceName,
    });
  }

  void sendDeleteDevice(String room, String targetId) {
    if (socket != null && socket!.connected) {
      socket!.emit('delete-device', {'room': room, 'targetId': targetId});
    }
  }

  Future<void> _acceptCall(Map<String, dynamic> data, {required bool useLocalStream}) async {
    // ★ issue 4：接聽新來電前，先徹底關閉既有連線，確保一般通話房與緊急通話房不會並存
    if (peerConnection != null) {
      await peerConnection!.close();
      peerConnection = null;
    }
    _candidateQueue.clear();
    await _createPeerConnection(useLocalStream: useLocalStream);

    // ★ Fix: 緊急通話強制啟用本機視訊軌道
    if (data['isEmergency'] == true && localStream != null) {
      debugPrint("🚨 [Signaling] Emergency call: enabling local video tracks before answer");
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = true;
      }
    }

    try {
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
      await _processCandidateQueue();
      var answer = await peerConnection?.createAnswer(_constraints);
      await peerConnection?.setLocalDescription(answer!);

      // ★ 確保發送 answer 時正確指定發起者的 socketId 作為 targetId
      final targetSocketId = data['senderId'] ?? _peerSocketId;
      debugPrint("📤 [Signaling] Emitting answer to $targetSocketId (Call initiated by them)");

      // ★ 2026-08-11 第二十二輪（需求 7）：與 createOffer 同理，**先送 answer 再套編碼參數**。
      //   `_applyVideoEncodingParams()` 的原生 setParameters 會延後 answer 抵達對端的時間，
      //   而它與 SDP 內容無關。⚠️ 不要再把它移回 emit 之前。
      socket!.emit('answer', {
        'room': _currentRoomId,
        'targetId': targetSocketId,
        'type': 'answer',
        'sdp': answer!.sdp,
        'senderId': socket!.id
      });
      await _applyVideoEncodingParams();
    } catch (e) {
      debugPrint("❌ Accept Error: $e");
    }
  }

  Future<void> _processCandidateQueue() async {
    for (var candidate in _candidateQueue) {
      await peerConnection?.addCandidate(candidate);
    }
    _candidateQueue.clear();
  }

  // ★ 根據 elder_id 生成動態的 TURN 憑證
  Map<String, dynamic> _generateDynamicTURNConfig() {
    String turnUsername = _turnUser;

    // 如果有 elder_id，根據 elder_id 生成隔離用的使用者名稱（僅供除錯輸出）
    if (_elderId != null && _elderId!.isNotEmpty) {
      // ★ 使用 elder_id 作為 TURN 用戶名的後綴，實現通訊隔離
      // 格式: uban_elder_{elder_id}
      turnUsername = '${_turnUser}_elder_$_elderId';

      debugPrint("🔐 [TURN] 生成 elder_id 隔離的 TURN 憑證:");
      debugPrint("   elder_id: $_elderId");
      debugPrint("   username: $turnUsername");
      debugPrint("   server: $_turnServer");
    } else {
      debugPrint("⚠️ [TURN] 未找到 elder_id，使用預設 TURN 憑證");
    }

    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {
          // ★ 2026-08-05 第十七輪：Coturn 實際只有靜態帳號 uban（README.md:338-343，
          //   lt-cred-mech + user=uban:115207）。原本只送 `uban_elder_<id>` 會被回 401，
          //   拿不到任何 relay 候選；同網域靠 srflx 還能通，跨網域對稱 NAT 就必然
          //   「SDP 談成、ICE 配不出 pair」→ 有通話計時卻零影音。靜態帳號必須放第一組。
          'urls': ['turn:$_turnServer', 'turn:$_turnServer?transport=tcp'],
          'username': _turnUser,
          'credential': _turnPass,
        },
        // 若日後 Coturn 真的開了 per-elder 帳號，這組會被一併嘗試，不影響上面那組。
        if (_elderId != null && _elderId!.isNotEmpty)
          {
            'urls': ['turn:$_turnServer', 'turn:$_turnServer?transport=tcp'],
            'username': '${_turnUser}_elder_$_elderId',
            'credential': _turnPass,
          },
      ],
      // ★ 2026-08-04 第 3 項：縮短連線建立時間。以下四項都不改變媒體路徑，
      //   只影響 ICE 協商的效率，與雙軌設計（信令走 Tailscale、媒體走 Coturn）無關。
      //   iceCandidatePoolSize：PeerConnection 一建立就預先蒐集候選位址，
      //     不必等到 setLocalDescription 之後才開始，這是縮短等待最有效的一項。
      //   bundlePolicy max-bundle：音訊與視訊共用同一條傳輸通道，
      //     ICE 檢查從兩組降為一組。
      //   rtcpMuxPolicy require：RTP 與 RTCP 共用同一個埠，候選數量減半。
      //   sdpSemantics unified-plan：與本檔使用 addTrack（第 920 行）的寫法一致，
      //     明確指定以免不同平台預設值不同。
      //   ★ 2026-08-11 第二十二輪（需求 7）：iceCandidatePoolSize 2→4。
      //     池子越大，PeerConnection 建立當下就預先向 STUN/TURN 要到越多候選，
      //     `createOffer` 時可直接寫進 SDP，少一輪「trickle → 對端 addCandidate」往返。
      //     4 是保守值（對應 srflx/relay × UDP/TCP 四種組合），再大只是多打 TURN 沒有效益。
      //     `iceServers` 一個字都不要動（靜態帳號 uban 必須排第一組，見上方 G39 註解）。
      'iceCandidatePoolSize': 4,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    };
  }

  Future<void> _createPeerConnection({required bool useLocalStream}) async {
    // ★ 使用基於 elder_id 的動態 TURN 配置
    final config = _generateDynamicTURNConfig();
    debugPrint("📍 [WebRTC] Creating PeerConnection with config: $config");
    peerConnection = await createPeerConnection(config);
    
    var iceGatheringCount = 0;

    // ★ 2026-08-05 第十七輪：onConnectionState 改為真正回報連線狀態，不只 debugPrint。
    //   不做 ICE restart（已查證，不要自行加回去）：restart offer 會送進對端的
    //   socket!.on('offer')（來電流程），沒有 callId → isKnownAcceptedCall 為 false →
    //   shouldAnswer = false → offer 被靜默丟棄，純粹是死碼；而若 onIncomingCall
    //   當下有註冊，還會在通話中彈出第二個來電提示。要做對必須在後端
    //   services/socket_app.py 新增獨立的 renegotiate 轉發事件——那是全專案風險最高的
    //   檔案，收益（B-1 修好後 Failed 應極罕見）遠低於回歸風險。本輪只做「據實回報」。
    peerConnection!.onConnectionState = (state) {
      debugPrint("🔌 [Signaling] Connection State: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        debugPrint("✅ [Signaling] P2P Connection Established!");
        onPeerConnected?.call();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint("❌ [Signaling] P2P Connection Failed!");
        onPeerConnectionFailed?.call('無法建立影音連線（雙方網路環境不支援），請改用行動網路或其他 Wi-Fi 再試');
      }
      // Disconnected / Closed 不處理：Disconnected 常會自行恢復，
      // 誤判會把正常通話砍掉；真的救不回來時瀏覽器/原生層會轉成 Failed。
    };

    peerConnection!.onIceConnectionState = (state) {
      debugPrint("🧊 [Signaling] ICE Connection State: $state");
      // ★ 2026-08-05 第十七輪（硬化）：不要把「已連通」單押在 onConnectionState 上。
      //   flutter_webrtc 在部分 Android 原生層 onConnectionState 回報並不完整，一旦它沒
      //   觸發，正常通話會完全不計時——那比修復前更糟。故 ICE 進入 Connected/Completed
      //   時同樣視為已連通，兩條原生回呼取聯集。
      //   兩端的 onPeerConnected 實作都是冪等的（video_call_screen.dart 與
      //   elder_screen.dart 的 _startCallTimer() 都以 _callTimer?.cancel() 開頭，
      //   setState 也只是把旗標設為 true），重複觸發無副作用。
      //   ⚠️ 只擴大「連通」這個良性訊號，**絕對不要**把 RTCIceConnectionStateFailed 接到
      //   onPeerConnectionFailed——那條路徑會直接拆掉通話，而 ICE 層的 Failed 有機會自行
      //   恢復，接上去等於製造「通話中途無故被掛斷」的新回歸。失敗判定維持只由
      //   onConnectionState 的 Failed 分支與媒體看門狗負責。
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onPeerConnected?.call();
      }
    };

    peerConnection!.onIceCandidate = (candidate) {
      iceGatheringCount++;
      final candidateStr = candidate.candidate ?? 'NULL';
      final displayStr = candidateStr.length > 25 ? candidateStr.substring(0, 25) : candidateStr;
      debugPrint("🧊 ICE Candidate #$iceGatheringCount: $displayStr...");
      
      if (socket != null) {
        var payload = {
          'room': _currentRoomId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'senderId': socket!.id
        };
        // ★ 必須指定 targetId，確保 Candidate 精準轉發給對端
        if (_peerSocketId != null) {
          payload['targetId'] = _peerSocketId!;
          socket!.emit('candidate', payload);
        } else {
          debugPrint("⚠️ [Signaling] Missing targetId for ICE Candidate #$iceGatheringCount - falling back to room broadcast");
          socket!.emit('candidate', payload);
        }
      } else {
        debugPrint("⚠️ [Signaling] Socket not connected, cannot emit ICE candidate");
      }
    };
    
    peerConnection!.onTrack = (event) {
      debugPrint("🛤️ [Signaling] Received Remote Track: kind=${event.track.kind}, enabled=${event.track.enabled}");
      // ★ 2026-08-05 第十七輪：只有真的收到 remote track 才啟動媒體看門狗——
      //   startMonitoring() 的 recvonly 端本來就不會有 remote track，
      //   以此為前提就不可能誤殺監控連線（詳見 _startMediaWatchdog 說明）。
      _startMediaWatchdog();
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        debugPrint("✅ [Signaling] Adding remote stream with ${event.streams.length} stream(s)");
        onAddRemoteStream!(event.streams[0]);
      } else {
        debugPrint("⚠️ [Signaling] Remote track received but no onAddRemoteStream callback or streams empty");
      }
    };

    if (useLocalStream && localStream != null) {
      final tracks = localStream!.getTracks();
      debugPrint("📍 [Signaling] Adding ${tracks.length} local tracks to PeerConnection:");
      for (var i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        debugPrint("  ├─ Track #$i: kind=${track.kind}, enabled=${track.enabled}");
        peerConnection?.addTrack(track, localStream!);
      }
      if (tracks.isEmpty) {
        debugPrint("⚠️ [Signaling] No local tracks found! Check media permissions.");
      }
    } else if (useLocalStream) {
      debugPrint("⚠️ [Signaling] useLocalStream=true but localStream is null");
    } else {
      debugPrint("📍 [Signaling] useLocalStream=false, not adding local tracks (receive-only mode)");
    }
  }

  /// ★ 2026-08-05 第十七輪：媒體看門狗。`onTrack` 只代表 SDP 談成，收到 remote track
  /// 後 12 秒檢查一次 inbound-rtp 的 bytesReceived 總和，仍為 0 就代表雖然「看似連線」
  /// 卻完全沒有任何影音位元組在流動，據實回報（onPeerConnectionFailed）而不是讓 UI
  /// 停在假裝已連線的畫面。只由 onTrack 呼叫，不掛在 onConnectionState 的 Connected
  /// 分支——startMonitoring() 建立的是 recvonly 監控連線，那一端本來就不會收到任何
  /// remote track、也永遠不會有 inbound-rtp，若掛在 Connected 上會誤殺監控連線。
  void _startMediaWatchdog() {
    _mediaWatchdogTimer?.cancel();
    _mediaWatchdogTimer = Timer(const Duration(seconds: 12), () async {
      try {
        final pc = peerConnection;
        if (pc == null) return;
        final reports = await pc.getStats();
        double bytesReceived = 0;
        for (final report in reports) {
          if (report.type == 'inbound-rtp') {
            final value = report.values['bytesReceived'];
            if (value is num) {
              bytesReceived += value.toDouble();
            }
          }
        }
        if (bytesReceived > 0) {
          debugPrint('✅ [Signaling] 媒體看門狗：已收到 $bytesReceived bytes，連線正常');
        } else {
          debugPrint('❌ [Signaling] 媒體看門狗：12 秒內 inbound-rtp bytesReceived 仍為 0');
          onPeerConnectionFailed?.call('影音無法傳輸，請確認雙方網路環境後重新撥打');
        }
      } catch (e) {
        // 看門狗本身絕不可讓通話掛掉，任何例外都只記錄。
        debugPrint('⚠️ [Signaling] 媒體看門狗檢查失敗（不影響通話）: $e');
      }
    });
  }

  /// ★ 2026-08-04 第 3 項：拉高視訊送出端的位元率與幀率上限。
  ///   擷取端已要求 1280x720@30，但 WebRTC 送出端預設可能把位元率壓得很低而導致畫面糊。
  ///   必須在 setLocalDescription / setRemoteDescription 之後呼叫——
  ///   協商完成前 sender.parameters.encodings 可能是空的，此時直接跳過即可，
  ///   絕不可強行塞入 encoding（在部分 Android 裝置會拋例外並中斷通話）。
  Future<void> _applyVideoEncodingParams() async {
    try {
      final pc = peerConnection;
      if (pc == null) return;
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind != 'video') continue;
        final params = sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) {
          debugPrint('ℹ️ [Signaling] 視訊 encodings 尚未就緒，略過編碼參數設定');
          continue;
        }
        // ★ 2026-08-11 第二十二輪（需求 7：盡量拉到 1080p / 60fps）。
        //   修改前：maxBitrate = 2500000（2.5 Mbps）、maxFramerate = 30。
        //   1080p60 的合理上限約 4 Mbps；這只是**上限**，WebRTC 的擁塞控制（GCC）
        //   仍會依實測頻寬自動降到能跑的位元率，網路差時不會因此塞爆。
        //   若日後要還原，把下面兩行改回 2500000 / 30 即可，其餘邏輯不必動。
        encodings.first.maxBitrate = 4000000; // 4 Mbps，1080p60 的合理上限
        encodings.first.maxFramerate = 60;
        await sender.setParameters(params);
        debugPrint('🎥 [Signaling] 已套用視訊編碼參數: maxBitrate=4Mbps, maxFramerate=60');
      }
    } catch (e) {
      // 設定失敗絕不可影響通話本身，僅記錄。
      debugPrint('⚠️ [Signaling] 套用視訊編碼參數失敗（不影響通話）: $e');
    }
  }

  Future<void> createOffer({String? targetId, bool isEmergency = false, bool useLocalStream = true}) async {
    // ⭐ 防止重複調用 createOffer
    if (_isCreatingOffer) {
      debugPrint("⚠️ [Signaling] createOffer already in progress, skipping");
      return;
    }
    
    try {
      _isCreatingOffer = true;
      // ★ 先關閉舊連線，避免通訊通道疊加
      if (peerConnection != null) {
        await peerConnection!.close();
        peerConnection = null;
      }
      _candidateQueue.clear();
      debugPrint("🚀 [Signaling] Creating WebRTC Offer... (useLocalStream: $useLocalStream)");
      _peerSocketId = targetId;
      await _createPeerConnection(useLocalStream: useLocalStream);
      
      // ⏳ 等待 DTLS 材料生成（優化連線速度：50ms）
      await Future.delayed(const Duration(milliseconds: 50));
      
      // 建立 Offer 時帶入 constraints，確保雙向或單向通訊
      final constraints = useLocalStream 
          ? _constraints 
          : {'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}};
      
      RTCSessionDescription offer = await peerConnection!.createOffer(constraints);
      await peerConnection!.setLocalDescription(offer);

      // ★ 2026-08-11 第二十二輪（需求 7：縮短接通等待）：**先送 offer、再套編碼參數**。
      //   原順序是 `setLocalDescription` → `await _applyVideoEncodingParams()` → `emit`，
      //   而 `_applyVideoEncodingParams()` 會 `await pc.getSenders()` 再逐一
      //   `await sender.setParameters(params)`——這些都是跨 platform channel 的原生呼叫，
      //   在中低階 Android 上量測到數百毫秒，等於**白白延後對端開始協商的時間**。
      //   編碼參數只影響「送出去的畫質」，與 SDP 內容無關（它改的是 sender 的
      //   encoding 參數，不是 local description），所以移到 emit 之後語意完全等價。
      //   ⚠️ 不要再把它移回 emit 之前。
      debugPrint("📤 [Signaling] Emitting offer to $targetId");
      socket!.emit('offer', {
          'room': _currentRoomId,
          'targetId': targetId,
          'senderId': socket!.id,
          'type': 'offer',
          'sdp': offer.sdp,
          'isEmergency': isEmergency
      });
      await _applyVideoEncodingParams();
    } catch (e) {
      debugPrint("❌ [Signaling] createOffer failed: $e");
      rethrow;
    } finally {
      _isCreatingOffer = false;
    }
  }

  Future<void> startMonitoring(String targetId) async {
    // ★ issue 4：開始監看前，先關閉既有連線，確保監控房與通話房不會並存
    if (peerConnection != null) {
      await peerConnection!.close();
      peerConnection = null;
    }
    _candidateQueue.clear();
    _peerSocketId = targetId;
    await _createPeerConnection(useLocalStream: false);
    await peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    socket!.emit('offer', {
      'targetId': targetId,
      'room': _currentRoomId,
      'type': 'offer',
      'sdp': offer.sdp,
      'isEmergency': true, 
    });
  }

  Future<void> openUserMedia(RTCVideoRenderer localVideo, {bool videoEnabled = true}) async {
    // ★ Task 3：提高畫質與幀率 constraint
    // ★ 2026-08-11 第二十二輪（需求 7）：ideal 由 1280x720@30 提高到 **1920x1080@60**。
    //   **min 值刻意維持 640x480@24 不變**——`mandatory` 的 min 在 Android 是硬性條件，
    //   若跟著拉高，攝影機不支援 1080p60 的機型會直接 getUserMedia 失敗（等於無法通話）。
    //   ideal 只是「希望值」，拿不到就退到裝置支援的最接近解析度，安全。
    //   若要還原：把 idealWidth/idealHeight/idealFrameRate 改回 1280/720/30。
    final Map<String, dynamic> videoConstraints = videoEnabled
        ? {
            'video': {
              'mandatory': {
                'minWidth': '640',
                'idealWidth': '1920',
                'minHeight': '480',
                'idealHeight': '1080',
                'minFrameRate': '24',
                'idealFrameRate': '60',
              },
              'facingMode': 'user',
              'optional': [],
            },
            'audio': true,
          }
        : {'video': false, 'audio': true};

    // ★ 2026-08-11 第二十二輪（需求 8：從監視機跳回長輩端後通話全滅）：
    //   取新的媒體前**必須先釋放舊的**。原本這裡直接 getUserMedia，舊的 `localStream`
    //   既沒 stop() 也沒 dispose()，於是每經歷一次「進監控 → 退出 → 一般通話」，
    //   相機／麥克風就多被一個孤兒 stream 占住。Android 的相機是獨占資源，
    //   累積到某個數量後 getUserMedia 會卡住不返回（不是丟例外，try/catch 攔不到），
    //   接聽流程停在這一行 → 按了「接聽」沒反應、不跳轉，背景累積無回應的原生呼叫
    //   最終被系統判定為 ANR（「停止或等待」對話框）。
    //   ⚠️ 這是本輪的核心修復之一，不要為了「省一次相機重啟」把它拿掉。
    if (localStream != null) {
      debugPrint("♻️ [Signaling] openUserMedia：偵測到既有 localStream，先釋放再重新取得");
      stopMedia();
    }

    var stream = await navigator.mediaDevices.getUserMedia(videoConstraints);
    localVideo.srcObject = stream;
    localStream = stream;
    if (onLocalStream != null) onLocalStream!(stream);
  }

  void clearSession() {
    stopMedia();
    _closePeerConnection();
    _currentCallId = null;
    _isCreatingOffer = false; // ⭐ 重置 createOffer flag
    // ★ 2026-08-05 第十七輪：媒體看門狗屬於單次通話狀態，一併清除。
    _mediaWatchdogTimer?.cancel();
    _mediaWatchdogTimer = null;

    // 僅清除與「單次通話連線」相關的介面回調
    onAddRemoteStream = null;
    onLocalStream = null;
    onCallAcceptedByRemote = null;
    onCallBusy = null;
    onCallEnded = null;
    
    debugPrint("🧹 [Signaling] Session cleared. Persistent listeners (CallRequest, etc.) remain active.");
  }

  void hangUp({bool disconnectSocket = false, bool disposeLocalStream = true}) {
    debugPrint("📢 [Signaling] Hanging up (disconnectSocket: $disconnectSocket, disposeLocalStream: $disposeLocalStream, callId: $_currentCallId)...");
    // ★ 2026-08-10 第二十輪（需求 8：某一方掛斷後另一端仍留在通話房間）：
    //   原條件是 `socket != null && _currentRoomId != null`，只要 `_currentRoomId`
    //   為 null 就**完全不送 end-call**，對端於是永遠停在通話畫面。
    //   `_currentRoomId` 只在 `join()` 成功後才寫入，但有數條路徑會在沒有它的
    //   情況下掛斷：
    //     a. 接聽方走 CallKit 冷啟動鏈，`clearSession()` 之後才進房，中途掛斷；
    //     b. 家屬端在 `_goHomeAfterCall()` 之後又被 watchdog 補呼叫一次 hangUp；
    //     c. join 失敗（join-failed）後掛斷 —— 此時房間沒進去但通話 registry 已存在。
    //   後端 `on_end_call` 對 `room=None` 是安全的：它會改用 call_registry 的
    //   caller_sid / target_sids / accepter_sid 湊出對端（room 只是額外的 fallback），
    //   所以只要還有 `targetId` 或 `callId` 其中之一就值得送。
    if (socket != null &&
        (_currentRoomId != null || _peerSocketId != null || _currentCallId != null)) {
      socket!.emit('end-call', {'room': _currentRoomId, 'targetId': _peerSocketId, 'callId': _currentCallId});
    }
    if (_currentCallId != null && _currentCallId!.isNotEmpty) {
      _invalidCallIds.add(_currentCallId!);
    }
    _currentCallId = null;
    _isCreatingOffer = false; // ⭐ 重置 createOffer flag
    // ★ 2026-08-05 第十七輪：媒體看門狗屬於單次通話狀態，一併清除。
    _mediaWatchdogTimer?.cancel();
    _mediaWatchdogTimer = null;

    _closePeerConnection();

    if (disposeLocalStream) {
      stopMedia();
    }

    if (disconnectSocket) {
      forceDisconnect();
    }
  }

  Future<void> _closePeerConnection() async {
    // ★ 2026-08-05 第十七輪：PeerConnection 即將關閉，媒體看門狗不再需要，避免關閉後
    //   仍觸發 12 秒後的 getStats() 檢查。
    _mediaWatchdogTimer?.cancel();
    _mediaWatchdogTimer = null;
    if (peerConnection != null) {
      // ★ 在關閉之前確保所有 track 都被移除和停止
      for (var sender in await peerConnection!.getSenders()) {
        await peerConnection!.removeTrack(sender);
      }
      await peerConnection!.close();
      peerConnection = null;
    }
    _peerSocketId = null;
  }

  void stopMedia() {
    // ★ 確保媒體資源徹底釋放
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        track.stop();
      }
      localStream?.dispose();
      localStream = null;
      debugPrint("✅ [Signaling] Local media stream stopped and disposed");
    }
  }

  /// ★ 2026-08-11 第二十二輪（需求 8）：徹底拆除目前的 Socket 物件。
  ///
  /// 順序刻意是 **`clearListeners()` → `dispose()`**：
  ///   - `clearListeners()` 先把本專案註冊的 handler 全部拔掉，之後 `disconnect()`
  ///     內部觸發的 `onclose('io client disconnect')` 就不會回打到 `onConnectionLost`
  ///     之類的畫面邏輯（否則退出監控時會誤跳「連線中斷」）。
  ///   - `dispose()`（socket_io_client 3.1.4）= `disconnect()` + `clearListeners()`，
  ///     其中 `disconnect()` 會 `destroy()` 遞減 Manager 的參考計數並關閉底層連線，
  ///     這才是真正把重連排程停掉、釋放 WebSocket 的一步。
  /// 兩步各自 try/catch：拆除失敗絕不可以讓呼叫端（登出、退出監控）中斷。
  ///
  /// **不要**把它改成只呼叫 `disconnect()`——那是修改前的行為，會留下孤兒 socket。
  void _disposeSocket(String reason) {
    final old = socket;
    socket = null; // 先斷開參考，避免拆除過程中有人又拿去 emit
    if (old == null) return;
    debugPrint("🧨 [Signaling] 拆除舊 socket（$reason）");
    try {
      old.clearListeners();
    } catch (e) {
      debugPrint("⚠️ [Signaling] clearListeners 失敗（續行）: $e");
    }
    try {
      old.dispose();
    } catch (e) {
      debugPrint("⚠️ [Signaling] socket.dispose 失敗（續行）: $e");
    }
  }

  /// 斷線的唯一入口（護欄：不要改用 `socket.disconnect()`，那會失去 FCM 接收能力）。
  ///
  /// ★ 2026-08-11 第二十二輪（需求 8）：修改前是
  /// `if (socket != null && socket!.connected) { socket?.disconnect(); socket = null; }`，
  /// 有兩個致命點：
  ///   1. **socket 已斷線時整段是 no-op**——`socket` 欄位仍指著那個舊物件，
  ///      它的 handler 與重連排程都還活著（監控機退出時正是這個狀態）。
  ///   2. 即使進得去，也只 `disconnect()` 不 `dispose()`，listener 全部留著。
  /// 現在一律走 `_disposeSocket()`，並清掉隨連線一起失效的房間／對端狀態。
  void forceDisconnect() {
    _disposeSocket('forceDisconnect()');
    // 這兩個是「本次連線」的狀態，socket 沒了它們就沒有意義；留著會讓下一次
    // hangUp() 對著早已不存在的房間／對端 emit end-call。
    _currentRoomId = null;
    _peerSocketId = null;
  }

  bool _isExpiredCallPayload(dynamic payload) {
    if (payload is! Map) return false;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? expiresAt = int.tryParse('${payload['expiresAt'] ?? ''}');
    if (expiresAt != null && now > expiresAt) return true;
    final int? issuedAt = int.tryParse('${payload['issuedAt'] ?? ''}');
    if (issuedAt != null && (now - issuedAt) > kCallValidityMs) return true;
    return false;
  }

  // ========================================
  // 新增：子女端遠端陪伴功能
  // ========================================

  /// 發送主動關心訊息（Heartbeat）給長輩端
  /// 
  /// [elderId] 長輩的資料庫 ID
  /// [message] 關心訊息內容
  /// [audioPath] 可選：自定義語音檔案路徑
  /// [playSound] 是否播放提示音
  /// [musicUrl] 可選：播放背景音樂 URL
  /// [actionButtons] 可選：互動按鈕列表
  Future<void> sendHeartbeat(
    int elderId,
    String message, {
    String? audioPath,
    bool playSound = true,
    String? musicUrl,
    List<Map<String, String>>? actionButtons,
  }) async {
    if (socket == null || !socket!.connected) {
      debugPrint("❌ [Signaling] Socket not connected, cannot send heartbeat");
      return;
    }

    final payload = {
      'elderId': elderId,
      'message': message,
      'audioPath': audioPath,
      'playSound': playSound,
      'musicUrl': musicUrl,
      'actionButtons': actionButtons,
      'timestamp': DateTime.now().toIso8601String(),
    };

    socket!.emit('send-heartbeat', payload);
    debugPrint("💓 [Signaling] Sent heartbeat to elder $elderId: $message");
  }

  /// 推送內容給長輩端
  /// 
  /// [elderId] 長輩的資料庫 ID
  /// [type] 內容類型: 'youtube_video', 'article', 'music', 'image'
  /// [data] 內容數據
  Future<void> pushContent(
    int elderId, {
    required String type,
    required Map<String, dynamic> data,
  }) async {
    if (socket == null || !socket!.connected) {
      debugPrint("❌ [Signaling] Socket not connected, cannot push content");
      return;
    }

    final payload = {
      'elderId': elderId,
      'type': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    socket!.emit('push-content', payload);
    debugPrint("📤 [Signaling] Pushed content to elder $elderId: $type");
  }

  /// 監聽長輩端的對話更新
  /// 
  /// [callback] 接收對話歷史的回調函數
  void listenToElderChat(int elderId, Function(List<Map<String, dynamic>>) callback) {
    if (socket == null) {
      debugPrint("❌ [Signaling] Socket not initialized");
      return;
    }

    socket!.on('elder-chat-update-$elderId', (data) {
      debugPrint("💬 [Signaling] Received elder chat update");
      if (data is List) {
        final messages = data.map((m) => m as Map<String, dynamic>).toList();
        callback(messages);
      }
    });

    // 請求當前對話歷史
    socket!.emit('request-elder-chat', {'elderId': elderId});
  }

  /// 監聽用藥確認回應
  /// 
  /// [elderId] 長輩的資料庫 ID
  /// [callback] 接收確認數據的回調函數
  void listenToMedicationConfirmation(int elderId, Function(Map<String, dynamic>) callback) {
    if (socket == null) {
      debugPrint("❌ [Signaling] Socket not initialized");
      return;
    }

    socket!.on('medication-confirmed-$elderId', (data) {
      debugPrint("💊 [Signaling] Medication confirmed");
      if (data is Map<String, dynamic>) {
        callback(data);
      }
    });
  }
}
