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

      setState(() {
        _pairingCode = result['pairing_code'];
        _secondsLeft = result['expires_in_seconds'] ?? 600;
        _isLoading = false;
      });
      _startStatusPolling();
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
        final status = await ApiService.checkPairingStatus(_pairingCode!);
        if (!mounted) return;

        if (status['status'] == 'paired') {
          timer.cancel();

          // 核心修復：持久化儲存長輩 ID 與姓名
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('caregiver_id', status['elder_id']);
          await prefs.setString('caregiver_name', status['elder_name'] ?? '長輩');

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
