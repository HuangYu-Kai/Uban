// lib/screens/family_dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../main.dart'; // import callKitDeclineStream
import '../services/signaling.dart'; 
import 'device_selection_screen.dart';
import 'video_call_screen.dart'; 
import 'role_selection_screen.dart';

class FamilyDashboardScreen extends StatefulWidget {
  final List<dynamic> elders;

  const FamilyDashboardScreen({Key? key, required this.elders}) : super(key: key);

  @override
  _FamilyDashboardScreenState createState() => _FamilyDashboardScreenState();
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
    if (state == AppLifecycleState.resumed) {
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
    _signaling.onCallRequest = (roomId, senderId) {
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

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
            _dialogContext = dialogContext;
            
            // Register cancel-call listener tightly to this dialog's lifecycle
            _signaling.onCancelCall = (cancelRoomId, cancelSenderId) {
                if (roomId == cancelRoomId && isDialogOpen && mounted) {
                    Navigator.of(dialogContext).pop();
                    isDialogOpen = false;
                    _currentDialogRoomId = null;
                    _dialogContext = null;
                }
            };

            return AlertDialog(
          title: const Text('📞 求助電話'),
          content: Text('${caller['elder_name']} (ID: $roomId) 正在呼叫！'),
          backgroundColor: Colors.red[50],
          actions: [
            TextButton(
              onPressed: () {
                isDialogOpen = false;
                _currentDialogRoomId = null;
                _dialogContext = null;
                _signaling.sendCallBusy(senderId); // explicitly inform elder someone declined
                Navigator.pop(dialogContext);
              }, 
              child: const Text('忽略')
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.call),
              label: const Text('接聽'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                isDialogOpen = false;
                _currentDialogRoomId = null;
                _dialogContext = null;
                Navigator.pop(dialogContext); // 關閉彈窗

                // ★ 先回到儀表板層（關閉任何正在通話中的 VideoCallScreen）
                //    確保舊的通話結束並釋放攝影機權限
                if (thisRoute != null) {
                  Navigator.of(context).popUntil((route) => route == thisRoute);
                }

                // ★ 使用 microtask 確保 popUntil dispose() 完成後再推入新頁面
                Future.microtask(() {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoCallScreen(
                          roomId: roomId,
                          targetSocketId: senderId,
                          isIncomingCall: true,
                        ),
                      ),
                    );
                  }
                });
              },
            ),
          ],
        );
      },
      );
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _declineSub?.cancel();
    _signaling.dispose();
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
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