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
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 頂部日期 (Header) - 增加漸層背景質感
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.1),
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
                              color: Colors.grey[700],
                            ),
                          ),
                          // 使用 FittedBox 避免字太大的時候爆版 (黃黑條紋)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              dateStr,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 80,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF333333),
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16), // 間距
                    // Right Side: Weather (Animated)
                    Column(
                      children: [
                        const FaIcon(
                              FontAwesomeIcons.sun,
                              color: Colors.orange,
                              size: 48,
                            )
                            .animate(
                              onPlay: (controller) => controller.repeat(),
                            )
                            .rotate(duration: 4000.ms),
                        const SizedBox(height: 8),
                        Text(
                          '24°C',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),

              const SizedBox(height: 32),

              // 2. 農曆日期 (取代原本的週曆)
              Center(
                child: Text(
                  '${lunar.getYearInGanZhi()}年 ${lunar.getMonthInChinese()}月 ${lunar.getDayInChinese()}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 36, // 大字體
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF8D6E63),
                    letterSpacing: 2.0,
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),

              // 3. 功能區 (Features)
              Expanded(
                child: Column(
                  children: [
                    // A. 老友廣播站 (Retro Radio Style)
                    Expanded(flex: 3, child: _buildRadioCard(context)),
                    const SizedBox(height: 20),
                    // B. 通訊錄 & AI (Photo Frame & Character)
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

  // 📻 復古收音機卡片
  Widget _buildRadioCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RadioStationScreen()),
      ),
      child:
          Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFD87836), // 復古橘
                  borderRadius: BorderRadius.circular(36),
                  // 擬物化紋理 (Gradient)
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE88A4A), Color(0xFFC46221)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD87836).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // 喇叭網孔紋理 (裝飾)
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Icon(
                        Icons.speaker,
                        size: 180,
                        color: Colors.black.withOpacity(0.05),
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
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.5),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'ON AIR',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
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
                                size: 40,
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '老友廣播站',
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '點擊收聽大家的故事',
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 16,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.02, duration: 2000.ms), // 呼吸效果
    );
  }

  // 🖼️ 數位相框 (通訊錄)
  Widget _buildContactsCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ContactsScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF8D6E63), width: 8), // 木質邊框感
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 模擬照片背景 (淺灰)
              Container(color: Colors.grey[100]),
              // 示意圖示
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.solidAddressBook,
                      size: 40,
                      color: Color(0xFF8D6E63),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '找家人',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF5D4037),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.2, end: 0),
    );
  }

  // 🤖 AI 貼心陪聊 (Character)
  Widget _buildAICard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AIChatScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFCC80),
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFCC80), Color(0xFFFFB74D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 10),
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
                        size: 50,
                        color: Colors.white,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .shake(delay: 2000.ms, duration: 500.ms),
                  const SizedBox(height: 8),
                  Text(
                    '貼心陪聊',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.2, end: 0),
    );
  }
}
