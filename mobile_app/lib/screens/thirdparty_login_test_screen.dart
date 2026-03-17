import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

class ThirdpartyLoginTestScreen extends StatefulWidget {
  const ThirdpartyLoginTestScreen({super.key});

  @override
  State<ThirdpartyLoginTestScreen> createState() => _ThirdpartyLoginTestScreenState();
}

class _ThirdpartyLoginTestScreenState extends State<ThirdpartyLoginTestScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final idToken = await AuthService.signInWithGoogle();
      if (!mounted) return;
      
      if (idToken != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google 登入成功！(取得 Token)')),
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
      final accessToken = await AuthService.signInWithLine();
      if (!mounted) return;
      
      if (accessToken != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('LINE 登入成功！(取得 Token)')),
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
      appBar: AppBar(
        title: const Text('第三方登入測試專區'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '測試本地網頁登入流程',
                style: GoogleFonts.notoSansTc(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48),
              
              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                // Google 測試按鈕
                ElevatedButton.icon(
                  onPressed: _handleGoogleLogin,
                  icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                  label: const Text('測試原生 Google 登入', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // LINE 測試按鈕
                ElevatedButton.icon(
                  onPressed: _handleLineLogin,
                  icon: const FaIcon(FontAwesomeIcons.line, color: Colors.white),
                  label: const Text('測試原生 LINE 登入', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C300),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              ],
              
              const SizedBox(height: 48),
              Text(
                '說明：目前使用的是原生的 SDK 進行登入。\n注意：請確認是否已註冊平台專屬的 Client ID/Channel ID，否則登入可能會報錯。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              )
            ],
          ),
        ),
      ),
    );
  }
}
