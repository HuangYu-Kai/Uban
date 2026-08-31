// lib/screens/family_dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 新增
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'identification_screen.dart'; // ★ 將原本的 role_selection_screen.dart 改為新的系統入口
import '../main.dart'; // import callKitDeclineStream
import '../services/signaling.dart';
import '../services/session_manager.dart';
import 'device_selection_screen.dart';
import 'video_call_screen.dart'; 
import '../globals.dart';

class FamilyDashboardScreen extends StatefulWidget {
  final List<dynamic> elders;

  const FamilyDashboardScreen({super.key, required this.elders});

  @override
  State<FamilyDashboardScreen> createState() => _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen> with WidgetsBindingObserver {
  final Signaling _signaling = Signaling();
  StreamSubscription? _declineSub;
  String? _currentDialogRoomId;
  BuildContext? _dialogContext;

  // ★ Signaling 是全域單例、onCallRequest／onCancelCall 各只有一個欄位，
  //   最後賦值者獨佔；本畫面 dispose 後若不歸還，閉包會持續指向已卸載的
  //   State，之後每一通來電都會被 `if (!mounted) return;` 靜默吞掉（無
  //   log、無 UI）。這裡保留自己那份 closure 的參考，dispose 時用
  //   identical() 只在「單例上掛的仍是自己這一份」時才清除，避免誤清掉
  //   接手畫面（例如重新進入本畫面後）的回呼。
  CallRequestCallback? _ownCallRequest;
  CallRequestCallback? _ownCancelCall;

  // ★ 2026-08-18 房間洩漏修復：記錄本畫面透過 joinRoom() 額外加入的
  //   `comm_elder_<id>` 監聽房間（第一位長輩的房間是由 connect() 建立、
  //   歸 _currentRoomId 管，不算在這裡）。dispose() 時要逐一離開，否則
  //   同一條 family socket 只要看過越多長輩，就會永久疊加越多房間成員。
  final Set<String> _joinedListenerRooms = {};

  // 移除阻擋多重對話框的 bool

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    //宣告儀表板已經完成初始掛載，允許main.dart直接發動Push
    isAppReady = true;

    // ★ 檢查是否有系統冷啟動時接聽的通話 (解決 Bug 8)
    if (pendingAcceptedCall.value != null) {
      final args = pendingAcceptedCall.value!;
      pendingAcceptedCall.value = null;
      Future.microtask(() {
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              roomId: args['roomId']!,
              targetSocketId: args['senderId']!,
              isIncomingCall: true,
              callId: args['callId'],
            ),
          ));
        }
      });
    } else {
      // 若 Dart 層沒收到事件 (完全被系統殺死時可能遺失)，主動去向 Native 查詢是否有接聽中的通話
      if (!kIsWeb) {
        _checkColdBootCallKit();
      }
    }
    
    // Listen for declines from CallKit (which can happen while app is in background)
    _declineSub = callKitDeclineStream.stream.listen((declinedRoomId) {
      if (_currentDialogRoomId == declinedRoomId && _dialogContext != null) {
        if (Navigator.canPop(_dialogContext!)) {
          Navigator.pop(_dialogContext!);
        }
        _currentDialogRoomId = null;
        _dialogContext = null;
      }
    });

    _connectAndListenAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      // Check if the CallKit notification was cleared or answered outside the app
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List && activeCalls.isEmpty && _dialogContext != null) {
        if (Navigator.canPop(_dialogContext!)) {
          Navigator.pop(_dialogContext!);
        }
        _currentDialogRoomId = null;
        _dialogContext = null;
      }
    }
  }

  Future<void> _checkColdBootCallKit() async {
    if (kIsWeb) return;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List && activeCalls.isNotEmpty) {
        final call = activeCalls[0];
        final extra = call['extra'];
        if (extra != null && extra is Map) {
          final roomId = extra['roomId'];
          final senderId = extra['senderId'];
          if (roomId != null && senderId != null) {
            // 清除 CallKit UI
            await FlutterCallkitIncoming.endAllCalls();
            
            if (mounted) {
              // 如果有對話框顯示中，關閉它
              if (_dialogContext != null && Navigator.canPop(_dialogContext!)) {
                Navigator.pop(_dialogContext!);
                _currentDialogRoomId = null;
                _dialogContext = null;
              }
              
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => VideoCallScreen(
                  roomId: roomId.toString(),
                  targetSocketId: senderId.toString(),
                  isIncomingCall: true, // 這會讓視訊房自動送出接聽通知給長輩
                  callId: extra['callId']?.toString(),
                ),
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Cold boot active call check failed: $e");
    }
  }

  Future<void> _connectAndListenAll() async {
    if (widget.elders.isEmpty) {
      debugPrint("ℹ️ [Dashboard] No paired elders. Skipping signaling connection.");
      return;
    }

    // ★ 修復：從 SharedPreferences 讀取真正的 user_id（caregiver_id）
    final prefs = await SharedPreferences.getInstance();
    final int? actualUserId = prefs.getInt('caregiver_id');

    // 1. 連線第一個長輩的房間 (以 'comm_elder_' 為前綴)
    final String firstRoomRaw = widget.elders[0]['elder_id'].toString();
    final String firstRoom = 'comm_elder_$firstRoomRaw';
    _signaling.connect(firstRoom, 'family', userId: actualUserId, deviceName: 'Dashboard');

    // 2. 加入其他長輩房間
    for (var elder in widget.elders) {
      final String room = 'comm_elder_${elder['elder_id']}';
      if (room != firstRoom) {
        _signaling.joinRoom(room, userId: actualUserId);
        _joinedListenerRooms.add(room); // ★ 房間洩漏修復：記下來，dispose() 時才知道要離開哪些房間
      }
    }

    // 3. 處理響鈴 (使用當前的 Context)
    // ★ 先寫進 _ownCallRequest 欄位再指派給單例，讓 dispose() 能用 identical()
    //   比對「單例上掛的是不是自己這一份」，才敢安全歸還。
    _ownCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;

      // Remove any existing dialogs to prevent multiple stacking, or if the user cancels
      if (Navigator.canPop(context)) {
        // Warning: This pops the current top route. Assuming the only pop-able route here is the dialog.
        // It's safer to use a named route or track the dialog state, but let's try pop first.
      }
      
      var caller = widget.elders.firstWhere(
        (e) => 'comm_elder_${e['elder_id']}' == roomId || e['elder_id'] == roomId, 
        orElse: () => {'elder_name': '未知長輩'}
      );

      // ★ 在顯示 Dialog 前先記錄 Dashboard 自己的 Route，
      //    之後可以用 popUntil 回到這層並清除上層的通話頁面
      final thisRoute = ModalRoute.of(context);
      
      // Define a dialog identifier or key if possible, but for now we'll rely on a boolean flag
      bool isDialogOpen = true;
      _currentDialogRoomId = roomId;

      // ★ 新增：通知時手機振動（長振動 + 中振動 + 短振動）
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), () {
        HapticFeedback.mediumImpact();
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        HapticFeedback.lightImpact();
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
            _dialogContext = dialogContext;
            
            // Register cancel-call listener tightly to this dialog's lifecycle
            // ★ 同樣先寫進 _ownCancelCall 欄位，dispose() 才能用 identical() 安全歸還。
            _ownCancelCall = (cancelRoomId, cancelSenderId, cancelCallId, [cancelSenderName]) {
                if (roomId == cancelRoomId && isDialogOpen && mounted) {
                    Navigator.of(dialogContext).pop();
                    isDialogOpen = false;
                    _currentDialogRoomId = null;
                    _dialogContext = null;
                }
            };
            _signaling.onCancelCall = _ownCancelCall;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 16,
              backgroundColor: Colors.white,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.red.shade50, Colors.orange.shade50],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ★ 頂部裝飾條（紅色，表示緊急）
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // ★ 警告圖標（緊急狀態）
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.shade400.withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: Colors.red.shade400,
                        child: const Icon(
                          Icons.sos,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // ★ 標題
                    Text(
                      '緊急求助來電',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // ★ 來電者信息
                    Text(
                      '${caller['elder_name'] ?? "未知長輩"} 正在求助',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // ★ ID（灰色較小字體）
                    Text(
                      'ID: $roomId',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // ★ 來電狀態（脈搏動畫效果）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.8),
                                blurRadius: 4,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在來電...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 36),
                    
                    // ★ 按鈕區域
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          // 忽略按鈕
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.shade300,
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  isDialogOpen = false;
                                  _currentDialogRoomId = null;
                                  _dialogContext = null;
                                  _signaling.sendCallBusy(senderId, callId: callId);
                                  Navigator.pop(dialogContext);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade300,
                                  foregroundColor: Colors.grey.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('忽略'),
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 12),
                          
                          // 接聽按鈕（強調紅色）
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.shade300,
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  isDialogOpen = false;
                                  _currentDialogRoomId = null;
                                  _dialogContext = null;
                                  Navigator.pop(dialogContext);

                                  if (thisRoute != null) {
                                    Navigator.of(context).popUntil((route) => route == thisRoute);
                                  }

                                  Future.microtask(() {
                                    if (mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => VideoCallScreen(
                                            roomId: roomId,
                                            targetSocketId: senderId,
                                            isIncomingCall: true,
                                            isEmergency: true,
                                            callId: callId,
                                            sendAcceptOnOpen: false,
                                          ),
                                        ),
                                      );
                                    }
                                  });
                                },
                                icon: const Icon(Icons.call, size: 20),
                                label: const Text('接聽'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade500,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
      },
      );
    };
    _signaling.onCallRequest = _ownCallRequest;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _declineSub?.cancel();

    // ★ Signaling 是全域單例、onCallRequest／onCancelCall 只有一個欄位，最後
    //   賦值者獨佔；只在「單例上掛的仍是自己這一份」時才清除（identical
    //   比對），避免誤清掉接手畫面（例如重新進入本畫面後）剛註冊的回呼。
    if (identical(_signaling.onCallRequest, _ownCallRequest)) {
      _signaling.onCallRequest = null;
    }
    if (identical(_signaling.onCancelCall, _ownCancelCall)) {
      _signaling.onCancelCall = null;
    }

    // ★ 2026-08-18 房間洩漏修復：離開本畫面額外加入的每個監聽房間。
    //   對每個房間同時呼叫 leaveRoom（已加入的情況）與 cancelPendingRoom
    //   （socket 尚未連線、房間還卡在 _pendingRooms 排隊中的情況）——
    //   兩者都是安全的 no-op（房間不存在/不在排隊中就什麼都不做），
    //   不需要額外狀態去區分「這個房間到底加入了沒」，寫法可以保持精簡。
    //   必須排在 clearSession() 之前：clearSession 可能導致 socket 斷線，
    //   之後才呼叫 leaveRoom 會直接被 no-op 掉。
    for (final room in _joinedListenerRooms) {
      _signaling.leaveRoom(room);
      _signaling.cancelPendingRoom(room);
    }
    _joinedListenerRooms.clear();

    _signaling.clearSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇監控對象'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await SessionManager.releaseSession();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const IdentificationScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: widget.elders.isEmpty
          ? const Center(child: Text("無資料"))
          : ListView.builder(
              itemCount: widget.elders.length,
              itemBuilder: (context, index) {
                final elder = widget.elders[index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(elder['elder_name'][0])),
                    title: Text(elder['elder_name']),
                    subtitle: Text("ID: ${elder['elder_id']}"),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeviceSelectionScreen(
                            elderId: elder['elder_id'],
                            elderName: elder['elder_name'],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
