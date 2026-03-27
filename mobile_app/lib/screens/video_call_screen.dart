// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (!kIsWeb && Platform.isAndroid) {
      Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication);
    }
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onAddRemoteStream = ((stream) {
      debugPrint("📺 [VideoCallScreen] Remote stream added! Tracks: ${stream.getTracks().length}");
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _inCall = true;
        });
      }
    });
    _signaling.onLocalStream = ((stream) {
      debugPrint("🤳 [VideoCallScreen] Local stream set! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [VideoCallScreen] Incoming Call/Offer detected while in UI!");
      return true;
    };

    _signaling.onCallEnded = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("通話已結束")),
        );
        Navigator.pop(context);
      }
    };

    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      debugPrint("✅ [VideoCallScreen] Target Accepted ($accepterId), sending Offer...");
      _signaling.createOffer(targetId: accepterId, isEmergency: widget.isEmergency);
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
      // 如果是主動呼叫，先發送 Request 給對方點擊接聽
      // 等待 onCallAcceptedByRemote 被觸發後才會執行 createOffer
      _signaling.sendCallRequest(widget.roomId, role: 'family');
    }
  }

  @override
  void dispose() {
    _signaling.hangUp();
    _signaling.clearSession();
    
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    if (!kIsWeb && Platform.isAndroid) {
      Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration(
        manageAudioFocus: false,
        androidAudioMode: AndroidAudioMode.normal,
        androidAudioFocusMode: AndroidAudioFocusMode.gain,
        androidAudioStreamType: AndroidAudioStreamType.music,
        androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
        androidAudioAttributesContentType: AndroidAudioAttributesContentType.unknown,
      ));
      Helper.clearAndroidCommunicationDevice();
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 遠端影像 (全螢幕沉浸式)
          Positioned.fill(
            child: _inCall
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1A1A1A), Colors.black],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white70),
                          const SizedBox(height: 24),
                          Text(
                            "正在連線中...",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 18,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // 2. 頂部自定義資訊欄 (代替 AppBar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield, color: Colors.greenAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        widget.isEmergency ? "緊急通話" : "視訊通話",
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white70),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // 3. 本地預覽 (精緻 PIP)
          Positioned(
            right: 20,
            bottom: 120,
            width: 110,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          ),

          // 4. 底部控制列 (Glassmorphism 磨砂質感)
          Positioned(
            bottom: 40,
            left: 30,
            right: 30,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: Icons.mic,
                        onPressed: () {},
                        color: Colors.white,
                      ),
                      _buildControlButton(
                        icon: Icons.call_end,
                        onPressed: () => Navigator.pop(context),
                        isEndCall: true,
                      ),
                      _buildControlButton(
                        icon: Icons.videocam,
                        onPressed: () {},
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white,
    bool isEndCall = false,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isEndCall ? Colors.redAccent : Colors.white12,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 28),
        onPressed: onPressed,
      ),
    );
  }
}