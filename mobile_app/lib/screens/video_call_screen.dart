// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/signaling.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String? targetSocketId;
  final bool isIncomingCall;
  final bool autoStart;
  final bool isEmergency;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    this.targetSocketId,
    this.isIncomingCall = false,
    this.autoStart = false,
    this.isEmergency = false,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
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
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _inCall = true;
        });
      }
    });
    _signaling.onLocalStream = ((stream) {
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onIncomingCall = (callerId, callType) async => true;

    _signaling.onCallEnded = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("通話已結束")),
        );
        Navigator.pop(context);
      }
    };

    await _signaling.openUserMedia(_localRenderer);

    // ★ 自動讀取使用者 ID 與名稱
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt('caregiver_id');
    final String userName = prefs.getString('caregiver_name') ?? '家屬端';

    _signaling.connect(
      widget.roomId, 
      'family', 
      userId: userId, 
      deviceName: userName
    );

    if (widget.isIncomingCall) {
      _signaling.sendCallAccept(widget.targetSocketId!);
    } else if (widget.autoStart) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _signaling.createOffer(targetId: widget.targetSocketId, isEmergency: widget.isEmergency);
        }
      });
    }
  }

  @override
  void dispose() {
    _signaling.hangUp();
    _signaling.onAddRemoteStream = null;
    _signaling.onCallEnded = null;
    _signaling.onIncomingCall = null;
    
    _localRenderer.dispose();
    _remoteRenderer.dispose();
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
                FloatingActionButton(
                  heroTag: "end",
                  backgroundColor: Colors.red,
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