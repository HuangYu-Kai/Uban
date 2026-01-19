import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ElderPairingScreen extends StatefulWidget {
  const ElderPairingScreen({super.key});

  @override
  State<ElderPairingScreen> createState() => _ElderPairingScreenState();
}

class _ElderPairingScreenState extends State<ElderPairingScreen> {
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _speakWelcomeMessage();
  }

  Future<void> _speakWelcomeMessage() async {
    // 設定語言為繁體中文
    await flutterTts.setLanguage("zh-TW");
    // 調整語速與音調 (可依需求調整)
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);

    // 播放歡迎語
    await flutterTts.speak("歡迎加入，請將此畫面秀給家人看");
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 背景色
      body: SafeArea(
        child: SingleChildScrollView(
          // 避免小螢幕溢出
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 48), // 頂部間距
                // 標題: 歡迎加入！
                Text(
                  '歡迎加入！',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 40),

                // 提示文字: 請將此畫面秀給家人看
                Text(
                  '請將此畫面秀給家人看',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                ),

                const SizedBox(height: 48),

                // 配對碼卡片 (橘色背景)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAB60), // 卡片橘色
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 配對碼: 0 8 2 0
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildCodeDigit('0'),
                          const SizedBox(width: 16),
                          _buildCodeDigit('8'),
                          const SizedBox(width: 16),
                          _buildCodeDigit('2'),
                          const SizedBox(width: 16),
                          _buildCodeDigit('0'),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // 文字: 4 位數配對碼
                      Text(
                        '4 位數配對碼',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // QR Code
                Container(
                  padding: const EdgeInsets.all(12), // 白邊
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: '0820', // TODO: 替換為實際配對碼連結或資料
                    version: QrVersions.auto,
                    size: 160.0,
                    backgroundColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 48),

                // 返回按鈕
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: Icon(Icons.arrow_back, color: Colors.grey[600]),
                    label: Text(
                      '返回',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 建構單個配對碼數字 (帶底線)
  Widget _buildCodeDigit(String digit) {
    return Column(
      children: [
        Text(
          digit,
          style: GoogleFonts.inter(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Container(width: 48, height: 4, color: Colors.white),
      ],
    );
  }
}
