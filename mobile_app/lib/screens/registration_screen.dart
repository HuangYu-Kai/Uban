import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  String _selectedGender = 'M';
  bool _isLoading = false;

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final ageStr = _ageController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || ageStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫所有欄位')));
      return;
    }

    final age = int.tryParse(ageStr) ?? 20;

    setState(() => _isLoading = true);
    try {
      final result = await ApiService.register(
        username: name,
        email: email,
        password: password,
        role: 'family', // 子女端註冊
        gender: _selectedGender,
        age: age,
      );

      if (!mounted) return;

      if (result.containsKey('user_id')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('註冊成功，請登入')));
        Navigator.pop(context); // 回到登入頁
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['error'] ?? '註冊失敗')));
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
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text('帳號註冊', style: GoogleFonts.notoSansTc(color: Colors.black)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '加入 UBan 陪伴計畫',
                style: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '填寫資料以開始串接長輩的陪伴系統',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),

              _buildTextField(_nameController, '您的姓名', Icons.person_outline),
              const SizedBox(height: 16),
              _buildTextField(_emailController, 'Email', Icons.email_outlined),
              const SizedBox(height: 16),
              _buildTextField(
                _passwordController,
                '密碼',
                Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _ageController,
                      '年齡',
                      Icons.cake_outlined,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedGender,
                        items: const [
                          DropdownMenuItem(value: 'M', child: Text('男')),
                          DropdownMenuItem(value: 'F', child: Text('女')),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedGender = val!),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '註冊並繼續',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
