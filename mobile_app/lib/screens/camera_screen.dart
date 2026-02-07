// 路徑: mobile_app/lib/screens/camera_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // 防休眠
import '../services/signaling.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isReconnecting = false; // 防止重複重連

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    // 1. 啟用防休眠 (重要)
    WakelockPlus.enable();

    // 2. 設定收到對方畫面時的行為
    signaling.onAddRemoteStream = ((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
      // ★★★ 強制接收端開啟擴音 (解決聽不到聲音) ★★★
      Helper.setSpeakerphoneOn(true);
    });

    // 3. 設定斷線自動重連邏輯
    signaling.onConnectionLost = () {
      if (mounted && !_isReconnecting) {
        print("偵測到斷線，3秒後嘗試自動重連...");
        _handleAutoReconnect();
      }
    };

    _initCameraAndConnect();
  }

  Future<void> _initCameraAndConnect() async {
    // 請求權限
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      signaling.connect();
      await signaling.openUserMedia(_localRenderer, _remoteRenderer);

      // ★★★ 強制發送端開啟擴音 ★★★
      Helper.setSpeakerphoneOn(true);
      setState(() {});
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("請允許相機與麥克風權限以使用此功能")));
      }
    }
  }

  Future<void> _handleAutoReconnect() async {
    if (_isReconnecting) return;
    setState(() => _isReconnecting = true);

    // 等待一下再重連
    await Future.delayed(const Duration(seconds: 3));

    try {
      await signaling.createOffer();
      Helper.setSpeakerphoneOn(true); // 重連後再次確認擴音
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("已觸發自動重連...")));
      }
    } catch (e) {
      print("重連失敗: $e");
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  @override
  void dispose() {
    // 離開頁面時關閉防休眠
    WakelockPlus.disable();
    signaling.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("即時監控")),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 本地畫面 (鏡面)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                    ),
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
                // 遠端畫面
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red),
                    ),
                    child: RTCVideoView(_remoteRenderer),
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
                  onPressed: () async {
                    await signaling.createOffer();
                    Helper.setSpeakerphoneOn(true);
                  },
                  icon: const Icon(Icons.videocam),
                  label: const Text("開始監控"),
                ),
                const SizedBox(width: 20),
                // 手動重連按鈕 (備用)
                ElevatedButton(
                  onPressed: _handleAutoReconnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                  ),
                  child: const Text("重連"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
