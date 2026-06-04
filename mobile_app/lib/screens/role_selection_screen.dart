// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'family_dashboard_screen.dart';
import 'elder_screen.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
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
    if (!kIsWeb) {
      try {
        final canUseFullScreenIntent = await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!canUseFullScreenIntent) {
          await FlutterCallkitIncoming.requestFullIntentPermission();
        }
      } catch (e) {
        debugPrint("Permission Action failed: $e");
      }
    }
    
    if (!kIsWeb) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
        Permission.notification,
        Permission.ignoreBatteryOptimizations,
      ].request();

      bool isCriticalDenied = false;
      if (statuses[Permission.notification] != PermissionStatus.granted) isCriticalDenied = true;
      if (statuses[Permission.ignoreBatteryOptimizations] != PermissionStatus.granted) isCriticalDenied = true;

      if (isCriticalDenied && mounted) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ 權限不足警告'),
            content: const Text('Uban 需要「通知」與「無限制電池(允許背景執行)」權限才能在鎖定畫面或背景成功接收緊急通話。若您拒絕這些權限，將無法正常收到來電。\n\n請前往系統設定中允許這些權限。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text('忽略並繼續 (不建議)'),
              ),
              ElevatedButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(context, true);
                },
                child: const Text('前往設定'),
              ),
            ],
          ),
        );
      }
    }

    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    // ★ 交由 ElderScreen 的 initState 來處理背景背景廣播傳進來的 Emergency Call 狀態，
    // 不再這裡越俎代庖直接 Push，這會導致掛斷時 Pop 找不到 Navigator 返回而黑屏 (Bug 10)。

    final savedRole = prefs.getString('saved_role');
    final savedId = prefs.getString('saved_id');
    
    if (savedRole != null && savedId != null) {
      if (savedRole == 'family') {
        appRole = 'family';
        List<dynamic> elders = await ApiService.getPairedElders(int.tryParse(savedId) ?? 0);
        if (elders.isNotEmpty && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilyDashboardScreen(elders: elders)));
          return;
        }
      } else if (savedRole == 'elder') {
        appRole = 'elder';
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

    if (_selectedRole == 'monitor') {
      setState(() => _isLoading = true);
      try {
        final result = await ApiService.resolveMonitorSetup(inputText);
        setState(() => _isLoading = false);
        if (result != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_role', 'elder'); // Monitor 屬於長輩端角色
          await prefs.setString('saved_id', result['elder_id'].toString());
          await prefs.setString('saved_device_name', result['device_name']);
          await prefs.setBool('saved_is_cctv', true);
          await prefs.setString('access_token', result['access_token']);
          appRole = 'elder';
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ElderScreen(
                  roomId: result['elder_id'].toString(),
                  isCCTVMode: true,
                  deviceName: result['device_name'],
                ),
              ),
            );
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('綁定碼無效或已過期')));
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('錯誤: $e')));
      }
    } else if (_selectedRole == 'family') {
      setState(() => _isLoading = true);
      List<dynamic> elders = await ApiService.getPairedElders(int.tryParse(inputText) ?? 0);
      setState(() => _isLoading = false);

      if (elders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('查無資料')));
        return;
      }
      
      // ★ 登入成功，儲存狀態
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_role', 'family');
      await prefs.setString('saved_id', inputText);
      appRole = 'family';

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

      // ★ 自動決定設備角色（不需資料庫欄位、不需手動選擇）：
      //   詢問後端該長輩是否已存在「通話機」。已有 → 本設備自動成為「監控機」。
      final bool isMonitor = await ApiService.hasCommDevice(inputText);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_role', 'elder');
      await prefs.setString('saved_id', inputText);
      await prefs.setString('saved_device_name', deviceName);
      await prefs.setBool('saved_is_cctv', isMonitor);
      appRole = 'elder';

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ElderScreen(
              roomId: inputText,
              isCCTVMode: isMonitor,
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
                const SizedBox(height: 20),
                ElevatedButton.icon(icon: const Icon(Icons.videocam), label: const Text("我是監控設備"), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, minimumSize: const Size.fromHeight(60)), onPressed: () => setState(() => _selectedRole = 'monitor')),
              ],

              if (isRoleSelected) ...[
                Text(_selectedRole == 'family' ? "請輸入 User ID" : _selectedRole == 'monitor' ? "請輸入 6 位數綁定碼" : "請輸入 Elder ID"),
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