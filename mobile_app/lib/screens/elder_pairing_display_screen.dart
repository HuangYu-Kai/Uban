import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'elder_home_screen.dart';
import 'dart:async';

class ElderPairingDisplayScreen extends StatefulWidget {
  const ElderPairingDisplayScreen({super.key});

  @override
  State<ElderPairingDisplayScreen> createState() =>
      _ElderPairingDisplayScreenState();
}

class _ElderPairingDisplayScreenState extends State<ElderPairingDisplayScreen> {
  static const bool _devBypassLogin = bool.fromEnvironment(
    'DEV_BYPASS_LOGIN',
    defaultValue: false,
  );
  static const int _devBypassUserId = int.fromEnvironment(
    'DEV_BYPASS_USER_ID',
    defaultValue: 1,
  );
  static const String _devBypassUserName = String.fromEnvironment(
    'DEV_BYPASS_USER_NAME',
    defaultValue: 'TestElder',
  );

  String? _pairingCode;
  int _secondsLeft = 0;
  bool _isLoading = true;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _requestNewCode();
  }

  Future<void> _requestNewCode() async {
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.requestPairingCode();
      if (!mounted) return;

// 檢查 API 是否回傳錯誤
      if (result['status'] == 'error') {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'API 錯誤：${result['message'] ?? result['error'] ?? '未知錯誤'}')),
        );
        return;
      }

// 從 API Response 的 data 欄位取得配對碼
      final data = result['data'] as Map<String, dynamic>?;

      setState(() {
        _pairingCode = data?['pairing_code'];
        _secondsLeft = data?['expires_in_seconds'] ?? 600;
        _isLoading = false;
      });

      if (_pairingCode != null) {
        _startStatusPolling();
      } else {
        // 顯示更詳細的錯誤資訊
        final errorDetail = result.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法取得配對碼：$errorDetail')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('申請代碼失敗：$e')));
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_pairingCode == null) return;
      try {
        final result = await ApiService.checkPairingStatus(_pairingCode!);
        if (!mounted) return;

// 從 API Response 的 data 欄位取得配對狀態
        final status = result['data'] as Map<String, dynamic>?;
        if (status == null) return;

        if (status['status'] == 'paired') {
          timer.cancel();

          // 核心修復：持久化儲存長輩 ID、姓名與角色
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('caregiver_id', status['elder_id']);
          await prefs.setString('caregiver_name', status['elder_name'] ?? '長輩');
          await prefs.setString('user_role', 'elder');

          if (!mounted) return;

// 跳轉至長輩首頁
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (c) => ElderHomeScreen(
                userId: status['elder_id'],
                userName: status['elder_name'] ?? '長輩',
              ),
            ),
          );
        }
      } catch (e) {
// 靜默處理
      }
    });
  }

  Future<void> _quickLoginSameElder() async {
    final prefs = await SharedPreferences.getInstance();
    int? elderId;
    String? elderName;
    String? role;

    // 開發模式：固定使用同一個測試長輩帳號（不依賴 SharedPreferences 是否被清空）
    if (_devBypassLogin) {
      elderId = _devBypassUserId > 0 ? _devBypassUserId : 1;
      elderName =
          _devBypassUserName.isNotEmpty ? _devBypassUserName : 'TestElder';
      await prefs.setInt('caregiver_id', elderId);
      await prefs.setString('caregiver_name', elderName);
      await prefs.setString('user_role', 'elder');
      role = 'elder';
    } else {
      elderId = prefs.getInt('caregiver_id');
      elderName = prefs.getString('caregiver_name');
      role = prefs.getString('user_role');
    }

    if (!mounted) return;

    if (elderId == null || elderName == null || role != 'elder') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未找到可快速登入的長輩帳號，請先完成一次配對')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ElderHomeScreen(userId: elderId!, userName: elderName!),
      ),
    );
  }

  Future<void> _quickLoginYuxuanDemo() async {
    try {
      final result = await ApiService.ensureYuxuanDemoElder();
      if (!mounted) return;

      if (result['status'] == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(result['message'] ?? result['error'] ?? '宇璿帳號建立失敗')),
        );
        return;
      }

      final data = result['data'] as Map<String, dynamic>?;
      final rawElderId = data?['elder_user_id'];
      final elderId =
          rawElderId is int ? rawElderId : int.tryParse('${rawElderId ?? ''}');
      final elderName = (data?['elder_name'] ?? '宇璿').toString();
      if (elderId == null || elderId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('宇璿帳號建立成功，但登入資料不完整')),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('caregiver_id', elderId);
      await prefs.setString('caregiver_name', elderName);
      await prefs.setString('user_role', 'elder');
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ElderHomeScreen(userId: elderId, userName: elderName),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入宇璿失敗：$e')),
      );
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 100,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '等待家人配對',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '請子女開啟手機上的 UBan App\n並輸入下方的 4 位數配對碼',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 48),
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else if (_pairingCode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            child: Text(
                              _pairingCode!,
                              style: GoogleFonts.inter(
                                fontSize: 72,
                                fontWeight: FontWeight.w900,
                                color: Colors.orange,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          QrImageView(
                            data: _pairingCode!,
                            version: QrVersions.auto,
                            size: 160.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '倒數: $_secondsLeft 秒',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 48),
                  TextButton(
                    onPressed: _requestNewCode,
                    child: const Text('更換代碼', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _quickLoginSameElder,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_devBypassLogin ? '快速登入固定測試長輩' : '快速登入同一長輩'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF59B294),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _quickLoginYuxuanDemo,
                    icon: const Icon(Icons.elderly_rounded),
                    label: const Text('登入宇璿（64歲）'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D78),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
