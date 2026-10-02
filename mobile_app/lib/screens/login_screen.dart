import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 溫馨米黃
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24), // Reduced from 40

// 標題: 歡迎回來
              Center(
                child: Text(
                  '歡迎回來',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28, // Reduced from 32
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                ),
              ),
              const SizedBox(height: 8),

// 副標題
              Center(
                child: Text(
                  '登入以管理家人的陪伴計畫',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14, // Reduced from 16
                    color: Colors.grey[600],
                  ),
                ),
              ),

              const SizedBox(height: 32), // Reduced from 48

// Email / 手機號碼 輸入框
              _buildTextField(
                controller: _emailController,
                hintText: 'Email / 手機號碼',
              ),

              const SizedBox(height: 12), // Reduced from 16

// 密碼 輸入框
              _buildTextField(
                controller: _passwordController,
                hintText: '密碼',
                isPassword: true,
                obscureText: _obscurePassword,
                onToggleVisibility: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),

              const SizedBox(height: 8), // Reduced from 16

// 忘記密碼?
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已傳送重設連結至您的 Email')),
                    );
                  },
                  child: Text(
                    '忘記密碼?',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16), // Reduced from 24

// 登入按鈕
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043), // 橘色
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '登入',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // 快速登入按鈕 (boyo@uban.com)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _quickFillUserAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.flash_on_rounded, color: Color(0xFF0284C7), size: 22),
                  label: Text(
                    '⚡ 快速登入 (boyo@uban.com)',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 註冊連結
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegistrationScreen(),
                      ),
                    );
                  },
                  child: RichText(
                    text: TextSpan(
                      text: '還沒有帳號？',
                      style: GoogleFonts.notoSansTc(color: Colors.grey[600]),
                      children: [
                        TextSpan(
                          text: ' 立即註冊',
                          style: GoogleFonts.notoSansTc(
                            color: const Color(0xFFFF7043),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

// 分隔線 or
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[300])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: GoogleFonts.inter(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[300])),
                ],
              ),

              const SizedBox(height: 40),

              // 社群登入按鈕
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSocialButton(
                    icon: FontAwesomeIcons.google,
                    color: Colors.red,
                    onTap: _isLoading ? () {} : _handleGoogleLogin,
                  ),
                  _buildSocialButton(
                    icon: FontAwesomeIcons.line,
                    color: const Color(0xFF00C300),
                    onTap: _isLoading ? () {} : _handleLineLogin,
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.notoSansTc(
            color: Colors.grey[500],
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey[600],
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required dynamic icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // color: Colors.white,
          // border: Border.all(color: Colors.grey[300]!),
        ),
        child: Center(
          // 使用 Stack 模擬彩色 icon
          child: FaIcon(
            icon ?? FontAwesomeIcons.question,
            size: 60, // 加大圖示
            color: color,
          ),
        ),
      ),
    );
  }
}
