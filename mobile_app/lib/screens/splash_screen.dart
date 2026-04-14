import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui; 
import 'dart:math' as math; // 新增數學函式給光點散播使用
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
    // 整個演繹動畫加上 Logo 停留總共 2.8s
    await Future.delayed(const Duration(milliseconds: 2800));
    
    // 2.8s 開始全局淡出 (歷時 0.7s)
    if (mounted) setState(() => _fadedOut = true);
  }

  Future<void> _navigateToNext() async {
    try {
      // 3.5s 正好銜接淡出的結束點，無縫載入主介面
      await Future.delayed(const Duration(milliseconds: 3500));
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
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF59B294), // 柔和薄荷綠全螢幕背景
          ),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 2500),
              curve: Curves.linear,
              builder: (context, time, child) {
                // 階段 1: 0~0.5s (time 0~0.2) 人頭冒出
                double headAnim = (time / 0.2).clamp(0.0, 1.0);
                
                // 階段 2: 0.5s~1.5s (time 0.2~0.6) 手臂環抱與光點迸發
                double embraceRaw = ((time - 0.2) / 0.4).clamp(0.0, 1.0);
                double embraceAnim = Curves.easeInOut.transform(embraceRaw);
                
                // 階段 3: 1.5s~ (time > 0.6) 手繪轉化為官方 Icon
                bool showIcon = time > 0.6;
                double fadeOutDraw = 1.0 - ((time - 0.6) / 0.1).clamp(0.0, 1.0);
                
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // 原本的手繪區
                    Opacity(
                      opacity: fadeOutDraw,
                      child: CustomPaint(
                        size: const Size(240, 240),
                        painter: EmbracePainter(
                          headAnim: headAnim,
                          embraceAnim: embraceAnim,
                        ),
                      ),
                    ),

                    // 官方 Logo 躍出轉化
                    if (showIcon)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.elasticOut,
                        builder: (context, iconScale, child) {
                          return Transform.scale(
                            scale: iconScale,
                            child: Opacity(
                              opacity: iconScale.clamp(0.0, 1.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 86,
                                    height: 86,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 15,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.volunteer_activism_rounded, // 無縫過渡成官方愛心圖標
                                        color: Color(0xFF59B294),
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'UBan',
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 4.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      ),
                  ],
                );
              }
            ),
          ),
        ),
      ),
    );
  }
}

class EmbracePainter extends CustomPainter {
  final double headAnim;
  final double embraceAnim;

  EmbracePainter({required this.headAnim, required this.embraceAnim});

  @override
  void paint(Canvas canvas, Size size) {
    if (headAnim <= 0) return;

    double cx = size.width / 2;
    double cy = size.height / 2;

    // 1.繪製發光「人頭」 (初始狀態)
    final headRadius = 22.0 * headAnim;
    final headCenter = Offset(cx, cy - 45); // 位於中心偏上
    
    // 人頭光暈
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6 * headAnim)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(headCenter, headRadius * 1.5, glowPaint);

    // 人頭本體
    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(headCenter, headRadius, headPaint);

    // 2.繪製環抱動畫 (擁抱動作)
    if (embraceAnim > 0) {
      // 內心的被擁抱者 (柔和米粉色心形)
      final innerCenter = Offset(cx, cy + 25);
      final innerHeartPaint = Paint()
        ..color = const Color(0xFFFDF0ED).withValues(alpha: embraceAnim * 0.9) // 淡淡偏暖米色
        ..style = PaintingStyle.fill;
      
      // 內心的大小隨著手臂伸展浮現
      final innerPath = _createHeartPath(innerCenter, 22 * embraceAnim);
      canvas.drawPath(innerPath, innerHeartPaint);

      // 外圍環抱的手臂 (心形的下半部與向上包圍)
      final armPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // 左手和右手伸展軌跡
      final leftArm = _createArmPath(innerCenter, 48, true);
      final rightArm = _createArmPath(innerCenter, 48, false);

      for (var path in [leftArm, rightArm]) {
        for (ui.PathMetric metric in path.computeMetrics()) {
          canvas.drawPath(
            metric.extractPath(0, metric.length * embraceAnim), 
            armPaint
          );
        }
      }

      // 愛心小光點散發
      if (embraceAnim > 0.3) {
        // 從 0.3 開始往外擴散
        final particleProgress = ((embraceAnim - 0.3) / 0.7).clamp(0.0, 1.0);
        final particlePaint = Paint()
          ..color = Colors.white.withValues(alpha: 1.0 - particleProgress) // 擴散至頂點時淡出
          ..style = PaintingStyle.fill;

        double radiusOffset = 30 + (45 * particleProgress);
        
        final angles = [135.0, 225.0, 45.0, 315.0];
        for (var angle in angles) {
          final rad = angle * math.pi / 180;
          final px = innerCenter.dx + math.cos(rad) * radiusOffset;
          final py = innerCenter.dy + math.sin(rad) * radiusOffset;
          
          final dotPath = _createHeartPath(Offset(px, py), 5.0 * (1.0 - particleProgress * 0.3)); 
          canvas.drawPath(dotPath, particlePaint);
        }
      }
    }
  }

  Path _createHeartPath(Offset center, double size) {
    Path path = Path();
    path.moveTo(center.dx, center.dy - size * 0.2); // 頂部心窩
    // 左半心
    path.cubicTo(
      center.dx - size * 1.2, center.dy - size * 1.4, 
      center.dx - size * 1.8, center.dy + size * 0.4, 
      center.dx, center.dy + size * 1.2               // 底部尖端
    );
    // 右半心
    path.moveTo(center.dx, center.dy - size * 0.2);
    path.cubicTo(
      center.dx + size * 1.2, center.dy - size * 1.4, 
      center.dx + size * 1.8, center.dy + size * 0.4, 
      center.dx, center.dy + size * 1.2
    );
    return path;
  }

  Path _createArmPath(Offset center, double size, bool isLeft) {
    Path path = Path();
    path.moveTo(center.dx, center.dy + size * 1.2); // 從被擁抱者的底部尖端稍下方開始
    if (isLeft) {
      path.cubicTo(
        center.dx - size * 1.8, center.dy + size * 1.0,  
        center.dx - size * 2.2, center.dy - size * 0.5,  
        center.dx - size * 0.5, center.dy - size * 1.0   // 彎向肩膀上方
      );
    } else {
      path.cubicTo(
        center.dx + size * 1.8, center.dy + size * 1.0, 
        center.dx + size * 2.2, center.dy - size * 0.5, 
        center.dx + size * 0.5, center.dy - size * 1.0
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant EmbracePainter oldDelegate) {
    return oldDelegate.headAnim != headAnim || oldDelegate.embraceAnim != embraceAnim;
  }
}
