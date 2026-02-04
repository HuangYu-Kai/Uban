import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart'; // 確保引用您指定的 signaling.dart

class CameraScreen extends StatefulWidget {
  final String roomId;
  const CameraScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    // 1. 設定回調
    _signaling.onAddRemoteStream = ((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });

    _signaling.onLocalStream = ((stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    });

    // 2. 開啟鏡頭與連線
    _startCall();
  }

  void _startCall() async {
    await _signaling.openUserMedia(_localRenderer);
    
    // ★★★ 修正點：補上第二個參數 role ★★★
    // 這裡給一個通用的角色名稱，例如 'user' 或 'video-peer'
    _signaling.connect(widget.roomId, 'video-peer'); 
  }

  @override
  void dispose() {
    _signaling.dispose(); // 記得釋放資源
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('雙向視訊 - 房號 ${widget.roomId}')),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 本地畫面
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
                // 遠端畫面
                Expanded(
                  child: Container(
                    color: Colors.black87,
                    child: RTCVideoView(_remoteRenderer),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(200, 50)),
              onPressed: () {
                // ★★★ 呼叫雙向通話邏輯 ★★★
                _signaling.createOffer();
              },
              child: const Text("撥打視訊 (Call)", style: TextStyle(fontSize: 20, color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }
}