import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'login_screen.dart';
import 'elder_pairing_screen.dart';

// 身分選擇畫面
class IdentificationScreen extends StatelessWidget {
  const IdentificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 背景色 (從 Mockup 取樣)
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 60), // 頂部間距
              // 標題: CompanionFlow
              Text(
                'CompanionFlow',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[600],
                ),
              ),

              const Spacer(flex: 2), // 彈性間距
              // 歡迎文字: 早安，今天想聊什麼？
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: '早安，\n今天'),
                    TextSpan(
                      text: '想聊什麼',
                      style: TextStyle(
                        color: const Color(0xFFFF9F69), // 橘色強調
                      ),
                    ),
                    const TextSpan(text: '？'),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // 我是長輩按鈕
              Expanded(
                flex: 5,
                child: Center(
                  child: InkWell(
                    onTap: () {
                      // 導向長輩配對畫面
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ElderPairingScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(
                        maxWidth: 320,
                        maxHeight: 360,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB673), // 按鈕橘色背景
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: Colors.black12, width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 笑臉圖示
                          const Center(
                            child: FaIcon(
                              FontAwesomeIcons.faceLaugh,
                              size: 100,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 按鈕文字
                          Text(
                            '我是長輩\n(點我聊天)',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // 家屬 / 照護者登入
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
                child: Text(
                  '家屬 / 照護者登入',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 48), // 底部間距
            ],
          ),
        ),
      ),
    );
  }
}
