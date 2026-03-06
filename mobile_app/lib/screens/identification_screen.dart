import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'elder_pairing_display_screen.dart';
import 'login_screen.dart';

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
                  const SizedBox(height: 24),
                  // "誰在使用？" Title
                  Text(
                    '誰在使用？',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 40, // Slightly smaller for better fit
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF59B294),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Cards Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 800,
                      ), // Limit max width for tablets
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                          const SizedBox(width: 24),
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
                    ),
                  ),
                  const SizedBox(height: 48),
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
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                image: DecorationImage(
                  image: AssetImage(imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4A4A4A),
            ),
          ),
        ],
      ),
    );
  }
}
