import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'registration_screen.dart';
import 'family_onboarding_screen.dart';
import 'family_main_screen.dart';
import 'family_profile_onboarding_screen.dart';
import '../globals.dart';
import '../services/auth_service.dart';
import '../utils/profile_completeness.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';

// 家屬/照護者登入畫面
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫所有欄位')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ApiService.login(email, password);
      if (!mounted) return;

      // API 回傳格式: { status: "success", data: { user_id, ... } }
      final data = result['data'];
      if (result['status'] == 'success' && data != null && data['user_id'] != null) {
        // 登入成功
        final int userId = data['user_id'];
        final String userName = data['user_name'] ?? '使用者';

        // 持久化儲存登入狀態
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;

        await prefs.setInt('caregiver_id', userId);
        await prefs.setString('caregiver_name', userName);
        await prefs.setString('user_role', 'family');
        // ★ 2026-08-05 第十六輪：兩個角色鍵必須同步寫，否則
        //   `user_role ?? saved_role` 會讀到跨身分殘留值（見 main.dart
        //   _deriveMyRoleFromCall 註解）。
        await prefs.setString('saved_role', 'family');
        appRole = 'family'; // ★ 新增：更新全域變數，確保通話偵聽正常

        if (!mounted) return; // MUST check again after async setInt/setString

        final bool hasPaired = data['has_paired_elder'] ?? false;

        // 登入後的下一步（依是否已配對長輩而不同），供補填完成後接續導向。
        WidgetBuilder nextScreenBuilder = hasPaired
            ? (context) => FamilyMainScreen(userId: userId, userName: userName)
            : (context) => FamilyOnboardingScreen(userId: userId, userName: userName);

        // ★ 第五十三輪 onboard53（家 4）：年齡／居住地改為必填，既有帳號（在
        //   這次改動上線前就註冊過）第一次登入時強制補填，不提供略過。
        //
        //   ⚠️ fail-open，不是 fail-closed：這裡只有在「讀得到資料、且資料
        //   確定是空的」才會導去補填畫面；讀取失敗（逾時、離線、伺服器錯誤）
        //   一律當作「已完整」直接放行——斷線時把使用者鎖在補填畫面外面、
        //   進不了 App，是比「資料晚一點補」嚴重得多的問題。
        //   ApiService.getElderProfile() 內部已經 try/catch 過，逾時或例外
        //   都回傳 {'status': 'error', ...} 而不是丟例外，這裡不需要再包一層。
        //   判斷邏輯本身抽到 utils/profile_completeness.dart（與長輩端
        //   elder_pairing_display_screen.dart::_goToElderHome 共用），
        //   避免兩端各自維護一份「必填」定義而逐漸分歧。
        bool profileConfirmedIncomplete = false;
        try {
          final profileResult = await ApiService.getElderProfile(userId);
          profileConfirmedIncomplete = isProfileConfirmedIncomplete(profileResult);
        } catch (_) {
          // 理論上 ApiService.getElderProfile 不會丟到這裡，多一層保險維持 fail-open。
          profileConfirmedIncomplete = false;
        }

        if (!mounted) return;

        if (profileConfirmedIncomplete) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => FamilyProfileOnboardingScreen(
                userId: userId,
                userName: userName,
                nextScreenBuilder: nextScreenBuilder,
              ),
            ),
            (route) => false,
          );
        } else if (hasPaired) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: nextScreenBuilder),
            (route) => false,
          );
        } else {
          // 未配對時，引導進入溫馨介紹畫面
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: nextScreenBuilder),
          );
        }
      } else {
        // 顯示錯誤訊息
        final errorMsg = result['message'] ?? result['error'] ?? result['detail'] ?? '登入失敗';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('連線失敗: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _quickFillUserAccount() {
    setState(() {
      _emailController.text = 'boyo@uban.com';
      _passwordController.text = 'robert20040924';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚡ 已帶入 boyo@uban.com，正在登入...'),
        duration: Duration(seconds: 1),
      ),
    );
    _handleLogin();
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final idTokenData = await AuthService.signInWithGoogle();
      if (!mounted) return;

      if (idTokenData != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google 登入成功！(正在執行 OIDC 測試...)')),
        );

        // 執行 OIDC 測試：將資料傳給後端寫入檔案
        await ApiService.testOidc(
          provider: 'google',
          email: idTokenData['email'] ?? 'N/A',
          uid: idTokenData['uid'] ?? 'N/A',
          token: idTokenData['token'] ?? 'N/A',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('OIDC 測試完成！請查看根目錄 oidc_test_results.txt')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google 登入失敗: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLineLogin() async {
    setState(() => _isLoading = true);
    try {
      final accessTokenData = await AuthService.signInWithLine();
      if (!mounted) return;

      if (accessTokenData != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('LINE 登入成功！(正在執行 OIDC 測試...)')),
        );

        // 執行 OIDC 測試：將資料傳給後端寫入檔案
        await ApiService.testOidc(
          provider: 'line',
          email: accessTokenData['email'] ?? 'N/A',
          uid: accessTokenData['uid'] ?? 'N/A',
          token: accessTokenData['token'] ?? 'N/A',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('OIDC 測試完成！請查看根目錄 oidc_test_results.txt')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LINE 登入失敗: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: UbanIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  semanticLabel: '返回',
                  flat: true,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 標題區：標誌＋歡迎回來＋說明
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: UbanMarkBox(
                            size: 56,
                            radius: 18,
                            child: UbanHeartMark(size: 36),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('歡迎回來', style: ubanH1(context)),
                        const SizedBox(height: 8),
                        Text('登入後就能看到長輩今天過得好不好',
                            style: ubanBody(context, size: 17)),
                        const SizedBox(height: 22),

                        // Email / 手機號碼 輸入框
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email／手機號碼',
                          keyboardType: TextInputType.emailAddress,
                        ),

                        const SizedBox(height: 14),

                        // 密碼 輸入框
                        _buildTextField(
                          controller: _passwordController,
                          label: '密碼',
                          isPassword: true,
                          obscureText: _obscurePassword,
                          onToggleVisibility: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),

                        // 忘記密碼？（照現狀只跳提示）
                        Align(
                          alignment: Alignment.centerRight,
                          child: UbanButton(
                            label: '忘記密碼？',
                            variant: UbanButtonVariant.ghost,
                            expand: false,
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('已傳送重設連結至您的 Email')),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 4),

                        // 登入按鈕
                        UbanButton(
                          label: '登入',
                          loading: _isLoading,
                          onPressed: _isLoading ? null : _handleLogin,
                        ),

                        const SizedBox(height: 14),

                        // 快速登入按鈕 (boyo@uban.com，開發用)
                        UbanButton(
                          label: '快速登入（開發用）',
                          variant: UbanButtonVariant.tonal,
                          onPressed: _isLoading ? null : _quickFillUserAccount,
                        ),

                        const SizedBox(height: 22),

                        // 分隔線：或
                        Row(
                          children: [
                            Expanded(child: Container(height: 1, color: c.line)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('或',
                                  style:
                                      ubanText(14, FontWeight.w400, c.text3)),
                            ),
                            Expanded(child: Container(height: 1, color: c.line)),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // 社群登入按鈕
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildSocialButton(
                              icon: FontAwesomeIcons.google,
                              semanticLabel: 'Google 登入',
                              // Google 品牌固定色
                              iconColor: const Color(0xFF4285F4),
                              background: c.surface,
                              onTap: _isLoading ? () {} : _handleGoogleLogin,
                            ),
                            const SizedBox(width: 16),
                            _buildSocialButton(
                              icon: FontAwesomeIcons.line,
                              semanticLabel: 'LINE 登入',
                              iconColor: Colors.white,
                              background: c.lineGreen,
                              onTap: _isLoading ? () {} : _handleLineLogin,
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // 註冊連結
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text('還沒有帳號？',
                                  style: ubanText(16, FontWeight.w400, c.text2)),
                            ),
                            UbanButton(
                              label: '註冊',
                              variant: UbanButtonVariant.ghost,
                              expand: false,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const RegistrationScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    final c = UbanColors.of(context);
    return UbanTextField(
      controller: controller,
      label: label,
      keyboardType: keyboardType,
      obscureText: obscureText,
      suffixIcon: isPassword
          ? IconButton(
              tooltip: obscureText ? '顯示密碼' : '隱藏密碼',
              icon: Icon(
                obscureText
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: c.text2,
              ),
              onPressed: onToggleVisibility,
            )
          : null,
    );
  }

  /// 設計稿 `.roundbtn`：64 圓、卡片陰影、按壓縮放＋液態暈開。
  Widget _buildSocialButton({
    required dynamic icon,
    required String semanticLabel,
    required Color iconColor,
    required Color background,
    required VoidCallback onTap,
  }) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: BlobRipple(
          color: c.brand.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(32),
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              boxShadow: c.shadows.card,
            ),
            child: FaIcon(
              icon ?? FontAwesomeIcons.question,
              size: 28,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
