// 路徑: lib/services/signaling.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  // ★★★ 請確認這裡的 IP 是電腦的 IPv4 (例如 192.168.0.4) ★★★
  final String _socketUrl = 'http://192.168.0.4:5000';

  IO.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  
  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onLocalStream;
  VoidCallback? onConnectionLost;
  Function(List<dynamic>)? onUserListUpdate;

  String? _currentRoomId;
  String? _peerSocketId; 

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  // 連線: 必須帶入 role
  void connect(String roomId, String role) {
    _currentRoomId = roomId;
    // ... (中間 socket設定省略，保持原樣) ...
    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true
    });
    socket!.connect();
    
    socket!.onConnect((_) {
      print('✅ 已連線。加入房間: $roomId, 角色: $role');
      socket!.emit('join', {'room': roomId, 'role': role});
    });
    
    // ... (省略中間監聽邏輯，請參考之前的完整代碼) ...
    // 為了節省篇幅，請確保這裡有 on('offer'), on('answer'), on('candidate') 的邏輯
    // 如果需要完整版請告訴我
  }
  
  // ★★★ 關鍵：一定要有這個方法，CameraScreen 才能呼叫 ★★★
  Future<void> createOffer() async {
    print('📞 發起雙向通話 Offer (廣播)...');
    // 確保這裡有初始化 PeerConnection
    if (peerConnection == null) await _createPeerConnection();

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    
    // 不帶 targetId，只帶 room
    socket!.emit('offer', {
      'room': _currentRoomId, 
      'type': 'offer',
      'sdp': offer.sdp
    });
  }

  // ★★★ 監控用：指定 Socket ID ★★★
  Future<void> startMonitoring(String targetSocketId) async {
    // ... (同之前的邏輯) ...
    _peerSocketId = targetSocketId;
    if (peerConnection == null) await _createPeerConnection();
    
    await peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    
    socket!.emit('offer', {
      'targetId': targetSocketId,
      'room': _currentRoomId,
      'type': 'offer',
      'sdp': offer.sdp
    });
  }

  // 內部輔助方法 (務必保留)
  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection(_configuration);
    // ... (candidate 與 track 監聽邏輯) ...
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