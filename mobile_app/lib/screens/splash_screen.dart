import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'identification_screen.dart';
import 'family_onboarding_screen.dart';
import 'elder_home_screen.dart';
import 'family_main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    try {
      // 延遲 3 秒展示 Splash
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      // 嘗試獲取登入狀態，設置 2 秒超時以防掛起
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      if (!mounted) return;

      final int? userId = prefs.getInt('caregiver_id');
      final String? userName = prefs.getString('caregiver_name');

      if (userId != null && userName != null) {
        // 先獲取當前使用者資訊以判斷角色
        try {
          final userProfile = await ApiService.getStatus(userId);
          if (!mounted) return;
          final role = userProfile['role'] ?? 'family';

          if (role == 'elder') {
            // 長輩端：直接進入長輩首頁
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ElderHomeScreen(userId: userId, userName: userName),
              ),
            );
            return;
          }

          // 子女端邏輯：直接進入主要儀表板容器
          final elders = await ApiService.getPairedElders(userId);
          if (!mounted) return;

          if (elders.isNotEmpty) {
            // 已有長輩，進入主介面（不再強制先進入選擇頁）
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FamilyMainScreen(userId: userId, userName: userName),
              ),
            );
          } else {
            // 未綁定任何長輩，進入引導頁
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FamilyOnboardingScreen(userId: userId, userName: userName),
              ),
            );
          }
        } catch (e) {
          // 若 API 失敗，保守處理
          if (mounted) _goNext();
        }
      } else {
        // 未登入，進入身分辨識頁
        _goNext();
      }
    } catch (e) {
      // 若發生任何錯誤 (如 SharedPreferences 失敗)，確保能進入身分選擇頁
      debugPrint('Splash error: $e');
      if (mounted) _goNext();
    }
  }

  void _goNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const IdentificationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF59B294), // Tealish green
              Color(0xFFD4F5E9), // Very light teal
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF59B294).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'UBan',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              bottom: 40,
              child: Text(
                'v 1.0.0',
                style: GoogleFonts.inter(color: Colors.black54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
