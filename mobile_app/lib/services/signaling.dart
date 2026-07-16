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

typedef StreamStateCallback = void Function(MediaStream stream);
typedef IncomingCallCallback = Future<bool> Function(String callerId, String callType);
// NOTE: 不要重新定義 VoidCallback，Flutter 已內建
typedef ErrorCallback = void Function(String message);
typedef CallRequestCallback = void Function(String roomId, String senderId, String? callId, [String? senderName]);
typedef CallAcceptedCallback = void Function(String accepterId, String? callId);

class Signaling {
  static const String _serverIp = String.fromEnvironment('SERVER_IP', defaultValue: 'localhost-0.tail5abf5e.ts.net');
  static const String _turnServer = String.fromEnvironment('TURN_SERVER', defaultValue: '152.69.196.5:3478');
  static const String _turnUser = String.fromEnvironment('TURN_USER', defaultValue: 'uban');
  static const String _turnPass = String.fromEnvironment('TURN_PASS', defaultValue: '115207');
  
  static String get serverUrl => _serverIp.contains('ngrok') || _serverIp.contains('ts.net')
      ? 'https://$_serverIp' 
      : 'http://$_serverIp:8000';

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
  ErrorCallback? onJoinFailed;
  CallRequestCallback? onCallRequest;
  CallRequestCallback? onCancelCall;
  CallRequestCallback? onEmergencyCall;
  CallAcceptedCallback? onCallAcceptedByRemote;
  CallAcceptedCallback? onCallBusy; 
  VoidCallback? onConnectionLost; 
  Function(String message)? onHeartbeatMessage; // 新增：主動式心跳消息回傳
  Function(String text, String type)? onNewPondLeaf; // 新增：記憶落葉話題推播

