// lib/screens/family_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen> {
  final Signaling _signaling = Signaling();
  
  // 移除阻擋多重對話框的 bool

  @override
  void initState() {
    super.initState();
    _connectAndListenAll();
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
      
      var caller = widget.elders.firstWhere((e) => e['elder_id'] == roomId, orElse: () => {'elder_name': '未知長輩'});

      // ★ 在顯示 Dialog 前先記錄 Dashboard 自己的 Route，
      //    之後可以用 popUntil 回到這層並清除上層的通話頁面
      final thisRoute = ModalRoute.of(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('📞 求助電話'),
          content: Text('${caller['elder_name']} (ID: $roomId) 正在呼叫！'),
          backgroundColor: Colors.red[50],
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              }, 
              child: const Text('忽略')
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.call),
              label: const Text('接聽'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                Navigator.pop(context); // 關閉彈窗

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
        ),
      );
    };
  }

  @override
  void dispose() {
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