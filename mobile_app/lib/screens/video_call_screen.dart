// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
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

  // ★ 通話控制狀態
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;

  // ★ 通話計時器
  Timer? _callTimer;
  int _callDurationSeconds = 0;

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
        _startCallTimer();
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
        _stopCallTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("通話已結束")),
        );
        Navigator.pop(context);
      }
    };

    // ★ 接聽回達後由家屬端觸發 createOffer（唯一入口，防止重複 Offer）
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

    // ★ 預設開啟揚聲器
    _signaling.enableSpeakerphone(true);

    if (widget.isIncomingCall) {
      _signaling.sendCallAccept(widget.targetSocketId!);
    } else if (widget.autoStart) {
      // 如果是主動呼叫，先發送 Request 給對方點擊接聽
      // 等待 onCallAcceptedByRemote 被觸發後才會執行 createOffer
      _signaling.sendCallRequest(widget.roomId, role: 'family');
    }
  }

  // ★ 通話計時器
  void _startCallTimer() {
    _callTimer?.cancel();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String get _formattedDuration {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ★ 麥克風靜音切換
  void _toggleMic() {
    if (_signaling.localStream == null) return;
    final audioTracks = _signaling.localStream!.getAudioTracks();
    if (audioTracks.isEmpty) return;
    setState(() {
      _isMicMuted = !_isMicMuted;
      for (var track in audioTracks) {
        track.enabled = !_isMicMuted;
      }
    });
    debugPrint("🎤 Mic ${_isMicMuted ? 'Muted' : 'Unmuted'}");
  }

  // ★ 鏡頭開關切換
  void _toggleCamera() {
    if (_signaling.localStream == null) return;
    final videoTracks = _signaling.localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    setState(() {
      _isCameraOff = !_isCameraOff;
      for (var track in videoTracks) {
        track.enabled = !_isCameraOff;
      }
    });
    debugPrint("📷 Camera ${_isCameraOff ? 'Off' : 'On'}");
  }

  // ★ 前後鏡頭切換
  void _switchCamera() {
    if (_signaling.localStream == null) return;
    final videoTracks = _signaling.localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    Helper.switchCamera(videoTracks[0]);
    setState(() => _isFrontCamera = !_isFrontCamera);
    debugPrint("🔄 Camera switched to ${_isFrontCamera ? 'Front' : 'Back'}");
  }

  // ★ 揚聲器切換
  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _signaling.enableSpeakerphone(_isSpeakerOn);
    debugPrint("🔊 Speaker ${_isSpeakerOn ? 'On' : 'Off'}");
  }

  @override
  void dispose() {
    _stopCallTimer();
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

          // 2. 頂部資訊欄
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 通話類型標示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isEmergency ? Icons.warning : Icons.shield,
                        color: widget.isEmergency ? Colors.orangeAccent : Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.isEmergency ? "緊急通話" : "視訊通話",
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // ★ 通話計時器
                if (_inCall)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          _formattedDuration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 3. 本地預覽 (PIP) — 鏡頭關閉時顯示圖標
          Positioned(
            right: 20,
            bottom: 140,
            width: 110,
            height: 160,
            child: GestureDetector(
              onTap: _switchCamera,
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
                  child: _isCameraOff
                      ? Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Center(
                            child: Icon(Icons.videocam_off, color: Colors.white38, size: 36),
                          ),
                        )
                      : RTCVideoView(
                          _localRenderer,
                          mirror: _isFrontCamera,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                ),
              ),
            ),
          ),

          // ★ 鏡頭切換提示 (PIP 右下角小圖標)
          if (!_isCameraOff)
            Positioned(
              right: 24,
              bottom: 144,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cameraswitch, color: Colors.white70, size: 16),
              ),
            ),

          // 4. 底部控制列 (Glassmorphism)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
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
                      // 揚聲器
                      _buildControlButton(
                        icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                        onPressed: _toggleSpeaker,
                        color: _isSpeakerOn ? Colors.white : Colors.white38,
                      ),
                      // 麥克風
                      _buildControlButton(
                        icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                        onPressed: _toggleMic,
                        color: _isMicMuted ? Colors.redAccent : Colors.white,
                        bgColor: _isMicMuted ? Colors.white24 : null,
                      ),
                      // 掛斷
                      _buildControlButton(
                        icon: Icons.call_end,
                        onPressed: () => Navigator.pop(context),
                        isEndCall: true,
                      ),
                      // 鏡頭
                      _buildControlButton(
                        icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                        onPressed: _toggleCamera,
                        color: _isCameraOff ? Colors.redAccent : Colors.white,
                        bgColor: _isCameraOff ? Colors.white24 : null,
                      ),
                      // 翻轉鏡頭
                      _buildControlButton(
                        icon: Icons.cameraswitch,
                        onPressed: _isCameraOff ? null : _switchCamera,
                        color: _isCameraOff ? Colors.white24 : Colors.white,
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
    VoidCallback? onPressed,
    Color color = Colors.white,
    Color? bgColor,
    bool isEndCall = false,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isEndCall ? Colors.redAccent : (bgColor ?? Colors.white12),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}