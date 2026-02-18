// lib/screens/elder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/signaling.dart';

class ElderScreen extends StatefulWidget {
  final String roomId;
  final bool isCCTVMode;
  final String deviceName;

  const ElderScreen({Key? key, required this.roomId, this.isCCTVMode = false, required this.deviceName}) : super(key: key);

  @override
  _ElderScreenState createState() => _ElderScreenState();
}

class _ElderScreenState extends State<ElderScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _status = "等待連線...";
  bool _isInCall = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await [Permission.camera, Permission.microphone].request();
    _initElderMode();
  }

  Future<void> _initElderMode() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onAddRemoteStream = ((stream) {
      if(mounted) setState(() { _remoteRenderer.srcObject = stream; _status = "通話中"; _isInCall = true; });
    });
    _signaling.onLocalStream = ((stream) => setState(() => _localRenderer.srcObject = stream));

    // 處理加入失敗 (名稱重複)
    _signaling.onJoinFailed = (errorMessage) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('連線失敗'),
            content: Text(errorMessage),
            actions: [
              ElevatedButton(
                onPressed: () { 
                  Navigator.pop(context); // 關閉 Dialog
                  Navigator.pop(context); // 退出頁面
                }, 
                child: const Text('確定')
              )
            ],
          ),
        );
      }
    };

    // ★★★ 關鍵：家屬接聽後，才發送 Offer (解決影像連線問題) ★★★
    _signaling.onCallAcceptedByRemote = (accepterId) {
      print("✅ 家屬($accepterId) 已接聽，開始定向發送 Offer...");
      if (mounted) setState(() { _status = "連線建立中..."; _isInCall = true; });
      
      // 傳入 accepterId，確保點對點連線
      _signaling.createOffer(targetId: accepterId, isEmergency: false);
    };

    await _signaling.openUserMedia(_localRenderer);
    
    _signaling.connect(
      widget.roomId, 
      'elder', 
      deviceName: widget.deviceName,
      deviceMode: widget.isCCTVMode ? 'cctv' : 'comm'
    );

    // 掛斷後重置狀態
    _signaling.onCallEnded = () {
      if (mounted) {
        setState(() { 
          _remoteRenderer.srcObject = null; 
          _status = "通話結束"; 
          _isInCall = false; 
        });
      }
    };

    _signaling.onIncomingCall = (callerId, callType) async {
      bool isEmergency = callType == 'emergency';
      if (widget.isCCTVMode || isEmergency) {
        setState(() => _isInCall = true);
        return true; 
      }
      bool accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('家人來電'),
          content: const Text('是否接聽？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('拒絕')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('接聽')),
          ],
        ),
      ) ?? false;
      if (accept) setState(() => _isInCall = true);
      return accept;
    };
  }

  // 主動呼叫 (先響鈴)
  void _makeCall() {
    setState(() { _status = "正在呼叫家人..."; _isInCall = true; });
    _signaling.requestCall();
  }

  void _hangUp() {
    _signaling.hangUp();
    setState(() { _remoteRenderer.srcObject = null; _status = "等待連線..."; _isInCall = false; });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceName), backgroundColor: widget.isCCTVMode ? Colors.redAccent : Colors.orange),
      body: Stack(
        children: [
          if (widget.isCCTVMode)
            Positioned.fill(child: Container(color: Colors.black, child: RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)))
          else
            Stack(children: [
              Positioned.fill(child: Container(color: Colors.black87, child: _remoteRenderer.srcObject != null ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover) : Center(child: Text(_status, style: const TextStyle(color: Colors.white, fontSize: 20))))),
              Positioned(right: 20, top: 20, width: 100, height: 150, child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.white)), child: RTCVideoView(_localRenderer, mirror: true))),
            ]),
          
          if (widget.isCCTVMode)
             const Positioned(bottom: 30, left: 0, right: 0, child: Center(child: Chip(label: Text("CCTV 運作中"), backgroundColor: Colors.red))),

          if (!widget.isCCTVMode)
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isInCall)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.call, size: 32),
                      label: const Text("呼叫家人", style: TextStyle(fontSize: 20)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                      onPressed: _makeCall,
                    ),
                  if (_isInCall)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.call_end, size: 32),
                      label: const Text("掛斷", style: TextStyle(fontSize: 20)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                      onPressed: _hangUp,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}