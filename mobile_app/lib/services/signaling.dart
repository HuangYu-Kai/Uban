import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

typedef StreamStateCallback = void Function(MediaStream stream);

class Signaling {
  // ★ 請確認 IP 正確
  final String _socketUrl = 'http://192.168.31.209:5000';

  socket_io.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;

  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onLocalStream;
  VoidCallback? onConnectionLost;
  Function(List<dynamic>)? onUserListUpdate;

  String? _currentRoomId;
  String? _peerSocketId; // 用於鎖定通話對象

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  // 連線: 必須帶入 role
  void connect(String roomId, String role) {
    _currentRoomId = roomId;

    socket = socket_io.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    socket!.connect();

    socket!.onConnect((_) {
      debugPrint('✅ 已連線。加入房間: $roomId, 角色: $role');
      socket!.emit('join', {'room': roomId, 'role': role});
    });

    socket!.on('user-list', (data) {
      if (onUserListUpdate != null) {
        onUserListUpdate!(data as List<dynamic>);
      }
    });

    // 處理 Offer
    socket!.on('offer', (data) async {
      debugPrint('📩 收到 Offer');
      _peerSocketId = data['senderId']; // 記錄來源

      await _createPeerConnection();

      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);

      var answer = await peerConnection?.createAnswer();
      await peerConnection?.setLocalDescription(answer!);

      // 回傳 Answer (優先回給 senderId，沒有則廣播)
      socket!.emit('answer', {
        'room': _currentRoomId,
        'targetId': _peerSocketId,
        'type': 'answer',
        'sdp': answer!.sdp,
      });
    });

    socket!.on('answer', (data) async {
      debugPrint('📩 收到 Answer');
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
    });

    socket!.on('candidate', (data) async {
      var candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      await peerConnection?.addCandidate(candidate);
    });
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection(_configuration);

    peerConnection!.onIceCandidate = (candidate) {
      if (socket != null) {
        // 發送 Candidate (如果有鎖定對象則傳給對象，否則傳給房間)
        socket!.emit('candidate', {
          'room': _currentRoomId,
          'targetId': _peerSocketId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        onAddRemoteStream!(event.streams[0]);
      }
    };

    if (localStream != null) {
      localStream!.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });
    }
  }

  // ★★★ 修復重點：加回 createOffer (給雙向視訊用) ★★★
  // 這會觸發 app.py 的廣播模式
  Future<void> createOffer() async {
    debugPrint('📞 發起雙向通話 Offer (廣播)...');
    await _createPeerConnection();

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    // 不帶 targetId，只帶 room
    socket!.emit('offer', {
      'room': _currentRoomId,
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  // ★★★ 監控專用：指定 Socket ID ★★★
  Future<void> startMonitoring(String targetSocketId) async {
    debugPrint('🎥 對 $targetSocketId 發起監控...');
    _peerSocketId = targetSocketId;

    await _createPeerConnection();

    // 監控端只接收 (RecvOnly)
    await peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    // 帶上 targetId
    socket!.emit('offer', {
      'targetId': targetSocketId,
      'room': _currentRoomId,
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  Future<void> openUserMedia(RTCVideoRenderer localVideo) async {
    var stream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });
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
