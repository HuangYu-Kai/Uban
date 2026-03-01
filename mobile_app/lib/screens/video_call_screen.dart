// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String targetSocketId;
  final bool isIncomingCall;

  const VideoCallScreen({
    Key? key,
    required this.roomId,
    required this.targetSocketId,
    this.isIncomingCall = false,
  }) : super(key: key);

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // ★ 獨立的 Signaling 實例，不與 Dashboard 共用，避免狀態汙染
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onAddRemoteStream = ((stream) {
      if (mounted) setState(() { _remoteRenderer.srcObject = stream; _inCall = true; });
    });
    _signaling.onLocalStream = ((stream) {
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    // ★ 關鍵：在通話畫面中收到 offer 直接接聽，不觸發 CallKit 5 秒阻擋
    _signaling.onIncomingCall = (callerId, callType) async => true;

    // 對方掛斷 → 退出頁面
    _signaling.onCallEnded = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("對方已結束通話")),
        );
        Navigator.pop(context);
      }
    };

    await _signaling.openUserMedia(_localRenderer);
    // ★ 用自己的 socket 連線，role='family'，不干擾 Dashboard 的監聽 socket
    _signaling.connect(widget.roomId, 'family', deviceName: '家屬端');

    if (widget.isIncomingCall) {
      // 接聽模式：等 socket 連線後通知長輩發送 Offer
      _signaling.sendCallAccept(widget.targetSocketId);
    }
  }

  @override
  void dispose() {
    // ★ 通話頁面完整清除，包含 socket（此 socket 為本頁專屬）
    _signaling.hangUp();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("視訊通話")),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _inCall
                  ? RTCVideoView(_remoteRenderer)
                  : const Center(
                      child: Text("連線中...",
                          style: TextStyle(color: Colors.white))),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 160,
            width: 100,
            height: 150,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.white)),
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!widget.isIncomingCall) ...[
                  FloatingActionButton(
                    heroTag: "call",
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.call),
                    onPressed: () => _signaling.createOffer(
                        targetId: widget.targetSocketId, isEmergency: false),
                  ),
                  FloatingActionButton(
                    heroTag: "emer",
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.warning),
                    onPressed: () => _signaling.createOffer(
                        targetId: widget.targetSocketId, isEmergency: true),
                  ),
                ],
                FloatingActionButton(
                  heroTag: "end",
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.call_end),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}