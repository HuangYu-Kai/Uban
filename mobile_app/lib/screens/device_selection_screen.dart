// lib/screens/device_selection_screen.dart
import 'package:flutter/material.dart';
import '../services/signaling.dart';
import 'monitoring_screen.dart';
import 'video_call_screen.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final String elderId;
  final String elderName;

  const DeviceSelectionScreen({Key? key, required this.elderId, required this.elderName}) : super(key: key);

  @override
  _DeviceSelectionScreenState createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final Signaling _signaling = Signaling();
  List<dynamic> _onlineDevices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _signaling.connect(widget.elderId, 'family', deviceName: 'FamilySelector');
    _signaling.onElderDevicesUpdate = (devices) {
      if (mounted) setState(() { _onlineDevices = devices; _isLoading = false; });
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
      appBar: AppBar(title: Text('${widget.elderName} 的設備')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _onlineDevices.isEmpty
              ? const Center(child: Text("目前沒有在線設備"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _onlineDevices.length,
                  itemBuilder: (context, index) {
                    final device = _onlineDevices[index];
                    final String name = device['deviceName'] ?? 'Unknown';
                    final String socketId = device['id'];
                    final String mode = device['deviceMode'] ?? 'comm'; 
                    final bool isOnline = device['isOnline'] ?? true; // 相容舊版，預設為在線

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          mode == 'cctv' ? Icons.videocam : Icons.phone_in_talk, 
                          color: isOnline ? (mode == 'cctv' ? Colors.red : Colors.green) : Colors.grey
                        ),
                        title: Text(isOnline ? name : "(離線) $name", style: TextStyle(color: isOnline ? Colors.black : Colors.grey)),
                        subtitle: Text(mode == 'cctv' ? "監控模式" : "通訊模式"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mode == 'cctv')
                              IconButton(
                                icon: Icon(Icons.videocam, color: isOnline ? Colors.blue : Colors.grey),
                                onPressed: () {
                                  if (isOnline) {
                                     Navigator.push(context, MaterialPageRoute(builder: (_) => MonitoringScreen(roomId: widget.elderId, targetSocketId: socketId)));
                                  } else {
                                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("設備離線中，無法觀看 CCTV")));
                                  }
                                }
                              ),
                            if (mode == 'comm')
                              IconButton(
                                icon: Icon(Icons.call, color: isOnline ? Colors.green : Colors.grey),
                                onPressed: () => _showCallTypeDialog(widget.elderId, socketId, isOnline: isOnline),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDeleteDevice(widget.elderId, socketId, name),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showCallTypeDialog(String roomId, String targetId, {bool isOnline = true}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isOnline ? "選擇通話類型" : "🚨 裝置目前離線"),
        content: Text(isOnline ? "一般通話將測試長輩接聽意願；緊急通話將強制開啟對方視訊畫面。" : "裝置目前無法連線。但您依然可以使用「緊急通話」或「一般通話」透過高優先級推播喚醒對方的設備。"),
        actions: [
          TextButton(
            child: const Text("一般通話"),
            onPressed: () {
              Navigator.pop(context);
              _initiateNormalCall(roomId, targetId);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("🚨 緊急通話", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(context);
              _initiateEmergencyCall(roomId, targetId);
            },
          )
        ],
      )
    );
  }

  void _confirmDeleteDevice(String roomId, String targetId, String deviceName) {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("移除設備"),
        content: Text("確定要強制登出並移除「$deviceName」嗎？此操作不可逆。"),
        actions: [
          TextButton(
            child: const Text("取消"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("刪除", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(context);
              _signaling.sendDeleteDevice(roomId, targetId);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已發送刪除指令給 $deviceName")));
            },
          )
        ],
      )
    );
  }

  void _initiateNormalCall(String roomId, String targetId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("正在呼叫長輩..."),
        content: const Text("等待長輩接聽中"),
        actions: [
          TextButton(
            child: const Text("取消", style: TextStyle(color: Colors.red)),
            onPressed: () {
              _signaling.sendCancelCall(roomId);
              Navigator.pop(dialogContext);
            },
          )
        ],
      ),
    );

    _signaling.onCallAcceptedByRemote = (accepterId) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(
          roomId: roomId,
          targetSocketId: accepterId,
          isIncomingCall: false, // We initiated, they accepted
          autoStart: true,
          isEmergency: false,
        )));
      }
    };

    _signaling.onCallBusy = (busyTargetId) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("對方忙線中或已拒絕")));
      }
    };

    _signaling.sendCallRequest(roomId);
  }

  void _initiateEmergencyCall(String roomId, String targetId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("發送緊急通話..."),
        content: const Text("正在強制喚醒長輩設備，請稍候..."),
        actions: [
          TextButton(
            child: const Text("取消", style: TextStyle(color: Colors.red)),
            onPressed: () {
              _signaling.sendCancelCall(roomId);
              Navigator.pop(dialogContext);
            },
          )
        ],
      ),
    );

    _signaling.onCallAcceptedByRemote = (accepterId) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(
          roomId: roomId,
          targetSocketId: accepterId,
          isIncomingCall: false,
          autoStart: true,
          isEmergency: true,
        )));
      }
    };

    _signaling.onCallBusy = (busyTargetId) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("對方忙線中或已拒絕")));
      }
    };

    _signaling.sendEmergencyCall(roomId);
  }
}