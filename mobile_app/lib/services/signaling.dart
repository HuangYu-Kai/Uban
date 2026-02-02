// 路徑: mobile_app/lib/services/signaling.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  // ★★★ 請修改這裡：換成您電腦的區網 IP ★★★
  final String _socketUrl = 'http://192.168.0.4:5000'; 

  Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
    ]
  };

  IO.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  StreamStateCallback? onAddRemoteStream;
  
  // 新增：斷線通知回呼
  VoidCallback? onConnectionLost;

  void connect() {
    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    socket!.onConnect((_) => print('已連線到信令伺服器'));

    socket!.on('offer', (data) async {
      await _createPeerConnection();
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
      
      var answer = await peerConnection?.createAnswer();
      await peerConnection?.setLocalDescription(answer!); // 修正 Null Safety
      
      socket!.emit('answer', {'type': 'answer', 'sdp': answer!.sdp});
    });

    socket!.on('answer', (data) async {
      var description = RTCSessionDescription(data['sdp'], data['type']);
      await peerConnection?.setRemoteDescription(description);
    });

    socket!.on('candidate', (data) async {
      var candidate = RTCIceCandidate(
        data['candidate'], data['sdpMid'], data['sdpMLineIndex']
      );
      await peerConnection?.addCandidate(candidate);
    });
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection(configuration);

    // ★★★ 監聽連線狀態：如果斷線，通知 UI 重連 ★★★
    peerConnection!.onIceConnectionState = (state) {
      print("WebRTC 連線狀態: $state");
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (onConnectionLost != null) onConnectionLost!();
      }
    };

    peerConnection!.onIceCandidate = (candidate) {
      if (socket != null) {
        socket!.emit('candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
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

  Future<void> openUserMedia(RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    var stream = await navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
    localVideo.srcObject = stream;
    localStream = stream;
  }

  Future<void> createOffer() async {
    await _createPeerConnection();
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    socket!.emit('offer', {'type': 'offer', 'sdp': offer.sdp});
  }

  void dispose() {
    localStream?.dispose();
    peerConnection?.close();
    socket?.disconnect();
  }
}