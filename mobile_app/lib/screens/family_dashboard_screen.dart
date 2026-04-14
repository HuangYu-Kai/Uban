// lib/screens/family_dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 新增
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../main.dart'; // import callKitDeclineStream
import '../services/signaling.dart'; 
import 'device_selection_screen.dart';
import 'video_call_screen.dart'; 
import 'role_selection_screen.dart';
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

  void _connectAndListenAll() {
    // 1. 連線 Lobby (隨意選一個 ID 或固定字串)
    String firstRoom = widget.elders.isNotEmpty ? widget.elders[0]['elder_id'] : 'family_lobby';
    _signaling.connect(firstRoom, 'family', deviceName: 'Dashboard');

    // 2. 加入其他長輩房間
    for (var elder in widget.elders) {
      if (elder['elder_id'] != firstRoom) {
        _signaling.joinRoom(elder['elder_id']);
      }
    }

    // 3. 處理響鈴 (使用當前的 Context)
    _signaling.onCallRequest = (roomId, senderId, callId) {
      if (!mounted) return;
      
      // Remove any existing dialogs to prevent multiple stacking, or if the user cancels
      if (Navigator.canPop(context)) {
        // Warning: This pops the current top route. Assuming the only pop-able route here is the dialog.
        // It's safer to use a named route or track the dialog state, but let's try pop first.
      }
      
      var caller = widget.elders.firstWhere((e) => e['elder_id'] == roomId, orElse: () => {'elder_name': '未知長輩'});

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
            _signaling.onCancelCall = (cancelRoomId, cancelSenderId, cancelCallId) {
                if (roomId == cancelRoomId && isDialogOpen && mounted) {
                    Navigator.of(dialogContext).pop();
                    isDialogOpen = false;
                    _currentDialogRoomId = null;
                    _dialogContext = null;
                }
            };

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _declineSub?.cancel();
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
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