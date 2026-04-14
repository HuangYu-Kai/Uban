import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
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

  bool _fadedOut = false;

  @override
  void initState() {
    super.initState();
    _playAnimations();
    _navigateToNext();
  }

  Future<void> _playAnimations() async {
    // 整個液態擴散動畫放慢至 3.2s
    await Future.delayed(const Duration(milliseconds: 3200));
    
    // 3.2s 開始全局淡出 (歷時 0.8s)
    if (mounted) setState(() => _fadedOut = true);
  }

  Future<void> _navigateToNext() async {
    try {
      // 4.0s (3.2s + 0.8s) 正好銜接淡出的結束點，無縫載入主介面
      await Future.delayed(const Duration(milliseconds: 4000));
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
      backgroundColor: const Color(0xFFF5F5F5), // 介面的預設淺色底
      body: AnimatedOpacity(
        opacity: _fadedOut ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 1000), // 圖標和背景平滑淡出的歷時
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 3200), // 總時長放慢
          curve: Curves.linear,
          builder: (context, time, child) {
            // 前 800 毫秒(約 time 0.0~0.25)安靜停頓，隨後開啟 2.4 秒的極柔和緩慢擴散
            double fillProgress = ((time - 0.25) / 0.75).clamp(0.0, 1.0);
            
            // 使用 easeOutQuart 讓一開始有平滑的加速推力，然後悠長地滑行至邊界，不會有瞬間爆炸的急促感
            double easedProgress = Curves.easeOutQuart.transform(fillProgress);

            final textStyle = GoogleFonts.poppins(
              fontSize: 78,
              fontWeight: FontWeight.w600, // 溫潤、乾淨的科技新創字體
              letterSpacing: 2.0,
            );

            return Stack(
              children: [
                // 底層：原本的白底綠字 (靜止狀態等待水花漫過)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.white,
                  child: Center(
                    child: Text(
                      'Uban',
                      style: textStyle.copyWith(color: const Color(0xFF59B294)),
                    ),
                  ),
                ),
                
                // 頂層：水花漫過的有機擴散綠底白字
                ClipPath(
                  clipper: BlobRevealClipper(easedProgress),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: const Color(0xFF59B294),
                    child: Center(
                      child: Text(
                        'Uban',
                        style: textStyle.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }
}

// 產生「水滴擴散」帶有非對稱、有機流體邊緣的自定義波紋
class BlobRevealClipper extends CustomClipper<Path> {
  final double progress; // 0.0 到 1.0 的液體擴散進度
  BlobRevealClipper(this.progress);

  @override
  Path getClip(Size size) {
    if (progress <= 0) return Path();

    final center = Offset(size.width / 2, size.height / 2);
    // 預設最大半徑為對角線長度
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    // 放大擴散圈倍率 (1.2)，確保算上不規則波動的「波谷」時，也能完全覆蓋到長方形螢幕的最角落
    final currentRadius = maxRadius * progress * 1.2;
    
    Path path = Path();
    int points = 180; // 高密度描點確保液態邊緣極其圓滑
    
    // 波動振幅：擴散越大，水波的起伏感越自然，但適度收斂
    double amplitude = maxRadius * 0.08 * progress; 

    for (int i = 0; i <= points; i++) {
      double angle = (i / points) * 2 * math.pi;
      
      // 使用三層傅立葉干涉 (Sin/Cos) 創造有機、隨機的液滴邊緣
      // 其中動態加入 progress 的相位偏移，讓「水波在向外推的過程中，邊緣形狀也在流動改變」
      double noise = math.sin(angle * 3) * amplitude * 0.7 +
                     math.cos(angle * 5 - progress * 6.0) * amplitude * 0.5 +
                     math.sin(angle * 7 + progress * 4.0) * amplitude * 0.3;
                     
      double r = currentRadius + noise;
      if (r < 0) r = 0; // 防呆
      
      double x = center.dx + r * math.cos(angle);
      double y = center.dy + r * math.sin(angle);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(covariant BlobRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}


