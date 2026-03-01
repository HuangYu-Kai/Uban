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

                    return Card(
                      child: ListTile(
                        leading: Icon(mode == 'cctv' ? Icons.videocam : Icons.phone_in_talk, color: mode == 'cctv' ? Colors.red : Colors.green),
                        title: Text(name),
                        subtitle: Text(mode == 'cctv' ? "監控模式" : "通訊模式"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mode == 'cctv')
                              IconButton(
                                icon: const Icon(Icons.videocam, color: Colors.blue),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MonitoringScreen(roomId: widget.elderId, targetSocketId: socketId))),
                              ),
                            if (mode == 'comm')
                              IconButton(
                                icon: const Icon(Icons.call, color: Colors.green),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoCallScreen(
                                  roomId: widget.elderId,
                                  targetSocketId: socketId,
                                  isIncomingCall: false,
                                ))),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}