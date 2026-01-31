// 路徑: mobile_app/lib/screens/camera_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart'; // 注意引入路徑

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    signaling.onAddRemoteStream = ((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });

    // 自動連線 Socket
    signaling.connect();
    // 自動開啟鏡頭
    signaling.openUserMedia(_localRenderer, _remoteRenderer).then((_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    signaling.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("即時監控"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 本地畫面 (加上邊框以示區別)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.blue)),
                    child: Stack(
                      children: [
                        RTCVideoView(_localRenderer, mirror: true),
                        const Positioned(top: 10, left: 10, child: Text("Local", style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ),
                ),
                // 遠端畫面
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.red)),
                    child: Stack(
                      children: [
                        RTCVideoView(_remoteRenderer),
                        const Positioned(top: 10, left: 10, child: Text("Remote", style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _inCalling ? null : () async {
                    await signaling.createOffer();
                    setState(() {
                      _inCalling = true;
                    });
                  },
                  icon: const Icon(Icons.videocam),
                  label: const Text("開始監控 (發送 Offer)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}