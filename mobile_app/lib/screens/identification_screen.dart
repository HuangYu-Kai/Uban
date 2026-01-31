import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'elder_pairing_screen.dart';
import 'family_main_screen.dart';
// Note: origin/main suggested LoginScreen, but we are using FamilyMainScreen for the family UI flow.
// import 'login_screen.dart';

class IdentificationScreen extends StatelessWidget {
  const IdentificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 動態背景層
          _buildAnimatedBackground(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // 標誌與品牌名
                  _buildBrandHeader(),

                  const Spacer(flex: 2),

                  // 問候語 (Hero Text)
                  _buildHeroGreeting(),

                  const SizedBox(height: 60),

                  // 核心入口：我是長輩
                  _buildElderEntryCard(context),

                  const Spacer(flex: 3),

                  // 家屬入口
                  _buildFamilyEntryLink(context),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF9F2), // 極淺暖色調
      ),
      child: Stack(
        children: [
          // 左上角的模糊裝飾
          Positioned(
                top: -100,
                left: -50,
                child: _buildBlurCircle(
                  300,
                  const Color(0xFFFFCCBC).withValues(alpha: 0.4),
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .moveY(
                begin: 0,
                end: 50,
                duration: 4.seconds,
                curve: Curves.easeInOut,
              ),

          // 右下角的模糊裝飾
          Positioned(
                bottom: -50,
                right: -50,
                child: _buildBlurCircle(
                  250,
                  const Color(0xFFFFAB91).withValues(alpha: 0.3),
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .moveX(
                begin: 0,
                end: -30,
                duration: 5.seconds,
                curve: Curves.easeInOut,
              ),
        ],
      ),
    );
  }

  Widget _buildBlurCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ColorFilter.mode(color, BlendMode.srcATop),
          child: Container(),
        ),
      ),
    ).animate().fadeIn(duration: 1.seconds);
  }

  Widget _buildBrandHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF7043),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const FaIcon(
            FontAwesomeIcons.umbrella,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'UBan',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2D2D2D),
            letterSpacing: 1.2,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildHeroGreeting() {
    return Column(
          children: [
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.notoSansTc(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF2D2D2D),
                  height: 1.3,
                ),
                children: [
                  const TextSpan(text: '早安，\n今天要'),
                  TextSpan(
                    text: '聊什麼',
                    style: const TextStyle(color: Color(0xFFFF7043)),
                  ),
                  const TextSpan(text: '？'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您的專屬 AI 陪伴夥伴已經準備好了',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          ],
        )
        .animate()
        .fadeIn(delay: 400.ms)
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }

  Widget _buildElderEntryCard(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ElderPairingScreen()),
        );
      },
      child:
          Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 340),
                height: 280,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // 背景圖案飾紋
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: FaIcon(
                        FontAwesomeIcons.quoteRight,
                        size: 150,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const FaIcon(
                                FontAwesomeIcons.heartPulse,
                                size: 80,
                                color: Colors.white,
                              )
                              .animate(onPlay: (c) => c.repeat())
                              .scale(
                                duration: 1.5.seconds,
                                curve: Curves.easeInOut,
                              ),

                          const SizedBox(height: 32),
                          Text(
                            '我是長輩',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '點擊進入聊天室',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                begin: 0,
                end: -10,
                duration: 2.seconds,
                curve: Curves.easeInOut,
              ),
    ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildFamilyEntryLink(BuildContext context) {
    return Column(
      children: [
        Text(
          '或者是...',
          style: GoogleFonts.notoSansTc(color: Colors.grey[400], fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FamilyMainScreen()),
            );
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            side: BorderSide(color: Colors.grey[300]!, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white.withValues(alpha: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.userShield,
                size: 16,
                color: Colors.grey[700],
              ),
              const SizedBox(width: 12),
              Text(
                '家屬 / 照護者入口',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 800.ms);
  }
}
