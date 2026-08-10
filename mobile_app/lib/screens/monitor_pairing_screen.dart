// lib/screens/monitor_pairing_screen.dart
// ★ issue 7：監視器角色 - 透過家屬產生的 6 位數綁定碼，自動配對到家屬指定的長輩
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../globals.dart';
import 'elder_screen.dart';

class MonitorPairingScreen extends StatefulWidget {
  const MonitorPairingScreen({super.key});

  @override
  State<MonitorPairingScreen> createState() => _MonitorPairingScreenState();
}

class _MonitorPairingScreenState extends State<MonitorPairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 6 位數綁定碼')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.resolveMonitorSetup(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result == null) {
      // ★ 2026-08-10 第二十輪：優先顯示後端回傳的具體原因（綁定碼不存在／已過期／連線失敗），
      //   查無具體原因時才退回原本的通用提示文字。
      final String errorMsg =
          ApiService.lastResolveError ?? '綁定碼無效或已過期，請向家屬確認後重新輸入';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return;
    }

    // ★ 持久化登入狀態，與一般長輩端設備使用相同的 SharedPreferences 欄位，
    //   確保 App 重啟後 splash_screen 能正確還原為監控機模式
    final prefs = await SharedPreferences.getInstance();
    final int elderUserId = result['elder_user_id'] is int
        ? result['elder_user_id']
        : int.tryParse('${result['elder_user_id']}') ?? 0;
    final String elderId = result['elder_id'].toString();
    final String elderName = (result['elder_name'] ?? '長輩').toString();
    final String deviceName = (result['device_name'] ?? '監控設備').toString();

    await prefs.setInt('caregiver_id', elderUserId);
    await prefs.setString('caregiver_name', elderName);
    await prefs.setString('user_role', 'elder');
    await prefs.setString('elder_room_id', elderId);
    await prefs.setString('saved_device_name', deviceName);
    await prefs.setBool('saved_is_cctv', true);
    if (result['access_token'] != null) {
      await prefs.setString('access_token', result['access_token'].toString());
    }
    appRole = 'elder';

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: elderId,
          isCCTVMode: true,
          deviceName: deviceName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_rounded, size: 80, color: Colors.grey),
                const SizedBox(height: 24),
                Text(
                  '設定監控設備',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '請向家屬索取「新增監控設備」產生的 6 位數綁定碼，\n輸入後即可自動配對至家屬指定的長輩',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(),
                    hintText: '------',
                  ),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submitCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF59B294),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('開始監控', style: TextStyle(fontSize: 18)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
