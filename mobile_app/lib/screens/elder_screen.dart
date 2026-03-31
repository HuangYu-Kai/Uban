import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/signaling.dart';
import 'role_selection_screen.dart';
import '../globals.dart';

class ElderScreen extends StatefulWidget {
  final String roomId;
  final bool isCCTVMode;
  final String deviceName;
  final bool autoCall; // 新增參數

  const ElderScreen({
    super.key,
    required this.roomId,
    this.isCCTVMode = false,
    this.deviceName = 'Elder Device',
    this.autoCall = false,
  });

  @override
  State<ElderScreen> createState() => _ElderScreenState();
}

class _ElderScreenState extends State<ElderScreen> with WidgetsBindingObserver {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _status = "等待連線...";
  bool _isInCall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _checkPermissions();
    
    // ★ Bug 16 解決方案：監聽從系統層 (main.dart) 傳進來的 CallKit 接聽動作
    pendingAcceptedCall.addListener(_onPendingCallChanged);

    _initElderMode();

    if (widget.autoCall) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isInCall) {
          _makeCall();
        }
      });
    }
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  void _onPendingCallChanged() {
    debugPrint("🔔 pendingAcceptedCall Changed: ${pendingAcceptedCall.value}");
    _checkPendingAcceptedCall();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingEmergency();
      _checkPendingAcceptedCall();
    }
  }

  Future<void> _checkPendingEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingRoom = prefs.getString('pending_emergency_room');
    final pendingSender = prefs.getString('pending_emergency_sender');

    if (pendingRoom != null && pendingRoom == widget.roomId && pendingSender != null) {
      await prefs.remove('pending_emergency_room');
      await prefs.remove('pending_emergency_sender');
      _handleEmergencyAccept(pendingSender);
    }
  }

  // ★ Bug 16 解決方案：檢查是否有從系統層 (main.dart) 傳進來的 CallKit 接聽動作
  void _checkPendingAcceptedCall() {
    if (pendingAcceptedCall.value != null) {
      final args = pendingAcceptedCall.value!;
      pendingAcceptedCall.value = null; // Consume the event
      
      final senderId = args['senderId']!;
      final roomId = args['roomId']!;
      final callId = args['callId'];
      
      debugPrint("📞 Detected Accepted Call from $senderId (Room: $roomId, CallId: $callId). Bridging...");
      
      _handleAcceptedCallFromBackground(senderId, callId: callId);
    }
  }

  Future<void> _handleAcceptedCallFromBackground(String senderId, {String? callId}) async {
    if (!_isInCall && mounted) {
      setState(() {
        _isInCall = true;
        _status = "通話建立中...";
      });
      
      // 確保畫面被喚醒到最上層 (針對 Android 14+)
      try {
        final platform = MethodChannel('com.example.app/bring_to_front');
        await platform.invokeMethod('bringToFront');
      } catch (e) {
        debugPrint("Bring to front failed: $e");
      }

      // 回報已接聽，讓家屬端發送 Offer
      _signaling.sendCallAccept(senderId, callId: callId);
    }
  }

  Future<void> _handleEmergencyAccept(String senderId, {String? callId}) async {
    if(!_isInCall && mounted) {
      setState(() {
        _isInCall = true;
        _status = "緊急通話自動接聽中...";
      });
      
      FlutterTts flutterTts = FlutterTts();
      await flutterTts.setLanguage("zh-TW");
      await flutterTts.setVolume(1.0);
      await flutterTts.speak("緊急通話，自動接聽中。緊急通話，自動接聽中。");

      // Notify the Family App that we are awake and ready to receive the Offer!
      _signaling.sendCallAccept(senderId, callId: callId);
    }
  }

  Future<void> _initElderMode() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onLocalStream = ((stream) {
      debugPrint("🤳 [ElderScreen] Local stream set! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    _signaling.onAddRemoteStream = ((stream) {
      debugPrint("📺 [ElderScreen] Remote stream added! Tracks: ${stream.getTracks().length}");
      if (mounted) setState(() { _remoteRenderer.srcObject = stream; _status = "通話中"; _isInCall = true; });
    });

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

    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      debugPrint("✅ 家屬($accepterId) 已接聽 (CallId: $callId)，開始定向發送 Offer...");
      if (mounted) setState(() { _status = "連線建立中..."; _isInCall = true; });
      _signaling.createOffer(targetId: accepterId, isEmergency: false);
    };

    await _signaling.openUserMedia(_localRenderer);
    
    _signaling.connect(
      widget.roomId, 
      'elder', 
      userId: int.tryParse(widget.roomId),
      deviceName: widget.deviceName,
      deviceMode: widget.isCCTVMode ? 'cctv' : 'comm'
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      _checkPendingEmergency();
      _checkPendingAcceptedCall();
    });

    _signaling.onCallEnded = () {
      if (mounted) {
        setState(() { 
          _remoteRenderer.srcObject = null; 
          _status = "通話結束"; 
          _isInCall = false; 
        });
        
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    };

    _signaling.onCallBusy = (targetId, callId) {
      if (mounted) {
        setState(() {
          _status = "家人通話中，請稍後再撥";
          _isInCall = false;
        });
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_isInCall) {
            setState(() => _status = "等待連線...");
          }
        });
      }
    };

    _signaling.socket?.on('force-logout', (_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
         Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (route) => false,
        );
      }
    });

    _signaling.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [ElderScreen] Incoming Offer from $callerId (Type: $callType)");
      if (_isInCall || callType == 'emergency' || widget.isCCTVMode) {
        if (mounted) setState(() => _isInCall = true);
        return true; 
      }
      return false; 
    };
  }

  // 主動呼叫 (先響鈴)
  void _makeCall() {
    setState(() { _status = "正在呼叫家人..."; _isInCall = true; });
    _signaling.sendCallRequest(widget.roomId, role: 'elder');
  }

  void _hangUp() {
    // If we are hanging up while the status is "正在呼叫家人..." (Calling Family),
    // it means the family hasn't answered yet. We should send a cancel-call so 
    // the family's CallKit dismisses.
    if (_status == "正在呼叫家人...") {
      _signaling.sendCancelCall(widget.roomId);
    }
    _signaling.hangUp(disconnectSocket: false, disposeLocalStream: false);
    setState(() { 
      _remoteRenderer.srcObject = null; 
      _status = "通話結束"; 
      _isInCall = false; 
    });

    // ★ 延遲 1.5 秒後自動回到首頁
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.clearSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder(
        valueListenable: pendingAcceptedCall,
        builder: (context, pendingCall, _) {
          return Stack(
            children: [
              // 1. 全螢幕視訊區塊 (沉浸式)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF121212),
                  child: _remoteRenderer.srcObject != null
                      ? RTCVideoView(
                          _remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isInCall)
                                const CircularProgressIndicator(color: Colors.orangeAccent),
                              const SizedBox(height: 24),
                              Text(
                                _status,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              // 2. 本地預覽 (精緻 PIP)
              Positioned(
                right: 20,
                top: MediaQuery.of(context).padding.top + 20,
                width: 110,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
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

              // 3. CCTV 模式提示
              if (widget.isCCTVMode)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text("CCTV 守護中", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

              // 4. 底部控制列 (大按鈕，便於操作)
              if (!widget.isCCTVMode)
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_isInCall)
                        GestureDetector(
                          onTap: _makeCall,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                              ),
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.call, color: Colors.white, size: 28),
                                SizedBox(width: 12),
                                Text(
                                  "呼叫家人",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_isInCall)
                        GestureDetector(
                          onTap: _hangUp,
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.call_end, color: Colors.white, size: 48),
                          ),
                        ),
                    ],
                  ),
                ),

              // 5. 測試/登出按鈕 (右下角)
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white24,
                  elevation: 0,
                  child: const Icon(Icons.logout, color: Colors.white),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
