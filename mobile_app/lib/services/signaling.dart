// lib/services/signaling.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

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

    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true
    });

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
      if (onCallAcceptedByRemote != null) onCallAcceptedByRemote!(data['accepterId']);
    });

    socket!.on('offer', (data) async {
      print('📩 收到 Offer');
      _peerSocketId = data['senderId'];
      _candidateQueue.clear();

      bool isEmergency = data['isEmergency'] == true;
      if (isEmergency) {
        try { await platform.invokeMethod('bringToFront'); } catch (e) {}
      }

      bool shouldAnswer = false;
      if (onIncomingCall != null) {
        shouldAnswer = await onIncomingCall!(_peerSocketId!, isEmergency ? 'emergency' : 'normal');
      } else {
        shouldAnswer = true; 
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
      await _closePeerConnection();
      if (onCallEnded != null) onCallEnded!();
    });
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

  void sendCallAccept(String targetSocketId) {
    socket!.emit('call-accept', {'targetId': targetSocketId});
  }

  void hangUp() {
    if (socket != null) {
      var payload = {'room': _currentRoomId};
      if (_peerSocketId != null) payload['targetId'] = _peerSocketId!;
      socket!.emit('end-call', payload);
    }
    _closePeerConnection();
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
    localStream?.dispose();
    peerConnection?.close();
    socket?.disconnect();
  }
}