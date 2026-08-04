// lib/screens/video_call_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/signaling.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../screens/family_main_screen.dart';
import '../screens/elder_home_screen.dart';
import '../globals.dart' as globals;

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String? targetSocketId;
  final bool isIncomingCall;
  final bool autoStart;
  final bool isEmergency;
  final String? callId;
  final bool sendAcceptOnOpen;
  final bool isVideoCall; // ★ Fix E：是否為視訊通話（false = 純語音/電話）

  const VideoCallScreen({
    super.key,
    required this.roomId,
    this.targetSocketId,
    this.isIncomingCall = false,
    this.autoStart = false,
    this.isEmergency = false,
    this.callId,
    this.sendAcceptOnOpen = true,
    this.isVideoCall = true, // 預設視訊通話
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
  bool _isCameraOff = false;  // 視訊房間預設開啟鏡頭
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _mediaInitialized = false;  // ★ 追蹤媒體是否已初始化
  bool _callConnecting = true;   // ★ 追蹤通話是否正在連線中
  bool _callConnected = false;   // ★ 追蹤通話是否已成功連線
  bool _callFailed = false;      // ★ 追蹤通話是否連線失敗
  String _callErrorMessage = ''; // ★ 通話失敗時的錯誤訊息

  // ★ 通話計時器
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  // ★ 通話逾時計時器
  Timer? _callTimeoutTimer;

  // ★ 情境 3 修復：結束通話後導回主畫面時所需的真實使用者資料（於 _initCall 從 prefs 讀取）
  int _resolvedUserId = 0;
  String _resolvedUserName = '家屬端';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication);
    }
    _initCall();
    // 設定通話逾時（30秒）
    _callTimeoutTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_callConnecting && !_callConnected && !_callFailed) {
        // 如果已經連線中超過30秒且仍未連線，則視為失敗
        // 這裡其實是每5秒檢查一次，但實際逾時時間在 _initCall 中控制
      }
    });
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
          _callConnecting = false;
          _callConnected = true;
          _callFailed = false;
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
        // ★ 2026-07-27 第十三輪：原本用 SnackBar，但緊接著的 _goHomeAfterCall() 是
        //   pushAndRemoveUntil，會立刻移除本 route，SnackBar 隨之消失 → 使用者看到
        //   的是「瞬間跳回主畫面、毫無提示」。改用不依附特定 route 的 dialog
        //   （與 onCallBusy 一致，2026-07-15 第二輪 Issue 6 當時漏改這兩個回調）。
        _showCallRejectedThenGoHome('對方已掛斷通話');
      }
    };

    _signaling.onCallBusy = (targetId, callId) {
      if (mounted) {
        _stopCallTimer();
        _showCallRejectedThenGoHome('對方已拒絕或目前無法接聽通話');
      }
    };

    // ★ issue 5：通話中發生無法復原的連線中斷（已超過 signaling.dart 的 2 秒重連寬限期）
    _signaling.onConnectionLost = () {
      if (mounted) {
        _stopCallTimer();
        // ★ 2026-07-27 第十三輪：同 onCallEnded，SnackBar 會被 pushAndRemoveUntil 吞掉。
        _showCallRejectedThenGoHome('網路連線中斷');
      }
    };

    // ★ 接聽回達後由家屬端觸發 createOffer（唯一入口，防止重複 Offer）
    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      debugPrint("✅ [VideoCallScreen] Target Accepted ($accepterId), sending Offer...");
      _signaling.createOffer(targetId: accepterId, isEmergency: widget.isEmergency);
    };

    // ★ 初始化媒體：通話必須有音軌才能建立 WebRTC 連線
    // 我們先開啟媒體，但預設將鏡頭的軌道設為停用 (黑屏)，保護隱私
    try {
      await _signaling.openUserMedia(_localRenderer);
      _mediaInitialized = true;
      // ★ Fix E：語音通話（isVideoCall=false）預設關閉鏡頭，與發起端對稱；
      //   鏡頭按鈕仍可手動開啟（見 _toggleCamera），此處僅決定進房初始狀態。
      if (!widget.isVideoCall && mounted) {
        setState(() => _isCameraOff = true);
      }
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        for (var track in videoTracks) {
          track.enabled = widget.isVideoCall;
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to initialize media: $e");
      if (mounted) {
        setState(() {
          _callConnecting = false;
          _callFailed = true;
          _callErrorMessage = '無法開啟攝像頭或麥克風: $e';
        });
      }
    }

    // ★ 自動讀取使用者 ID 與名稱
    final prefs = await SharedPreferences.getInstance();
    final String role = prefs.getString('user_role') ?? 'family';
    final int? userId = (role == 'elder')
        ? prefs.getInt('caregiver_id')
        : (prefs.getInt('user_id') ?? prefs.getInt('caregiver_id'));
    final String userName = (role == 'elder')
        ? (prefs.getString('caregiver_name') ?? '長輩')
        : (prefs.getString('user_name') ?? prefs.getString('caregiver_name') ?? '家屬端');

    // ★ 情境 3 修復：暫存真實使用者資料，供通話結束後重建主畫面使用（避免 userId:0 導致主畫面失效）
    _resolvedUserId = userId ?? 0;
    _resolvedUserName = userName;

    // ★ 修復：若 Socket 已經連線（從 FamilyMainScreen 傳承下來），則不要重新連線，
    //   否則會導致原本的 callbacks 被覆寫且 SocketId 改變。
    if (_signaling.socket?.connected != true) {
      debugPrint("🔌 [VideoCallScreen] Socket 未連線，開始連線...");
      final String? fcmToken = await FirebaseMessaging.instance.getToken();
      _signaling.connect(
        widget.roomId,
        'family',
        userId: userId,
        deviceName: userName,
        fcmToken: fcmToken,
      );
    } else {
      debugPrint("🔌 [VideoCallScreen] Socket 已連線，重用現有連線 (room: ${widget.roomId})");
    }

    // ★ 預設開啟揚聲器
    _signaling.enableSpeakerphone(true);

    if (widget.isIncomingCall && widget.sendAcceptOnOpen) {
      _signaling.sendCallAccept(widget.targetSocketId!, callId: widget.callId);
    } else if (widget.autoStart) {
      Future.microtask(() async {
        int retries = 50; // 最多等待 5 秒
        while (_signaling.socket?.connected != true && retries > 0) {
          await Future.delayed(const Duration(milliseconds: 100));
          retries--;
        }
        if (!mounted) return;

        if (widget.isEmergency) {
          _signaling.sendEmergencyCall(widget.roomId, targetId: widget.targetSocketId);
        } else {
          // 如果是主動呼叫，先發送 Request 給對方點擊接聽 (確保觸發 FCM 與資料庫記錄)
          _signaling.sendCallRequest(widget.roomId, role: 'family', targetId: widget.targetSocketId);
        }
      });
    }

    // 緊急通話需等待對端被喚醒與自動接聽，逾時窗拉長避免家屬端誤判自動掛斷
    final int connectTimeoutSeconds = widget.isEmergency ? 60 : 20;
    Future.delayed(Duration(seconds: connectTimeoutSeconds), () {
      if (mounted && _callConnecting && !_callConnected) {
        // ★ 2026-07-18：逾時未接通時，主動通知對方取消／掛斷，避免被叫方 CallKit
        //   繼續響到 45 秒。僅撥打方（非來電接聽方）需要送取消。
        if (!widget.isIncomingCall) {
          try {
            _signaling.sendCancelCall(widget.roomId, role: 'family');
          } catch (e) {
            debugPrint('⚠️ [VideoCall] timeout sendCancelCall failed: $e');
          }
        }
        _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
        setState(() {
          _callConnecting = false;
          _callFailed = true;
          _callErrorMessage = '連線逾時，請檢查網路連接或稍後再試';
        });
      }
    });
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

  // ★ 鏡頭開關切換 — 同時初始化媒體（如果還未初始化）
  void _toggleCamera() {
    if (!_mediaInitialized) {
      _initializeAndToggleCamera();
      return;
    }
    
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

  // ★ 初始化媒體並打開攝像頭
  Future<void> _initializeAndToggleCamera() async {
    try {
      debugPrint("🎬 Initializing media stream...");
      await _signaling.openUserMedia(_localRenderer);
      setState(() => _mediaInitialized = true);
      
      if (_signaling.localStream != null) {
        final videoTracks = _signaling.localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          setState(() {
            _isCameraOff = false;  // 開啟攝像頭
            for (var track in videoTracks) {
              track.enabled = true;
            }
          });
          debugPrint("📷 Camera initialized and turned On");
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to initialize media: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("無法開啟攝像頭: $e")),
        );
      }
    }
  }

  // ★ 前後鏡頭切換 — 必須先初始化媒體
  void _switchCamera() {
    if (!_mediaInitialized || _signaling.localStream == null) return;
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
    _callTimeoutTimer?.cancel();
    // ★ 修復：只結束 WebRTC，不要斷開 Socket，這樣回到 FamilyMainScreen 時才能繼續接收推播
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);

    // ★ 清空 UI 相關的 callbacks，讓全域的 callbacks 重拾控制權
    _signaling.onCallAcceptedByRemote = null;
    _signaling.onAddRemoteStream = null;
    _signaling.onLocalStream = null;
    _signaling.onIncomingCall = null;
    _signaling.onCallEnded = null;
    _signaling.onCallBusy = null;
    _signaling.onJoinFailed = null;
    _signaling.onConnectionLost = null;

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


  // ★ issue 3 fix: 安全掛斷並導航，防止冷啟動進入時 pop 後黑屏
  void _safeHangUp() {
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    _stopCallTimer();
    if (mounted) {
      _goHomeAfterCall();
    }
  }

  // ★ issue 3 fix: 冷啟動時無上一頁，退回 FamilyMainScreen（帶入真實使用者資料）
  Widget _buildFallbackHome() {
    if (globals.appRole == 'elder') {
      return ElderHomeScreen(
        userId: _resolvedUserId,
        userName: _resolvedUserName,
      );
    }
    return FamilyMainScreen(
      userId: _resolvedUserId,
      userName: _resolvedUserName,
    );
  }

  // ★ 情境 3 修復：通話結束/拒接/斷線後，一律用 pushAndRemoveUntil 導向「重建的」主畫面。
  //   家屬端在 APP 外接聽時，VideoCallScreen 會被疊在 SplashScreen 之上；若用 pop()
  //   會回到已完成任務的 SplashScreen 造成黑屏。改用 pushAndRemoveUntil 可確定性返回
  //   主畫面、清空堆疊，杜絕任何黑屏。
  void _goHomeAfterCall() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildFallbackHome()),
      (route) => false,
    );
  }

  void _showCallRejectedThenGoHome(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('通話已結束'),
        content: Text(message),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _goHomeAfterCall();
    });
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
                          if (_callFailed)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wifi_off,
                                  color: Colors.redAccent,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _callErrorMessage.isNotEmpty
                                      ? _callErrorMessage
                                      : '通話連線失敗',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    // 重試連線
                                    setState(() {
                                      _callConnecting = true;
                                      _callFailed = false;
                                      _callErrorMessage = '';
                                      _callConnected = false;
                                    });
                                    _initCall(); // 重新初始化通話
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重試連線'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            )
                          else
                            Column(
                              mainAxisSize: MainAxisSize.min,
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
                        widget.isEmergency
                            ? Icons.warning
                            : (widget.isVideoCall ? Icons.shield : Icons.call),
                        color: widget.isEmergency
                            ? Colors.orangeAccent
                            : (widget.isVideoCall ? Colors.greenAccent : Colors.lightBlueAccent),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        // ★ Fix E：非緊急且非視訊時顯示「語音通話」，其餘沿用原邏輯。
                        widget.isEmergency
                            ? "緊急通話"
                            : (widget.isVideoCall ? "視訊通話" : "語音通話"),
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
            bottom: 220,  // ★ 從 140 改為 220，避免與按鈕重疊
            width: 110,
            height: 160,
            child: GestureDetector(
              onTap: (_mediaInitialized && !_isCameraOff) ? _switchCamera : null,
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
                  border: Border.all(
                    color: _isCameraOff ? Colors.white12 : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _isCameraOff
                      ? Container(
                          color: const Color(0xFF2A2A2A),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.videocam_off,
                                color: Colors.white38,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '鏡頭已關閉',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
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
          if (_mediaInitialized && !_isCameraOff)
            Positioned(
              right: 24,
              bottom: 224,  // ★ 與 PIP 位置同步（220 + 4）
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
                        onPressed: _safeHangUp,
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
                        onPressed: (_mediaInitialized && !_isCameraOff) ? _switchCamera : null,
                        color: (_mediaInitialized && !_isCameraOff) ? Colors.white : Colors.white24,
                        bgColor: (_mediaInitialized && !_isCameraOff) ? null : Colors.white.withValues(alpha: 0.1),
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
    final isDisabled = onPressed == null;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isEndCall 
          ? Colors.redAccent 
          : (bgColor ?? (isDisabled ? Colors.white.withValues(alpha: 0.05) : Colors.white12)),
        shape: BoxShape.circle,
        border: isDisabled ? Border.all(color: Colors.white12, width: 1) : null,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}
