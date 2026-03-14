// lib/screens/elder_screen.dart
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

  const ElderScreen({Key? key, required this.roomId, this.isCCTVMode = false, required this.deviceName}) : super(key: key);

  @override
  _ElderScreenState createState() => _ElderScreenState();
}

class _ElderScreenState extends State<ElderScreen> with WidgetsBindingObserver {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _status = "等待連線...";
  bool _isInCall = false;
  BuildContext? _incomingCallDialogContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _checkPermissions();
    
    // ★ Bug 16 解決方案：監聽從系統層 (main.dart) 傳進來的 CallKit 接聽動作
    pendingAcceptedCall.addListener(_onPendingCallChanged);
  }

  void _onPendingCallChanged() {
    print("🔔 pendingAcceptedCall Changed: ${pendingAcceptedCall.value}");
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
      
      print("📞 Detected Accepted Call from $senderId (Room: $roomId, CallId: $callId). Bridging...");
      
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
        print("Bring to front failed: $e");
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

    // 如果在前景收到緊急通訊 Socket
    _signaling.onEmergencyCall = (roomId, senderId, callId) {
        _handleEmergencyAccept(senderId, callId: callId);
    };

    // 如果在前景收到一般通訊 Socket
    _signaling.onCallRequest = (roomId, senderId, callId) {
        // 在長輩端，一般通話通常是跳出 Dialog，這裡暫時與緊急通話處理邏輯分開，或者視需求自動接聽
        // 目前暫不處理一般通話主動彈窗 (因為長輩端通常是被動接收)
        print("📱 Foreground Call Request from $senderId (Room: $roomId, CallId: $callId)");
    };

    // ★★★ 關鍵：家屬接聽後，才發送 Offer (解決影像連線問題) ★★★
    _signaling.onCallAcceptedByRemote = (accepterId, callId) {
      print("✅ 家屬($accepterId) 已接聽 (CallId: $callId)，開始定向發送 Offer...");
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

    // ★ Bug 14 解決方案：除了靠 AppLifecycleState.resumed 觸發以外，
    // 在啟動完成且剛連上 Socket 的這瞬間，也要主動去檢查有沒有 pending 的通話要求。
    // 這樣在 App 全程被關掉並依靠推播冷啟動時，就能第一時間回傳 sendCallAccept 解除家屬端的對話框。
    Future.delayed(const Duration(milliseconds: 1500), () {
      _checkPendingEmergency();
      _checkPendingAcceptedCall();
    });

    // 掛斷後重置狀態
    _signaling.onCallEnded = () {
      if (mounted) {
        if (_incomingCallDialogContext != null && Navigator.canPop(_incomingCallDialogContext!)) {
          Navigator.pop(_incomingCallDialogContext!);
          _incomingCallDialogContext = null;
        }
        setState(() { 
          _remoteRenderer.srcObject = null; 
          _status = "通話結束"; 
          _isInCall = false; 
        });
      }
    };

    // 背景來的正常通話要求 (會由這支負責彈窗)
    _signaling.onCallRequest = (reqRoomId, reqSenderId, callId) async {
       if (mounted) {
         bool accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            _incomingCallDialogContext = dialogContext;
            return AlertDialog(
              title: const Text('家人來電'),
              content: const Text('是否接聽？'),
              actions: [
                TextButton(onPressed: () {
                  _incomingCallDialogContext = null;
                  Navigator.pop(dialogContext, false);
                }, child: const Text('拒絕')),
                ElevatedButton(onPressed: () {
                  _incomingCallDialogContext = null;
                  Navigator.pop(dialogContext, true);
                }, child: const Text('接聽')),
              ],
            );
          },
        ) ?? false;
        
        if (accept) {
          setState(() { _status = "連線建立中..."; _isInCall = true; });
          _signaling.sendCallAccept(reqSenderId, callId: callId);
        } else {
          _signaling.sendCallBusy(reqSenderId, callId: callId);
        }
       }
    };

    // 對方取消來電
    _signaling.onCancelCall = (cancelRoomId, senderId, callId) {
      if (mounted) {
        if (_incomingCallDialogContext != null && Navigator.canPop(_incomingCallDialogContext!)) {
          Navigator.pop(_incomingCallDialogContext!);
          _incomingCallDialogContext = null;
        }
        setState(() {
          _status = "對方已取消來電";
          _isInCall = false;
        });
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_isInCall) {
            setState(() => _status = "等待連線...");
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
        
        // 延遲幾秒後恢復預設狀態
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_isInCall) {
            setState(() => _status = "等待連線...");
          }
        });
      }
    };

    // 背景來的被強制登出要求 (Feature 12)
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
      // 由於一般來電已經在 onCallRequest 那邊彈出視窗且使用者點擊同意了，
      // 所以這時收到的 Offer 一律放行 (不論是 CCTV、Emergency、或是剛答應的 Normal)
      setState(() => _isInCall = true);
      return true; 
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
    setState(() { _remoteRenderer.srcObject = null; _status = "等待連線..."; _isInCall = false; });
  }

  @override
  void dispose() {
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName),
        backgroundColor: widget.isCCTVMode ? Colors.redAccent : Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                // 回到角色選擇畫面，並清空路由歷史
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: pendingAcceptedCall,
        builder: (context, pendingCall, _) {
          // 在 UI 渲染時也檢查一次，確保不會漏掉
          return Stack(
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
          );
        },
      ),
    );
  }
}