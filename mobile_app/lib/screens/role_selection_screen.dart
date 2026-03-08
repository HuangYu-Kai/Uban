// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'family_dashboard_screen.dart';
import 'elder_screen.dart';
import 'video_call_screen.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../globals.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isLoading = true; // 初始啟動時顯示讀取中，檢查本機快取
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndLogin();
  }

  Future<void> _checkPermissionsAndLogin() async {
    try {
      final canUseFullScreenIntent = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!canUseFullScreenIntent) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      print("Permission Action failed: $e");
    }
    
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    // ★ 檢查是否有背景背景廣播傳進來的 Emergency Call 狀態
    final pendingEmergencyRoom = prefs.getString('pending_emergency_room');
    final pendingEmergencySender = prefs.getString('pending_emergency_sender');
    if (pendingEmergencyRoom != null && pendingEmergencyRoom.isNotEmpty && pendingEmergencySender != null) {
      print("🚨 發現暫存的緊急呼叫！立即導向強制接聽畫面");
      // 清除，以免下次打開又觸發
      await prefs.remove('pending_emergency_room');
      await prefs.remove('pending_emergency_sender');
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              roomId: pendingEmergencyRoom,
              targetSocketId: pendingEmergencySender,
              isIncomingCall: true,
            ),
          ),
        );
        return;
      }
    }

    final savedRole = prefs.getString('saved_role');
    final savedId = prefs.getString('saved_id');
    
    if (savedRole != null && savedId != null) {
      if (savedRole == 'family') {
        List<dynamic> elders = await ApiService.getElderData(savedId);
        if (elders.isNotEmpty && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilyDashboardScreen(elders: elders)));
          
          if (pendingAcceptedCall != null) {
            final args = pendingAcceptedCall!;
            pendingAcceptedCall = null;
            Navigator.push(context, MaterialPageRoute(
              builder: (context) => VideoCallScreen(
                roomId: args['roomId']!,
                targetSocketId: args['senderId']!,
                isIncomingCall: true,
              ),
            ));
          }
          return;
        }
      } else if (savedRole == 'elder') {
        final deviceName = prefs.getString('saved_device_name') ?? '預設設備';
        final isCCTV = prefs.getBool('saved_is_cctv') ?? false;
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ElderScreen(
                roomId: savedId,
                isCCTVMode: isCCTV,
                deviceName: deviceName,
              ),
            ),
          );
          return;
        }
      }
    }
    // 如果沒有儲存的登入狀態或驗證失敗，顯示一般登入畫面
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    String inputText = _inputController.text.trim();
    if (inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入 ID')));
      return;
    }

    if (_selectedRole == 'family') {
      setState(() => _isLoading = true);
      List<dynamic> elders = await ApiService.getElderData(inputText);
      setState(() => _isLoading = false);

      if (elders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('查無資料')));
        return;
      }
      
      // ★ 登入成功，儲存狀態
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_role', 'family');
      await prefs.setString('saved_id', inputText);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilyDashboardScreen(elders: elders)));
      }
    } else {
      // 長輩邏輯
      String deviceName = "預設設備";
      TextEditingController nameCtrl = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('設備命名'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(hintText: '例如: 客廳、臥室'),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) deviceName = nameCtrl.text;
                Navigator.pop(context);
              },
              child: const Text('確定'),
            )
          ],
        ),
      );

      if (!mounted) return;
      bool? isCCTV = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('選擇模式'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.phone_in_talk),
              label: const Text('視訊通訊機'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.videocam),
              label: const Text('CCTV 監控機'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

      if (isCCTV == null) return;

      // ★ 登入成功，儲存狀態
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_role', 'elder');
      await prefs.setString('saved_id', inputText);
      await prefs.setString('saved_device_name', deviceName);
      await prefs.setBool('saved_is_cctv', isCCTV);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ElderScreen(
              roomId: inputText,
              isCCTVMode: isCCTV,
              deviceName: deviceName,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isRoleSelected = _selectedRole != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: isRoleSelected 
          ? AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => setState(() { _selectedRole = null; _inputController.clear(); })), backgroundColor: Colors.transparent, elevation: 0)
          : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.connect_without_contact, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text("Uban 系統入口", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),

              if (!isRoleSelected) ...[
                ElevatedButton.icon(icon: const Icon(Icons.visibility), label: const Text("我是家屬"), onPressed: () => setState(() => _selectedRole = 'family'), style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(60))),
                const SizedBox(height: 20),
                ElevatedButton.icon(icon: const Icon(Icons.elderly), label: const Text("我是長輩"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size.fromHeight(60)), onPressed: () => setState(() => _selectedRole = 'elder')),
              ],

              if (isRoleSelected) ...[
                Text(_selectedRole == 'family' ? "請輸入 User ID" : "請輸入 Elder ID"),
                const SizedBox(height: 20),
                TextField(controller: _inputController, decoration: const InputDecoration(border: OutlineInputBorder())),
                const SizedBox(height: 20),
                if (_isLoading) const CircularProgressIndicator() else ElevatedButton(onPressed: _handleSubmit, child: const Text("下一步")),
              ],
            ],
          ),
        ),
      ),
    );
  }
}