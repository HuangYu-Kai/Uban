import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';
import 'registration_screen.dart';
import 'caregiver_pairing_screen.dart';

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

      if (result.containsKey('user_id')) {
        // 登入成功
        final bool hasPaired = result['has_paired_elder'] ?? false;

        if (hasPaired) {
          Navigator.pushReplacementNamed(
            context,
            '/family_home',
            arguments: {
              'user_id': result['user_id'],
              'user_name': result['user_name'],
            },
          );
        } else {
          // 強制前往配對頁面
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => CaregiverPairingScreen(
                familyId: result['user_id'],
                familyName: result['user_name'],
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['error'] ?? '登入失敗')));
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
              const SizedBox(height: 40),

              // 標題: 歡迎回來
              Center(
                child: Text(
                  '歡迎回來',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
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
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Email / 手機號碼 輸入框
              _buildTextField(
                controller: _emailController,
                hintText: 'Email / 手機號碼',
              ),

              const SizedBox(height: 16),

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

              const SizedBox(height: 16),

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

              const SizedBox(height: 24),

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

              // 診斷按鈕：連線測試
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final health = await ApiService.checkHealth();
                    if (!context.mounted) return;
                    if (health.containsKey('status') &&
                        health['status'] == 'ok') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ 連線成功：後端運作中')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ 連線失敗：${health['error']}')),
                      );
                    }
                  },
                  icon: const Icon(Icons.network_check, size: 16),
                  label: const Text('連線測試 (診斷用)'),
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
                    onTap: () {},
                  ),
                  _buildSocialButton(
                    icon: FontAwesomeIcons.facebookF,
                    color: const Color(0xFF1877F2),
                    onTap: () {},
                  ),
                  _buildSocialButton(
                    icon: FontAwesomeIcons.line,
                    color: const Color(0xFF00C300),
                    onTap: () {},
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
    required IconData icon,
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
            icon,
            size: 60, // 加大圖示
            color: color,
          ),
        ),
      ),
    );
  }
}
