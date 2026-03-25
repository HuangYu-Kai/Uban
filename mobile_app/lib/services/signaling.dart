// lib/services/signaling.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef IncomingCallCallback = Future<bool> Function(String callerId, String callType);
typedef VoidCallback = void Function();
typedef ErrorCallback = void Function(String message);
typedef CallRequestCallback = void Function(String roomId, String senderId, String? callId);
typedef CallAcceptedCallback = void Function(String accepterId, String? callId);

class Signaling {
  static const String _serverIp = String.fromEnvironment('SERVER_IP', defaultValue: 'localhost-0.tail5abf5e.ts.net');
  
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

  String? _currentRoomId;
  String? _peerSocketId;
  int? _userId; // 新增：儲存當前使用者的資料庫 ID
  final List<RTCIceCandidate> _candidateQueue = [];
  final List<String> _pendingRooms = [];

  final Map<String, dynamic> _configuration = {
    'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
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

  void connect(String roomId, String role, {int? userId, String deviceName = 'Unknown', String deviceMode = 'comm', String? fcmToken}) {
    _currentRoomId = roomId;
    _userId = userId;

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
      _asyncJoin(_currentRoomId!, 'family', 'Reconnected_Device', 'comm'); 
    }
  }

  Future<void> _asyncJoin(String roomId, String role, String deviceName, String deviceMode, {int? userId, String? fcmToken}) async {
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
      socket?.disconnect();
    });

    socket!.on('elder-devices-list', (data) => onElderDevicesUpdate?.call(data as List<dynamic>));
    
    // 響鈴監聽
    socket!.on('call-request', (data) {
      if (onCallRequest != null) onCallRequest!(data['room'], data['senderId'], data['callId']);
    });

    // 取消呼叫監聽
    socket!.on('cancel-call', (data) {
      if (onCancelCall != null) onCancelCall!(data['room'], data['senderId'], data['callId']);
    });

    // 緊急呼叫監聽
    socket!.on('emergency-call', (data) {
      if (onEmergencyCall != null) onEmergencyCall!(data['room'], data['senderId'], data['callId']);
    });

    // 對方接聽監聽
    socket!.on('call-accept', (data) {
      debugPrint("📞 [Signaling] Received call-accept (SenderId: ${data['accepterId']}, CallId: ${data['callId']})");
      _peerSocketId = data['accepterId'];  
      if (onCallAcceptedByRemote != null) onCallAcceptedByRemote!(data['accepterId'], data['callId']);
    });

    // 忙線監聽
    socket!.on('call-busy', (data) {
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

    socket!.on('end-call', (_) async {
      debugPrint("📴 收到掛斷訊號");
      if (!kIsWeb) {
        await FlutterCallkitIncoming.endAllCalls();
      }
      await _closePeerConnection();
      if (onCallEnded != null) onCallEnded!();
    });
  }

  Future<bool> _showCallkitIncoming(String callerName) async {
    if (kIsWeb) return false;
    final uuid = const Uuid().v4();
    final params = CallKitParams(
      id: uuid,
      nameCaller: callerName,
      appName: 'Uban',
      avatar: 'https://i.pravatar.cc/100',
      handle: '長輩呼叫',
      type: 0,
      duration: 30000,
      textAccept: '接聽',
      textDecline: '拒絕',
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
        backgroundColor: '#0955fa',
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',
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

  void _emitJoin(String room, String role, String name, String mode, {int? userId, String? fcmToken}) async {
    debugPrint("📢 [Signaling] Emitting join: $room ($role) as $name (UID: $userId)");
    
    // ★ Bug: Web 版不支援 FirebaseMessaging.instance.getToken() 若未正確設定 VAPID
    // 且 Web 版通訊多在前景，暫不需要 FCM 推播。
    if (kIsWeb) {
      socket!.emit('join', {
        'room': room, 
        'role': role, 
        'deviceName': name, 
        'deviceMode': mode,
        'userId': userId,
        'fcmToken': fcmToken
      });
      return;
    }

    // Non-blocking FCM token retrieval (Mobile Only)
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) debugPrint("🔔 [Signaling] FCM Token retrieved: ${token.substring(0, 8)}...");
      socket!.emit('join', {
        'room': room, 
        'role': role, 
        'deviceName': name, 
        'deviceMode': mode,
        'userId': userId,
        'fcmToken': token ?? fcmToken
      });
    }).catchError((e) {
      debugPrint("⚠️ [Signaling] FCM Token failed: $e, joining without token.");
      socket!.emit('join', {
        'room': room, 
        'role': role, 
        'deviceName': name, 
        'deviceMode': mode,
        'userId': userId,
        'fcmToken': fcmToken
      });
    });
  }

  void joinRoom(String roomId) {
    if (socket != null && socket!.connected) {
      _emitJoin(roomId, 'family', 'Dashboard_Listener', 'listener');
    } else {
      _pendingRooms.add(roomId);
    }
  }

  void enableSpeakerphone(bool enable) {
    if (kIsWeb) return;
    Helper.setSpeakerphoneOn(enable);
  }

  void sendCallRequest(String room, {String role = 'family', String? callId}) {
    socket!.emit('call-request', {
      'room': room, 
      'role': role, 
      'callId': callId,
      'callerUserId': _userId // 新增：主動發送發起者的資料庫 ID
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

  void sendCancelCall(String room) {
    socket!.emit('cancel-call', {'room': room});
  }

  void sendEmergencyCall(String room) {
    socket!.emit('emergency-call', {'room': room});
  }

  void sendDeleteDevice(String room, String targetId) {
    if (socket != null && socket!.connected) {
      socket!.emit('delete-device', {'room': room, 'targetId': targetId});
    }
  }

  Future<void> _acceptCall(Map<String, dynamic> data, {required bool useLocalStream}) async {
    if (peerConnection != null) await peerConnection!.close();
    await _createPeerConnection(useLocalStream: useLocalStream);

    try {
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
      await _processCandidateQueue();
      var answer = await peerConnection?.createAnswer(_constraints);
      await peerConnection?.setLocalDescription(answer!);
      socket!.emit('answer', {
        'room': _currentRoomId,
        'targetId': _peerSocketId,
        'type': 'answer',
        'sdp': answer!.sdp,
        'senderId': socket!.id // 告知對方我是誰
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

  Future<void> _createPeerConnection({required bool useLocalStream}) async {
    peerConnection = await createPeerConnection(_configuration);
    
    peerConnection!.onIceConnectionState = (state) {
      debugPrint("❄️ ICE Connection State: $state");
    };

    peerConnection!.onConnectionState = (state) {
      debugPrint("🔌 [Signaling] Connection State: $state");
    };
    
    peerConnection!.onIceConnectionState = (state) {
      debugPrint("🧊 [Signaling] ICE Connection State: $state");
    };

    peerConnection!.onIceCandidate = (candidate) {
      if (socket != null) {
        debugPrint("🧊 Generated ICE Candidate: ${candidate.candidate?.substring(0, 15)}...");
        var payload = {
          'room': _currentRoomId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        };
        if (_peerSocketId != null) payload['targetId'] = _peerSocketId!;
        socket!.emit('candidate', payload);
      }
    };
    
    peerConnection!.onTrack = (event) {
      debugPrint("🛤️ Received Remote Track: ${event.track.kind}");
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        onAddRemoteStream!(event.streams[0]);
      }
    };
    if (useLocalStream && localStream != null) {
      localStream!.getTracks().forEach((track) => peerConnection?.addTrack(track, localStream!));
    }
  }

  Future<void> createOffer({String? targetId, bool isEmergency = false}) async {
    // ★ 先關閉舊連線，避免通訊通道疊加
    if (peerConnection != null) {
      await peerConnection!.close();
      peerConnection = null;
    }
    _candidateQueue.clear();
    debugPrint("🚀 [Signaling] Creating WebRTC Offer...");
    _peerSocketId = targetId;
    await _createPeerConnection(useLocalStream: true);
    
    // 建立 Offer 時帶入 constraints，確保雙向通訊
    RTCSessionDescription offer = await peerConnection!.createOffer(_constraints);
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
  }

  Future<void> startMonitoring(String targetId) async {
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

  Future<void> openUserMedia(RTCVideoRenderer localVideo) async {
    var stream = await navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
    localVideo.srcObject = stream;
    localStream = stream;
    if (onLocalStream != null) onLocalStream!(stream);
  }

  void clearSession() {
    stopMedia();
    _closePeerConnection();
    
    // 僅清除與「單次通話連線」相關的介面回調
    onAddRemoteStream = null;
    onLocalStream = null;
    onCallAcceptedByRemote = null;
    onCallBusy = null;
    onCallEnded = null;
    
    debugPrint("🧹 [Signaling] Session cleared. Persistent listeners (CallRequest, etc.) remain active.");
  }

  void hangUp({bool disconnectSocket = false, bool disposeLocalStream = true}) {
    debugPrint("📢 [Signaling] Hanging up (disconnectSocket: $disconnectSocket, disposeLocalStream: $disposeLocalStream)...");
    if (socket != null && _currentRoomId != null) {
      socket!.emit('end-call', {'room': _currentRoomId, 'targetId': _peerSocketId});
    }
    
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
      await peerConnection!.close();
      peerConnection = null;
    }
    _peerSocketId = null;
  }

  void stopMedia() {
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;
  }

  void forceDisconnect() {
    if (socket != null && socket!.connected) {
      socket?.disconnect();
      socket = null;
    }
  }
}