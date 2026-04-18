// lib/screens/socketio_test_screen.dart
// SocketIO 通話測試專用頁面

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/signaling.dart';
import 'video_call_screen.dart';

class SocketIOTestScreen extends StatefulWidget {
  const SocketIOTestScreen({super.key});

  @override
  State<SocketIOTestScreen> createState() => _SocketIOTestScreenState();
}

class _SocketIOTestScreenState extends State<SocketIOTestScreen> {
  final Signaling _signaling = Signaling();
  final TextEditingController _roomIdController =
      TextEditingController(text: '17');

  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusMessage = '尚未連線';
  String _selectedRole = 'elder'; // elder 或 family
  final List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _setupSignalingCallbacks();
  }

  void _setupSignalingCallbacks() {
    // 收到來電請求
    _signaling.onCallRequest = (roomId, senderId, callId) {
      _addLog('📞 收到來電！Room: $roomId, Sender: $senderId');
      _showIncomingCallDialog(roomId, senderId, callId);
    };

    // 收到緊急通話
    _signaling.onEmergencyCall = (roomId, senderId, callId) {
      _addLog('🚨 緊急來電！Room: $roomId, Sender: $senderId');
      _showIncomingCallDialog(roomId, senderId, callId, isEmergency: true);
    };

    // 收到取消通話
    _signaling.onCancelCall = (roomId, senderId, callId) {
      _addLog('🔕 來電已取消');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('對方已取消通話')),
        );
      }
    };

    // 設備列表更新
    _signaling.onElderDevicesUpdate = (devices) {
      _addLog('📡 設備列表更新: ${devices.length} 台設備');
      for (var d in devices) {
        _addLog('   - ${d['deviceName']} (${d['isOnline'] ? '在線' : '離線'})');
      }
    };
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, {'time': timeStr, 'message': message});
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId,
      {bool isEmergency = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isEmergency ? Icons.warning : Icons.phone,
              color: isEmergency ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(isEmergency ? '🚨 緊急來電' : '📞 來電'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('房間: $roomId'),
            Text('發話者: $senderId'),
            if (callId != null) Text('CallID: ${callId.substring(0, 8)}...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _signaling.sendCallBusy(senderId);
              _addLog('❌ 已拒接');
            },
            child: const Text('拒接', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _signaling.sendCallAccept(senderId, callId: callId);
              _addLog('✅ 已接聽，準備進入視訊...');

              // 進入視訊通話畫面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => VideoCallScreen(
                    roomId: roomId,
                    targetSocketId: senderId,
                    autoStart: false,
                  ),
                ),
              );
            },
            child: const Text('接聽'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入房間號')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = '正在連線...';
    });

    _addLog('🔌 連線中... Room: $roomId, Role: $_selectedRole');

    try {
      _signaling.connect(
        roomId,
        _selectedRole,
        deviceName: 'TestDevice_$_selectedRole',
        deviceMode: 'comm',
      );

      // 等待連線
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _statusMessage = '已連線 ✅\nRoom: $roomId\nRole: $_selectedRole';
      });
      _addLog('✅ 連線成功！等待來電...');
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '連線失敗: $e';
      });
      _addLog('❌ 連線失敗: $e');
    }
  }

  void _disconnect() {
    _signaling.forceDisconnect();
    setState(() {
      _isConnected = false;
      _statusMessage = '已斷線';
    });
    _addLog('🔌 已斷線');
  }

  void _sendTestCall() {
    final roomId = _roomIdController.text.trim();
    _signaling.sendCallRequest(roomId, role: _selectedRole);
    _addLog('📞 已發送 call-request 到房間 $roomId');
  }

  @override
  void dispose() {
    _signaling.onCallRequest = null;
    _signaling.onEmergencyCall = null;
    _signaling.onCancelCall = null;
    _signaling.onElderDevicesUpdate = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('SocketIO 測試', style: GoogleFonts.notoSansTc()),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 連線狀態卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? '已連線' : '未連線',
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      style: GoogleFonts.notoSansTc(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 設定區
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '連線設定',
                      style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 房間號輸入
                    TextField(
                      controller: _roomIdController,
                      decoration: InputDecoration(
                        labelText: '房間號 (長輩的 user_id)',
                        hintText: '例如: 17',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('房間號說明'),
                                content: const Text(
                                  '房間號 = 長輩的 user_id\n\n'
                                  '不是 elder_id！\n\n'
                                  '測試用房間號：17',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('了解'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),

                    const SizedBox(height: 16),

                    // 角色選擇
                    Text('角色',
                        style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('長輩'),
                            value: 'elder',
                            groupValue: _selectedRole,
                            onChanged: _isConnected
                                ? null
                                : (v) => setState(() => _selectedRole = v!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('家屬'),
                            value: 'family',
                            groupValue: _selectedRole,
                            onChanged: _isConnected
                                ? null
                                : (v) => setState(() => _selectedRole = v!),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 連線按鈕
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                                _isConnected ? Icons.link_off : Icons.link),
                            label: Text(_isConnected ? '斷線' : '連線'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isConnected ? Colors.red : Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _isConnecting
                                ? null
                                : (_isConnected ? _disconnect : _connect),
                          ),
                        ),
                        if (_isConnected) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.phone),
                            label: const Text('發話'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                            ),
                            onPressed: _sendTestCall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 日誌區
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '事件日誌',
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _logs.clear()),
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _logs.isEmpty
                          ? Center(
                              child: Text(
                                '尚無日誌',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '[${log['time']}] ${log['message']}',
                                    style: GoogleFonts.notoSansTc(fontSize: 12),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 測試說明
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          '測試步驟',
                          style: GoogleFonts.notoSansTc(
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 輸入房間號 (例如: 17)\n'
                      '2. 選擇角色為「長輩」\n'
                      '3. 點擊「連線」\n'
                      '4. 在電腦執行:\n'
                      '   python test_call_simulator.py 17\n'
                      '5. 選擇 [1] 發送通話請求\n'
                      '6. 此頁面會彈出來電對話框',
                      style: GoogleFonts.notoSansTc(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
