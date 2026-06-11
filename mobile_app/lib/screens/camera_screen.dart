import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/signaling.dart';

class CameraScreen extends StatefulWidget {
  final String roomId;
  const CameraScreen({super.key, required this.roomId});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isReconnecting = false;
  bool _isConnecting = true;
  String? _targetMonitorId;

  @override
  void initState() {
    super.initState();
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

    _signaling.onLocalStream = null;

    // 斷線重連邏輯
    _signaling.onConnectionLost = () {
      if (mounted && !_isReconnecting) {
        _handleAutoReconnect();
      }
    };

    _signaling.onElderDevicesUpdate = (devices) async {
      if (!mounted) return;
      
      // 尋找作為監視器的設備 (video-peer)
      final monitors = devices.where((d) => d['deviceMode'] == 'monitor' || d['role'] == 'video-peer').toList();
      
      if (monitors.isNotEmpty) {
        // ★ issue 8：後端 elder-devices-update 回傳的 socket id 欄位是 'id'，並非 'socketId'
        _targetMonitorId = monitors.first['id'];
        debugPrint("📹 [CameraScreen] 找到監視設備: $_targetMonitorId");
        
        setState(() => _isConnecting = false);
        
        // 發送單向觀看請求 (不需要發送自己的影音)
        await _signaling.createOffer(targetId: _targetMonitorId, isEmergency: false, useLocalStream: false);
        Helper.setSpeakerphoneOn(true);
      } else {
        debugPrint("📹 [CameraScreen] 找不到監視設備");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("長輩端沒有開啟監視器模式的設備")));
          setState(() => _isConnecting = false);
        }
      }
    };

    _initCameraAndConnect();
  }

  Future<void> _initCameraAndConnect() async {
    // ★ 修復：讀取真正的 user_id（caregiver_id），用於後端驗證身份
    final prefs = await SharedPreferences.getInstance();
    final int? actualUserId = prefs.getInt('caregiver_id');
    
    // 單向觀看，不需要要求相機麥克風權限
    _signaling.connect(
      widget.roomId, 
      'family-monitor', 
      userId: actualUserId,  // ★ 修復：傳入真正的 user_id 供後端驗證
      deviceName: '家屬監控端'
    );
    
    // 等待連線成功後，要求更新設備列表
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _signaling.sendGetElderDevices(widget.roomId);
      }
    });
  }

  Future<void> _handleAutoReconnect() async {
    if (_isReconnecting) return;
    setState(() => _isReconnecting = true);
    await Future.delayed(const Duration(seconds: 3));

    try {
      if (_targetMonitorId != null) {
        await _signaling.createOffer(targetId: _targetMonitorId, isEmergency: false, useLocalStream: false);
      } else {
        _signaling.sendGetElderDevices(widget.roomId);
      }
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

  void dispose() {
    WakelockPlus.disable();
    _signaling.clearSession();
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
            child: _isConnecting 
              ? const Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blue),
                    SizedBox(height: 16),
                    Text('正在尋找長輩端的監視器...', style: TextStyle(color: Colors.white70)),
                  ],
                ))
              : Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.1),
                        blurRadius: 20,
                        spreadRadius: 5,
                      )
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    if (_targetMonitorId != null) {
                      await _signaling.createOffer(targetId: _targetMonitorId, isEmergency: false, useLocalStream: false);
                      Helper.setSpeakerphoneOn(true);
                    } else {
                      _signaling.sendGetElderDevices(widget.roomId);
                    }
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
                  icon: const Icon(Icons.refresh),
                  label: const Text("重新連線"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
