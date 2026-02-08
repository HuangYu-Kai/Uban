import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'elder_home_screen.dart';
import '../services/api_service.dart';

class ElderPairingScreen extends StatefulWidget {
  const ElderPairingScreen({super.key});

  @override
  State<ElderPairingScreen> createState() => _ElderPairingScreenState();
}

class _ElderPairingScreenState extends State<ElderPairingScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _speakWelcomeMessage();
  }

  Future<void> _speakWelcomeMessage() async {
    await flutterTts.setLanguage("zh-TW");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    await flutterTts.speak("歡迎加入，請輸入家人提供的四位數配對碼");
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text;
    if (code.length != 4) {
      setState(() => _errorMessage = '請輸入 4 位數字');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 演示用：我們先註冊一個 Elder ID = 1 (真實環境應從登入狀態取得)
      final result = await ApiService.verifyPairingCode(1, code);

      if (result.containsKey('error')) {
        setState(() => _errorMessage = result['error']);
      } else {
        // 配對成功！
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('配對成功！正在準備您的專屬空間...')));

          final navigator = Navigator.of(context);
          Future.delayed(const Duration(seconds: 1), () {
            navigator.pushReplacement(
              MaterialPageRoute(builder: (context) => const ElderHomeScreen()),
            );
          });
        }
      }
    } catch (e) {
      setState(() => _errorMessage = '連線失敗，請確認後端是否啟動');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 48),
                Text(
                  '歡迎加入 UBan！',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  '請輸入配對碼',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 48),

                // 配對碼輸入區域
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAB60),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 16,
                        ),
                        decoration: const InputDecoration(
                          hintText: '0000',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(width: 160, height: 4, color: Colors.white),
                      const SizedBox(height: 24),
                      Text(
                        '請輸入家人提供的 4 位數字',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                // 驗證按鈕
                SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 8,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            '開始配對',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 40),

                // 按鈕列 (返回 & 跳過)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.grey[600]),
                      label: Text(
                        '返回',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ElderHomeScreen(),
                          ),
                        );
                      },
                      child: Text(
                        '測試跳過 >>',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
