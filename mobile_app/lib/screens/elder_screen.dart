import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart';

class ElderScreen extends StatefulWidget {
  final String roomId;
  const ElderScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  _ElderScreenState createState() => _ElderScreenState();
}

class _ElderScreenState extends State<ElderScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    
    // 預覽自己的畫面
    _signaling.onLocalStream = ((stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    });

    _initElderMode();
  }

  void _initElderMode() async {
    await _signaling.openUserMedia(_localRenderer);
    // ★ 關鍵：宣告自己是 'elder'
    _signaling.connect(widget.roomId, 'elder');
  }

  @override
  void dispose() {
    _signaling.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('長輩端 - ${widget.roomId}'), backgroundColor: Colors.orange),
      body: Stack(
        children: [
          Positioned.fill(child: RTCVideoView(_localRenderer, mirror: true)),
          const Center(
            child: Text("等待家屬連線...", 
              style: TextStyle(color: Colors.white, backgroundColor: Colors.black54, fontSize: 20)),
          )
        ],
      ),
    );
  }
}