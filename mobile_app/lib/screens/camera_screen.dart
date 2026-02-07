import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/signaling.dart';

class CameraScreen extends StatefulWidget {
  final String roomId;
  const CameraScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    // 1. 啟用防休眠
    WakelockPlus.enable();

    // 2. 設定回調
    _signaling.onAddRemoteStream = ((stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
        Helper.setSpeakerphoneOn(true);
      }
    });

    _signaling.onLocalStream = ((stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    });

    // 斷線重連邏輯
    _signaling.onConnectionLost = () {
      if (mounted && !_isReconnecting) {
        _handleAutoReconnect();
      }
    };

    _initCameraAndConnect();
  }

  Future<void> _initCameraAndConnect() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      _signaling.connect(widget.roomId, 'video-peer');
      await _signaling.openUserMedia(_localRenderer);
      Helper.setSpeakerphoneOn(true);
      if (mounted) setState(() {});
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
    await Future.delayed(const Duration(seconds: 3));

    try {
      await _signaling.createOffer();
      Helper.setSpeakerphoneOn(true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("已觸發自動重連...")));
      }
    } catch (e) {
      debugPrint("重連失敗: $e");
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _signaling.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // 使用深色背景營造專業感
      appBar: AppBar(
        title: Text('即時監控 - ${widget.roomId}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(_remoteRenderer),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await _signaling.createOffer();
                    Helper.setSpeakerphoneOn(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.videocam),
                  label: const Text("開始監控"),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  onPressed: _handleAutoReconnect,
                  icon: const Icon(Icons.refresh),
                  tooltip: '重連',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
