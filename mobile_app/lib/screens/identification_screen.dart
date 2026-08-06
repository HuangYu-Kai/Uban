import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import 'family_main_screen.dart';
import 'elder_pairing_display_screen.dart';
import 'login_screen.dart';
import 'monitor_pairing_screen.dart'; // ★ issue 7：監視器角色
class IdentificationScreen extends StatelessWidget {
  const IdentificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  // "誰在使用？" Title
                  Text(
                    '誰在使用？',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 32, // Reduced from 40 to prevent overflow
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF59B294),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 32), // Reduced from 48
                  // Cards Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 800,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                            children: [
                              // Elder Card
                              Expanded(
                                child: _buildRoleCard(
                                  context: context,
                                  label: '我是長者',
                                  imagePath: 'assets/images/elder_illustration.png',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ElderPairingDisplayScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 16), // Reduced from 24
                              // Caregiver Card
                              Expanded(
                                child: _buildRoleCard(
                                  context: context,
                                  label: '我是家屬 / 照護者',
                                  imagePath:
                                      'assets/images/family_illustration.png',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const LoginScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // ★ issue 7：監視器設備文字（移除圖示，居中放置）
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MonitorPairingScreen(),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                '我是監控設備',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 14, // Reduced from 16
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF4A4A4A),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32), // Reduced from 48
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String label,
    String? imagePath,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: imagePath == null ? const Color(0xFFF1F5F9) : null,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                image: imagePath != null
                    ? DecorationImage(
                        image: AssetImage(imagePath),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imagePath == null
                  ? Icon(icon, size: 56, color: const Color(0xFF59B294))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(
              fontSize: 14, // Reduced from 16
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4A4A4A),
            ),
          ),
        ],
      ),
    );
  }
}
