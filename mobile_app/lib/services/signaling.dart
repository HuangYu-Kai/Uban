import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  // ★★★ 請確認 IP 正確 (電腦 IPv4) ★★★
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

  // ★★★ 新增：用來暫存還沒加入的 ICE Candidates ★★★
  List<RTCIceCandidate> _candidateQueue = [];

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  void connect(String roomId, String role) {
    _currentRoomId = roomId;

    socket = IO.io(_socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true
    });

    socket!.connect();

    socket!.onConnect((_) {
      print('✅ Socket 連線成功 (ID: ${socket!.id})');
      socket!.emit('join', {'room': roomId, 'role': role});
    });

    socket!.on('user-list', (data) {
      if (onUserListUpdate != null) {
        onUserListUpdate!(data as List<dynamic>);
      }
    });
    
    // --- 收到 Offer ---
    socket!.on('offer', (data) async {
      print('📩 收到 Offer');
      _peerSocketId = data['senderId'];
      
      // 確保 queue 清空
      _candidateQueue.clear();

      if (peerConnection == null) await _createPeerConnection();
      
      try {
        var description = RTCSessionDescription(data['sdp'], data['type']);
        await peerConnection?.setRemoteDescription(description);
        
        // ★★★ 關鍵：設定完 Remote 之後，立刻處理排隊中的 Candidates ★★★
        _processCandidateQueue();
        
        var answer = await peerConnection?.createAnswer();
        await peerConnection?.setLocalDescription(answer!);
        
        socket!.emit('answer', {
          'room': _currentRoomId,
          'targetId': _peerSocketId,
          'type': 'answer',
          'sdp': answer!.sdp
        });
      } catch (e) {
        print("❌ 處理 Offer 失敗: $e");
      }
    });

    // --- 收到 Answer ---
    socket!.on('answer', (data) async {
      print('📩 收到 Answer');
      try {
        var description = RTCSessionDescription(data['sdp'], data['type']);
        await peerConnection?.setRemoteDescription(description);
        
        // ★★★ 關鍵：設定完 Remote 之後，立刻處理排隊中的 Candidates ★★★
        _processCandidateQueue();
        
      } catch (e) {
        print("❌ 處理 Answer 失敗: $e");
      }
    });

    // --- 收到 Candidate ---
    socket!.on('candidate', (data) async {
      var candidate = RTCIceCandidate(
        data['candidate'], data['sdpMid'], data['sdpMLineIndex']
      );

      // ★★★ 關鍵修正：判斷是否已經可以加入 Candidate ★★★
      if (peerConnection != null && await peerConnection?.getRemoteDescription() != null) {
        // 如果遠端描述已經設定好，直接加入
        await peerConnection?.addCandidate(candidate);
      } else {
        // 如果還沒設定好，先排隊 (解決卡頓的關鍵)
        print("⏳ 排隊 Candidate...");
        _candidateQueue.add(candidate);
      }
    });
  }

  // ★★★ 輔助函式：處理排隊的 Candidates ★★★
  Future<void> _processCandidateQueue() async {
    for (var candidate in _candidateQueue) {
      print("🚀 補加入排隊的 Candidate");
      await peerConnection?.addCandidate(candidate);
    }
    _candidateQueue.clear();
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection(_configuration);

    // 監聽連線狀態 (除錯用)
    peerConnection!.onIceConnectionState = (state) {
      print("📡 ICE 連線狀態變更: $state");
    };

    peerConnection!.onIceCandidate = (candidate) {
      if (socket != null) {
        socket!.emit('candidate', {
          'room': _currentRoomId,
          'targetId': _peerSocketId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        });
      }
    };

    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && onAddRemoteStream != null) {
        print('📺 收到遠端影像流 (Track)');
        onAddRemoteStream!(event.streams[0]);
      }
    };

    if (localStream != null) {
      localStream!.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });
    }
  }

  // 雙向視訊 (廣播)
  Future<void> createOffer() async {
    print('📞 發起 Offer...');
    _candidateQueue.clear(); // 清空舊的 queue
    _peerSocketId = null; 
    if (peerConnection == null) await _createPeerConnection();

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    
    socket!.emit('offer', {
      'room': _currentRoomId, 
      'type': 'offer',
      'sdp': offer.sdp
    });
  }

  // 監控模式
  Future<void> startMonitoring(String targetSocketId) async {
    print('🎥 發起監控 Offer...');
    _candidateQueue.clear(); // 清空舊的 queue
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

  Future<void> openUserMedia(RTCVideoRenderer localVideo) async {
    var stream = await navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
    localVideo.srcObject = stream;
    localStream = stream;
    if (onLocalStream != null) onLocalStream!(stream);
  }

  void dispose() {
    localStream?.dispose();
    localStream = null;
    peerConnection?.close();
    peerConnection = null;
    socket?.disconnect();
    _candidateQueue.clear();
  }
}