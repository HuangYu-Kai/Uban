import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
// ignore: depend_on_referenced_packages
import 'package:intl/date_symbol_data_local.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lunar/lunar.dart';

import 'contacts_screen.dart';
import 'ai_chat_screen.dart';
import 'radio_station_screen.dart';
import 'weather_screen.dart';

// 長輩首頁 V2 (Polish & Engagement)
class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({super.key});

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('zh_TW', null);
    _speakWelcome();
  }

  Future<void> _speakWelcome() async {
    await flutterTts.setLanguage("zh-TW");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak("爺爺早安，今天要不要聽聽老歌？");
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 獲取當前日期
    final DateTime now = DateTime.now();
    final String dateStr = DateFormat('M月d日', 'zh_TW').format(now);
    final String weekdayStr = DateFormat('EEEE', 'zh_TW').format(now);

    // 獲取農曆日期
    final Lunar lunar = Lunar.fromDate(now);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1), // 溫馨米黃 (Warm Amber)
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 頂部日期 (Header)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFA726), Color(0xFFFF7043)], // 暖橘漸層
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center, // 垂直置中
                  children: [
                    // Left Side: Date (Expanded to take available space)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            weekdayStr,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9), // 白字
                            ),
                          ),
                          // 使用 FittedBox 避免字太大的時候爆版
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              dateStr,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 80,
                                fontWeight: FontWeight.bold,
                                color: Colors.white, // 白字
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16), // 間距
                    // 天氣 (Button Style)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WeatherScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3), // 橘色邊框
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.cloudSun,
                              color: Colors.deepOrange, // 深橘色圖示
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '24°C',
                                style: GoogleFonts.inter(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            Text(
                              '看氣象',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),

              const SizedBox(height: 32),

              // 2. 農曆日期
              Center(
                child: Text(
                  '${lunar.getYearInGanZhi()}年 ${lunar.getMonthInChinese()}月 ${lunar.getDayInChinese()}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 36, // 大字體
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5D4037), // 深褐色
                    letterSpacing: 2.0,
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),

              // 3. 功能區 (Features)
              Expanded(
                child: Column(
                  children: [
                    // A. 老友廣播站 (Coral Style)
                    Expanded(flex: 3, child: _buildRadioCard(context)),
                    const SizedBox(height: 20),
                    // B. 通訊錄 & AI
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(child: _buildContactsCard(context)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildAICard(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 📻 復古收音機卡片 (Coral Theme)
  Widget _buildRadioCard(BuildContext context) {
    return _buildElderTouchable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RadioStationScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFF7043), // 復古橘
          borderRadius: BorderRadius.circular(36),
          // 擬物化紋理 (Gradient)
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8A65), Color(0xFFFF5722)], // 橘紅漸層
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7043).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 喇拔網孔紋理 (裝飾)
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.speaker,
                size: 200, // 加大
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ON AIR 燈號
                  Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Text(
                          'ON AIR',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16, // 加大
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fade(duration: 1000.ms),

                  const Spacer(),

                  Row(
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.radio,
                        color: Colors.white,
                        size: 60, // 加大
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '老友廣播站',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 48, // 加大
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '點擊收聽大家的故事',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 32, // 加大
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🖼️ 數位相框 (通訊錄) - Coral Theme
  Widget _buildContactsCard(BuildContext context) {
    return _buildElderTouchable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ContactsScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFD54F), // 溫暖黃
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFECB3), Color(0xFFFFD54F)], // 淡黃 -> 暖黃
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 示意圖示
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.solidAddressBook,
                      size: 60, // 加大
                      color: Color(0xFF5D4037), // 深棕色
                    ),
                    const SizedBox(height: 16),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '找家人',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 36, // 加大
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF5D4037), // 深棕色
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🤖 AI 貼心陪聊 (Character) - Coral Theme
  Widget _buildAICard(BuildContext context) {
    return _buildElderTouchable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AIChatScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFCC80), // 淺橘
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFCC80), Color(0xFFFFB74D)], // 淺橘漸層
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.2),
              blurRadius: 10,
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 眨眼動畫
                  const FaIcon(
                        FontAwesomeIcons.robot,
                        size: 60, // 加大
                        color: Colors.white,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .shake(delay: 2000.ms, duration: 500.ms),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '貼心陪聊',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 36, // 加大
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for touchable cards with scale feedback
  Widget _buildElderTouchable({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: child
          .animate(
            onPlay: (c) => c.stop(),
          ) // Animation is triggered by external events or manually
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(0.95, 0.95),
            duration: 100.ms,
            curve: Curves.easeInOut,
          ),
    );
  }
}
