// lib/screens/monitor_pairing_screen.dart
// ★ issue 7：監視器角色 - 透過家屬產生的 6 位數綁定碼，自動配對到家屬指定的長輩
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../globals.dart';
import 'elder_screen.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';

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
    // ★ 必須用 pushAndRemoveUntil 清空堆疊，理由同 role_selection_screen.dart／
    //   elder_pairing_display_screen.dart 的說明：本畫面是從 IdentificationScreen
    //   用 Navigator.push 進來的，若在此僅 pushReplacement，IdentificationScreen
    //   會留在 ElderScreen 底下；監控機模式的長輩在通話畫面內掛斷時，
    //   globals.dart::safeNavigateBack 會 pop 優先而誤降落在身分選擇頁。
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: elderId,
          isCCTVMode: true,
          deviceName: deviceName,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const UbanTopBar(title: '設定監控設備'),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: UbanMarkBox(
                      size: 72,
                      radius: 22,
                      color: c.surface2,
                      child:
                          Icon(Icons.videocam_outlined, size: 38, color: c.text2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '請在家屬的手機上開啟「新增監控設備」，把畫面上的 6 位數號碼輸入到下方。',
                    style: ubanBody(context),
                  ),
                  const SizedBox(height: 20),
                  _buildCodeField(c),
                  const SizedBox(height: 20),
                  UbanButton(
                    label: '開始監控',
                    size: UbanButtonSize.xl,
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _submitCode,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 設計稿 `.idinput`：置中、Poppins 42、字距 .3em、高 84。
  /// 展示用大字（≥40pt）固定字級，不隨系統字級放大，避免 6 碼擠出欄位。
  Widget _buildCodeField(UbanColors c) {
    final radius = BorderRadius.circular(18);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('6 位數設定碼',
            style: ubanText(15, FontWeight.w700, c.text2)),
        const SizedBox(height: 6),
        MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            cursorColor: c.brand,
            style: ubanBrandText(42, FontWeight.w600, c.text)
                .copyWith(letterSpacing: 42 * .3, height: 1.1),
            decoration: InputDecoration(
              counterText: '',
              hintText: '------',
              hintStyle: ubanBrandText(42, FontWeight.w600, c.text3)
                  .copyWith(letterSpacing: 42 * .3, height: 1.1),
              filled: true,
              fillColor: c.surface,
              constraints: const BoxConstraints(minHeight: 84),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: border(c.line),
              enabledBorder: border(c.line),
              focusedBorder: border(c.brand),
            ),
          ),
        ),
      ],
    );
  }
}
