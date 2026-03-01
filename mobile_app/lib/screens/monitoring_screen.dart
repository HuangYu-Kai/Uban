// lib/screens/monitoring_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart';

class MonitoringScreen extends StatefulWidget {
  final String roomId;
  final String targetSocketId;

  const MonitoringScreen({Key? key, required this.roomId, required this.targetSocketId}) : super(key: key);

  @override
  _MonitoringScreenState createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initMonitoring();
  }

  Future<void> _initMonitoring() async {
    await _remoteRenderer.initialize();
    _signaling.onAddRemoteStream = ((stream) {
      if (mounted) setState(() { _remoteRenderer.srcObject = stream; _isConnected = true; });
    });

    // 解決黑屏
    _signaling.onCallEnded = () {
      if (mounted) {
        Navigator.pop(context);
      }
    };

    _signaling.connect(widget.roomId, 'family', deviceName: 'Monitor');
    _signaling.enableSpeakerphone(true);

    Future.delayed(const Duration(milliseconds: 500), () {
      _signaling.startMonitoring(widget.targetSocketId);
    });
  }

  @override
  void dispose() {
    _signaling.hangUp();
    _signaling.enableSpeakerphone(false);
    _remoteRenderer.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("監控中"), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isConnected = false);
              _initMonitoring();
            },
            tooltip: '重新連線',
          )
        ],
      ),
      body: Center(
        child: _isConnected
            ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}