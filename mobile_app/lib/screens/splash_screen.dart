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
import 'elder_screen.dart'; // ★ 新增

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
      // 若有待接聽的緊急通話，直接跳過開機動畫以加速進入視訊房間
      if (pendingAcceptedCall.value == null) {
        await Future.delayed(const Duration(milliseconds: 4000));
      } else {
        debugPrint("🚨 [Splash] 檢測到待接聽來電，跳過開機動畫延遲");
        // 強制淡出
        if (mounted) setState(() => _fadedOut = true);
      }
      if (!mounted) return;

      // 嘗試獲取登入狀態（已移除 2 秒 .timeout，避免冷啟動 SharedPreferences
      // 初始化 + 磁碟讀取超過 2 秒 → 拋例外 → 誤跳身分頁，讓已登入長輩看似 session 遺失）
      final prefs = await SharedPreferences.getInstance();
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

      // ★ Issue 3 診斷 log：記錄本機 session 三個關鍵欄位，用於區分「session 真的遺失」
      //   還是「短暫讀取異常造成的假性遺失」。
      debugPrint(
          '🔎 [Splash] _navigateToNext prefs 快照: caregiver_id=$effectiveUserId, caregiver_name=$effectiveUserName, user_role=$effectiveLocalRole');

      // ★ issue 2：先以本機紀錄的角色預先設置全域 appRole，
      //   避免在等待 API 回應期間（例如冷啟動時 CallKit 的接聽事件搶先觸發），
      //   main.dart 的 _navigateToVideoCall 因 appRole 仍是 null 而誤判為家屬端，
      //   導致長輩端被推到錯誤的 VideoCallScreen。下方 API 成功後會再次校正。
      if (effectiveLocalRole != null) {
        appRole = effectiveLocalRole;
      }

      if (effectiveUserId != null && effectiveUserName != null) {
        // 先嘗試獲取當前使用者資訊，以驗證連線與角色
        try {
          final userProfile = await ApiService.getStatus(effectiveUserId);
          if (!mounted) return;
          
          final profileData = userProfile['data'] as Map<String, dynamic>? ?? {};
          final role = profileData['role'] ?? effectiveLocalRole ?? 'family';
          appRole = role; // ★ 新增：同步到全域變數，確保啟動後通話偵聽正常

          if (role == 'elder') {
            final String? apiElderId = profileData['elder_id']?.toString();
            if (apiElderId != null) {
              await prefs.setString('elder_room_id', apiElderId);
              if (!mounted) return;
            }

            final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
            final String deviceName = prefs.getString('saved_device_name') ?? effectiveUserName;
            final String elderRoomId = apiElderId ?? prefs.getString('elder_room_id') ?? effectiveUserId.toString();

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => _resolveElderDestination(
                  isCCTV: isCCTV,
                  deviceName: deviceName,
                  elderRoomId: elderRoomId,
                  effectiveUserId: effectiveUserId,
                  effectiveUserName: effectiveUserName,
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
              final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
              final String deviceName = prefs.getString('saved_device_name') ?? effectiveUserName;
              final String elderRoomId = prefs.getString('elder_room_id') ?? effectiveUserId.toString();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => _resolveElderDestination(
                    isCCTV: isCCTV,
                    deviceName: deviceName,
                    elderRoomId: elderRoomId,
                    effectiveUserId: effectiveUserId,
                    effectiveUserName: effectiveUserName,
                  ),
                ),
              );
            } else {
              // ★ Issue 3 硬化：effectiveLocalRole 只是進入本函式當下的快照，
              //   API 失敗不代表本機真的不是長輩帳號；改由 _goNextOrRestoreElder
              //   重讀 prefs 二次確認，避免暫時性失敗把已登入長輩丟到身分頁。
              await _goNextOrRestoreElder();
            }
          }
        }
      } else {
        // 未登入，進入身分辨識頁
        // ★ Issue 3 硬化：effectiveUserId/effectiveUserName 可能只是短暫讀取異常
        //   造成的假性 null，先由 _goNextOrRestoreElder 重讀一次 prefs 再決定。
        await _goNextOrRestoreElder();
      }
    } catch (e) {
      // 若發生任何錯誤 (如 SharedPreferences 失敗)，確保能進入身分選擇頁
      debugPrint('Splash error: $e');
      // ★ Issue 3 硬化：任何例外都先嘗試重讀 prefs 判斷是否為已登入長輩，
      //   絕不能因為一次例外就把已登入長輩導回身分辨識頁。
      if (mounted) await _goNextOrRestoreElder();
    }
  }

  void _goNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const IdentificationScreen()),
    );
  }

  /// ★ Issue 3 硬化：在導向身分辨識頁（_goNext）之前的最後防線。
  /// API 失敗或 prefs 短暫讀取異常，不代表本機真的沒有已登入的長輩 session。
  /// 這裡「重新」讀一次 SharedPreferences（不沿用外層可能已經是舊快照的區域變數），
  /// 只要看起來像長輩 session（user_role 直接是 'elder'；或 user_role 欄位本身缺漏
  /// 但 caregiver_id/caregiver_name 都還在，視為寫入未完成的邊界情況也保守當作長輩），
  /// 就一律導向長輩主畫面，絕不因暫時性失敗把已登入長輩丟回身分頁。
  Future<void> _goNextOrRestoreElder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? uid = prefs.getInt('caregiver_id');
      final String? uname = prefs.getString('caregiver_name');
      final String? role = prefs.getString('user_role');

      debugPrint(
          '🛟 [Splash] _goNextOrRestoreElder 重讀 prefs: caregiver_id=$uid, caregiver_name=$uname, user_role=$role');

      final bool looksLikeElderSession =
          role == 'elder' || (role == null && uid != null && uname != null);

      if (looksLikeElderSession && mounted) {
        final bool isCCTV = prefs.getBool('saved_is_cctv') ?? false;
        final String deviceName =
            prefs.getString('saved_device_name') ?? uname ?? '長輩';
        final String elderRoomId =
            prefs.getString('elder_room_id') ?? uid?.toString() ?? '0';

        debugPrint('🛡️ [Splash] 偵測到本機長輩 session，改導向長輩主畫面而非身分頁');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => _resolveElderDestination(
              isCCTV: isCCTV,
              deviceName: deviceName,
              elderRoomId: elderRoomId,
              effectiveUserId: uid ?? 0,
              effectiveUserName: uname ?? deviceName,
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('⚠️ [Splash] _goNextOrRestoreElder 重讀 prefs 失敗: $e');
    }
    if (mounted) _goNext();
  }

  /// ★ issue 2/10：決定長輩端啟動後要進入哪個畫面。
  /// 在等待 SharedPreferences/API 期間，若收到待接聽的來電（一般或緊急），
  /// `pendingAcceptedCall` 會被填入。此處在「導航當下」重新檢查一次，
  /// 若有待接聽來電則直接跳過長輩主畫面，進入 ElderScreen 並帶上通話資料，
  /// 模擬「像緊急來電一樣直接進入視訊房間」的需求。
  Widget _resolveElderDestination({
    required bool isCCTV,
    required String deviceName,
    required String elderRoomId,
    required int effectiveUserId,
    required String effectiveUserName,
  }) {
    final pending = pendingAcceptedCall.value;
    if (pending != null && !isCCTV) {
      pendingAcceptedCall.value = null; // 消費掉，避免主畫面重複處理
      debugPrint("🚨 [Splash] 偵測到待接聽來電，直接進入 ElderScreen");
      return ElderScreen(
        roomId: pending['roomId'] ?? elderRoomId,
        deviceName: deviceName,
        initialCallData: pending,
      );
    }

    if (isCCTV) {
      return ElderScreen(
        roomId: elderRoomId,
        isCCTVMode: true,
        deviceName: deviceName,
      );
    }

    return ElderHomeScreen(
      userId: effectiveUserId,
      userName: effectiveUserName,
      roomId: elderRoomId,
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


