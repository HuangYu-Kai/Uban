import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'identification_screen.dart';
import 'family_onboarding_screen.dart';
import 'elder_home_screen.dart';
import 'family_main_screen.dart';
import '../globals.dart'; // ★ 新增

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const bool _devBypassLogin = bool.fromEnvironment(
    'DEV_BYPASS_LOGIN',
    defaultValue: false,
  );
  static const String _devBypassRole = String.fromEnvironment(
    'DEV_BYPASS_ROLE',
    defaultValue: '',
  );
  static const int _devBypassUserId = int.fromEnvironment(
    'DEV_BYPASS_USER_ID',
    defaultValue: 0,
  );
  static const String _devBypassUserName = String.fromEnvironment(
    'DEV_BYPASS_USER_NAME',
    defaultValue: '測試使用者',
  );

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

      // 開發便捷模式：若本機登入資料遺失，可由 dart-define 自動回填，避免每次重跑都要重新配對
      if (_devBypassLogin && (userId == null || userName == null)) {
        if (_devBypassUserId > 0 && _devBypassRole.isNotEmpty) {
          await prefs.setInt('caregiver_id', _devBypassUserId);
          await prefs.setString('caregiver_name', _devBypassUserName);
          await prefs.setString('user_role', _devBypassRole);
          if (!mounted) return;
        }
      }

      final int? effectiveUserId = prefs.getInt('caregiver_id');
      final String? effectiveUserName = prefs.getString('caregiver_name');
      final String? effectiveLocalRole = prefs.getString('user_role');

      if (effectiveUserId != null && effectiveUserName != null) {
        // 先嘗試獲取當前使用者資訊，以驗證連線與角色
        try {
          final userProfile = await ApiService.getStatus(effectiveUserId);
          if (!mounted) return;
          
          // 角色優先序：1. 後端最新狀態 2. 本地紀錄 3. 預設子女
          final role = userProfile['role'] ?? effectiveLocalRole ?? 'family';
          appRole = role; // ★ 新增：同步到全域變數，確保啟動後通話偵聽正常

          if (role == 'elder') {
            // 長輩端：直接進入長輩首頁
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ElderHomeScreen(
                      userId: effectiveUserId,
                      userName: effectiveUserName,
                    ),
              ),
            );
            return;
          }

          // 子女端邏輯：直接進入主要儀表板容器
          final elders = await ApiService.getPairedElders(effectiveUserId);
          if (!mounted) return;

          if (elders.isNotEmpty) {
            // 已有長輩，進入主介面
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FamilyMainScreen(
                      userId: effectiveUserId,
                      userName: effectiveUserName,
                    ),
              ),
            );
          } else {
            // 未綁定任何長輩，進入引導頁
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FamilyOnboardingScreen(
                      userId: effectiveUserId,
                      userName: effectiveUserName,
                    ),
              ),
            );
          }
        } catch (e) {
          // 若 API 失敗，使用本地紀錄決定跳轉
          if (mounted) {
            if (effectiveLocalRole == 'elder') {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ElderHomeScreen(
                        userId: effectiveUserId,
                        userName: effectiveUserName,
                      ),
                ),
              );
            } else {
              _goNext();
            }
          }
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