  String? _currentRoomId;
  String? _peerSocketId;
  String? _currentCallId; // 追蹤當前通話 ID，確保 hangUp 時能傳給後端
  String? lastProcessedCallId; // ★ 問題4修復：記錄最後一個已處理的來電 ID，防止重複
  int lastProcessedCallTime = 0; // ★ 問題4修復：記錄最後一個已處理來電的時間戳，用於去重檢查
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
    'optional': [],
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
    socket!.onConnectError((err) => debugPrint('❌ Socket Connect Error: $err (Server: $serverUrl)'));
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
      if (onJoinFailed != null) onJoinFailed!(data['message']);
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
      if (onCallBusy != null) onCallBusy!(data['targetId'], data['callId']);
    });

    socket!.on('elder-devices-update', (devices) {
      debugPrint("📡 [Signaling] Received elder-devices-update (count: ${devices.length})");
      if (onElderDevicesUpdate != null) onElderDevicesUpdate!(devices);
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
        // If no UI handler (e.g. background), try CallKit for Family role.
        // But for Elder, they should auto-answer emergency.
        if (isEmergency) {
          shouldAnswer = true;
        } else {
          // 如果沒有註冊 onIncomingCall，代表 APP 在背景 或沒有打開 Dashboard
          shouldAnswer = await _showCallkitIncoming(data['room'] ?? 'Unknown');
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
      duration: 30000,
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

  void sendCallRequest(String room, {String role = 'family', String? callId, String? targetId}) {
    final String effectiveCallId = callId ?? const Uuid().v4();
    _currentCallId = effectiveCallId;
    final int issuedAt = DateTime.now().millisecondsSinceEpoch;
    socket!.emit('call-request', {
      'room': room, 
      'role': role, 
      'callId': effectiveCallId,
      'issuedAt': issuedAt.toString(),
      'expiresAt': (issuedAt + 15000).toString(),
      if (targetId != null) 'targetId': targetId,
      'callerUserId': _userId, // 新增：主動發送發起者的資料庫 ID
      if (_deviceName != null) 'senderName': _deviceName,
    });
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

  void sendCallBusy(String targetSocketId, {String? callId}) {
    if (socket != null && socket!.connected) {
      socket!.emit('call-busy', {'targetId': targetSocketId, 'callId': callId});
    }
  }

  void sendCancelCall(String room, {String role = 'family'}) {
    socket!.emit('cancel-call', {'room': room, 'role': role, 'callId': _currentCallId});
    if (_currentCallId != null && _currentCallId!.isNotEmpty) {
      _invalidCallIds.add(_currentCallId!);
    }
    _currentCallId = null;
  }

  void sendEmergencyCall(String room, {String? targetId}) {
    socket!.emit('emergency-call', {
      'room': room,
      if (targetId != null) 'targetId': targetId,
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
      
      socket!.emit('answer', {
        'room': _currentRoomId,
        'targetId': targetSocketId,
        'type': 'answer',
        'sdp': answer!.sdp,
        'senderId': socket!.id
      });
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

  // ★ 根据 elder_id 生成动态的 TURN 凭证
  Map<String, dynamic> _generateDynamicTURNConfig() {
    String turnUsername = _turnUser;
    String turnPassword = _turnPass;
    
    // 如果有 elder_id，根据 elder_id 生成隔离的凭证
    if (_elderId != null && _elderId!.isNotEmpty) {
      // ★ 使用 elder_id 作为 TURN 用户名的后缀，实现通讯隔离
      // 格式: uban_elder_{elder_id}
      turnUsername = '${_turnUser}_elder_$_elderId';
      
      // ★ 生成基于 elder_id 的密码
      // 这可以确保每个 elder 有独立的认证通道
      turnPassword = _turnPass; // 保持相同的密码，由服务器验证 elder_id
      
      debugPrint("🔐 [TURN] 生成 elder_id 隔离的 TURN 凭证:");
      debugPrint("   elder_id: $_elderId");
      debugPrint("   username: $turnUsername");
      debugPrint("   server: $_turnServer");
    } else {
      debugPrint("⚠️ [TURN] 未找到 elder_id，使用默认 TURN 凭证");
    }
    
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {
          'urls': [
            'turn:$_turnServer',
            'turn:$_turnServer?transport=tcp',
          ],
          'username': turnUsername,
          'credential': turnPassword,
        },
      ]
    };
  }

  Future<void> _createPeerConnection({required bool useLocalStream}) async {
    // ★ 使用基于 elder_id 的动态 TURN 配置
    final config = _generateDynamicTURNConfig();
    debugPrint("📍 [WebRTC] Creating PeerConnection with config: $config");
    peerConnection = await createPeerConnection(config);
    
    var iceGatheringCount = 0;
    peerConnection!.onIceConnectionState = (state) {
      debugPrint("❄️ ICE Connection State: $state");
    };

    peerConnection!.onConnectionState = (state) {
      debugPrint("🔌 [Signaling] Connection State: $state");
      if (state == 'connected') {
        debugPrint("✅ [Signaling] P2P Connection Established!");
      } else if (state == 'failed') {
        debugPrint("❌ [Signaling] P2P Connection Failed!");
      }
    };
    
    peerConnection!.onIceConnectionState = (state) {
      debugPrint("🧊 [Signaling] ICE Connection State: $state");
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
      
      // ⏳ 等待 DTLS 材料生成（CRITICAL: 防止 fingerprint 不匹配）
      // 增加到 1000ms 以確保 DTLS 證書完全初始化
      await Future.delayed(Duration(milliseconds: 1000));
      
      // 建立 Offer 時帶入 constraints，確保雙向或單向通訊
      final constraints = useLocalStream 
          ? _constraints 
          : {'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true}};
      
      RTCSessionDescription offer = await peerConnection!.createOffer(constraints);
      await peerConnection!.setLocalDescription(offer);
      
      debugPrint("📤 [Signaling] Emitting offer to $targetId");
      socket!.emit('offer', {
          'room': _currentRoomId,
          'targetId': targetId,
          'senderId': socket!.id,
          'type': 'offer',
          'sdp': offer.sdp,
          'isEmergency': isEmergency
      });
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
    var stream = await navigator.mediaDevices.getUserMedia({
      'video': videoEnabled,
      'audio': true,
    });
    localVideo.srcObject = stream;
    localStream = stream;
    if (onLocalStream != null) onLocalStream!(stream);
  }

  void clearSession() {
    stopMedia();
    _closePeerConnection();
    _currentCallId = null;
    _isCreatingOffer = false; // ⭐ 重置 createOffer flag
    
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
    if (socket != null && _currentRoomId != null) {
      socket!.emit('end-call', {'room': _currentRoomId, 'targetId': _peerSocketId, 'callId': _currentCallId});
    }
    if (_currentCallId != null && _currentCallId!.isNotEmpty) {
      _invalidCallIds.add(_currentCallId!);
    }
    _currentCallId = null;
    _isCreatingOffer = false; // ⭐ 重置 createOffer flag
    
    _closePeerConnection();
    
    if (disposeLocalStream) {
      stopMedia();
    }

    if (disconnectSocket) {
      forceDisconnect();
    }
  }

  Future<void> _closePeerConnection() async {
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

  void forceDisconnect() {
    if (socket != null && socket!.connected) {
      socket?.disconnect();
      socket = null;
    }
  }

  bool _isExpiredCallPayload(dynamic payload) {
    if (payload is! Map) return false;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? expiresAt = int.tryParse('${payload['expiresAt'] ?? ''}');
    if (expiresAt != null && now > expiresAt) return true;
    final int? issuedAt = int.tryParse('${payload['issuedAt'] ?? ''}');
    if (issuedAt != null && (now - issuedAt) > 15000) return true;
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
