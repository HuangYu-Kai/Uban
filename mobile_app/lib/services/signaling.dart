// lib/services/signaling.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:uuid/uuid.dart';

typedef void StreamStateCallback(MediaStream stream);
typedef Future<bool> IncomingCallCallback(String callerId, String callType);
typedef void VoidCallback();
typedef void ErrorCallback(String message);
typedef void CallRequestCallback(String roomId, String senderId);
typedef void CallAcceptedCallback(String accepterId);

class Signaling {
  final String _socketUrl = 'http://192.168.0.4:5000'; // 請確認 IP
  static const platform = MethodChannel('com.example.app/bring_to_front');

  IO.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  
  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onLocalStream;
  Function(List<dynamic>)? onElderDevicesUpdate;
  IncomingCallCallback? onIncomingCall;
  VoidCallback? onCallEnded;
  ErrorCallback? onJoinFailed;
  CallRequestCallback? onCallRequest;
  CallAcceptedCallback? onCallAcceptedByRemote;
  CallAcceptedCallback? onCallBusy; // Reusing CallAcceptedCallback for simplicity (just needs a string ID)

  String? _currentRoomId;
  String? _peerSocketId;
  List<RTCIceCandidate> _candidateQueue = [];
  
  // 保留這個修復：暫存房間，解決 "只能收到第一個響鈴" 的問題
  final List<String> _pendingRooms = [];

  final Map<String, dynamic> _configuration = {
    'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
  };

  void connect(String roomId, String role, {String deviceName = 'Unknown', String deviceMode = 'comm'}) {
    _currentRoomId = roomId;

    socket = IO.io(_socketUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .enableForceNew() // 強制每次 connect 都建立全新 Socket，不共用快取
      .build()
    );

    socket!.connect();

    socket!.onConnect((_) {
      print('✅ Socket 連線成功');
      _emitJoin(roomId, role, deviceName, deviceMode);
      
      // 加入暫存的房間
      for (var pendingRoom in _pendingRooms) {
        _emitJoin(pendingRoom, 'family', 'Dashboard_Listener', 'listener');
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
      if (onCallRequest != null) onCallRequest!(data['room'], data['senderId']);
    });

    // 對方接聽監聽
    socket!.on('call-accept', (data) {
      _peerSocketId = data['accepterId'];  // ★ 記錄接聽方的 Socket ID，以便之後單播 end-call
      if (onCallAcceptedByRemote != null) onCallAcceptedByRemote!(data['accepterId']);
    });

    // 忙線監聽
    socket!.on('call-busy', (data) {
      if (onCallBusy != null) onCallBusy!(data['targetId']);
    });

    socket!.on('offer', (data) async {
      print('📩 收到 Offer');
      _peerSocketId = data['senderId'];
      _candidateQueue.clear();

      bool isEmergency = data['isEmergency'] == true;
      if (isEmergency) {
        try { await platform.invokeMethod('bringToFront'); } catch (e) {}
        try { 
          VolumeController.instance.showSystemUI = false;
          VolumeController.instance.setVolume(1.0); 
        } catch (e) {}
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
      try {
        var description = RTCSessionDescription(data['sdp'], data['type']);
        await peerConnection?.setRemoteDescription(description);
        await _processCandidateQueue();
      } catch (e) {
        print("❌ Answer Error: $e");
      }
    });

    socket!.on('candidate', (data) async {
      var candidate = RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
      if (peerConnection != null && await peerConnection?.getRemoteDescription() != null) {
        await peerConnection?.addCandidate(candidate);
      } else {
        _candidateQueue.add(candidate);
      }
    });

    socket!.on('end-call', (_) async {
      print("📴 收到掛斷訊號");
      await FlutterCallkitIncoming.endAllCalls();
      await _closePeerConnection();
      if (onCallEnded != null) onCallEnded!();
    });
  }

  Future<bool> _showCallkitIncoming(String callerName) async {
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

  void _emitJoin(String room, String role, String name, String mode) {
    socket!.emit('join', {'room': room, 'role': role, 'deviceName': name, 'deviceMode': mode});
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

  void requestCall() {
    socket!.emit('call-request', {'room': _currentRoomId});
  }


  void sendCallAccept(String targetSocketId) async {
    if (socket == null) return;
    
    // 如果還沒連線，最多等待 5 秒 (50 * 100ms)
    int retries = 50;
    while (!socket!.connected && retries > 0) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries--;
    }

    if (socket!.connected) {
      socket!.emit('call-accept', {'targetId': targetSocketId});
      print("✅ 成功發送 call-accept 給 $targetSocketId");
    } else {
      print("❌ 發送 call-accept 失敗：Socket 遲遲未連線");
    }
  }

  void sendCallBusy(String targetSocketId) {
    socket!.emit('call-busy', {'targetId': targetSocketId});
  }

  void hangUp({bool disconnectSocket = true, bool disposeLocalStream = true}) {
    if (socket != null) {
      // 絕對不可以只送 room，這會導致伺服器針對整個房間廣播 end-call，
      // 誤殺家屬端 Dashboard 的監聽 Socket！
      if (_peerSocketId != null) {
        socket!.emit('end-call', {
          'room': _currentRoomId,
          'targetId': _peerSocketId
        });
      }
      // ★ 延遲斷線：確保 end-call 訊息送達後再中斷 socket (僅限需要斷開的畫面)
      if (disconnectSocket) {
        Future.delayed(const Duration(milliseconds: 500), () {
          socket?.disconnect();
          socket = null;
        });
      }
    }
    _closePeerConnection();
    
    // ★ 是否釋放媒體串流 (ElderScreen 需要持續開啟攝影機所以帶 false)
    if (disposeLocalStream) {
      localStream?.getTracks().forEach((t) => t.stop());
      localStream?.dispose();
      localStream = null;
    }
    _peerSocketId = null;
  }

  Future<void> _closePeerConnection() async {
    if (peerConnection != null) {
      await peerConnection!.close();
      peerConnection = null;
    }
    _candidateQueue.clear();
  }

  Future<void> _acceptCall(Map<String, dynamic> data, {required bool useLocalStream}) async {
    if (peerConnection != null) await peerConnection!.close();
    await _createPeerConnection(useLocalStream: useLocalStream);

    try {
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
      await _processCandidateQueue();
      var answer = await peerConnection?.createAnswer();
      await peerConnection?.setLocalDescription(answer!);
      socket!.emit('answer', {
        'room': _currentRoomId,
        'targetId': _peerSocketId,
        'type': 'answer',
        'sdp': answer!.sdp
      });
    } catch (e) {
      print("❌ Accept Error: $e");
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
    peerConnection!.onIceCandidate = (candidate) {
      if (socket != null) {
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
    _peerSocketId = targetId;
    await _createPeerConnection(useLocalStream: true);
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    
    var payload = {
      'room': _currentRoomId, 
      'type': 'offer',
      'sdp': offer.sdp,
      'isEmergency': isEmergency,
    };
    if (targetId != null) payload['targetId'] = targetId;
    socket!.emit('offer', payload);
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

  void dispose() {
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    peerConnection?.close();
    // 延遲中斷，確保如果剛呼叫了 hangUp，其發送的 end-call 不會被瞬間切斷
    if (socket != null && socket!.connected) {
      Future.delayed(const Duration(milliseconds: 600), () {
        socket?.disconnect();
        socket = null;
      });
    }
  }
}