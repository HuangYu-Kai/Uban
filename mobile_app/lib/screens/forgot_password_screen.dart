import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';

/// 忘記密碼（Email 驗證碼）。
///
/// 流程：步驟一輸入 Email 並寄送驗證碼 → 步驟二（同一頁）輸入 6 位數驗證碼與新密碼。
/// 驗證碼綁定寄送時的 Email：步驟二若改了 Email，退回步驟一重新寄送。
/// 重設成功以 `Navigator.pop(context, email)` 回傳 Email，由登入頁帶回欄位。
class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSending = false;
  bool _isSubmitting = false;

  // 是否已寄出驗證碼（步驟二）；_sentEmail 為寄送當下的 Email
  bool _codeSent = false;
  String _sentEmail = '';

  // 重新寄送倒數（秒），由後端 resend_after 決定
  int _resendRemaining = 0;
  Timer? _resendTimer;

  // 持久化錯誤訊息（比照 registration_screen，不只用 SnackBar）
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = (widget.initialEmail ?? '').trim();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 將後端錯誤負載轉為可顯示的繁體中文（detail 可能是字串或 422 的 List）。
  String _readableError(Map<String, dynamic> result, String fallback) {
    final dynamic raw = result['detail'] ?? result['message'] ?? result['error'];
    debugPrint('⚠️ [ForgotPassword] 後端回應: $raw');
    if (raw is String && raw.trim().isNotEmpty) {
      final msg = raw.trim();
      if (msg.contains('網路連線失敗') || msg.contains('伺服器回應格式錯誤')) {
        return '目前連不上伺服器，請確認網路後再試一次';
      }
      // 沒有任何中文字元＝多半是技術訊息，不直接給使用者看
      if (!RegExp(r'[一-鿿]').hasMatch(msg)) return fallback;
      return msg;
    }
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map && first['msg'] != null) {
        final m = first['msg'].toString();
        if (RegExp(r'[一-鿿]').hasMatch(m)) return m;
      }
      return '請檢查 Email 與密碼的格式是否正確';
    }
    return fallback;
  }

  bool _emailLooksValid(String email) =>
      email.isNotEmpty && email.contains('@');

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendRemaining = _resendRemaining > 0 ? _resendRemaining - 1 : 0;
      });
      if (_resendRemaining <= 0) t.cancel();
    });
  }

  /// 使用者改了 Email：若已寄過碼就退回步驟一（驗證碼綁定寄送時的 Email）。
  void _onEmailChanged(String value) {
    setState(() {
      _errorMessage = null;
      if (_codeSent && value.trim() != _sentEmail) {
        _codeSent = false;
        _codeController.clear();
        _passwordController.clear();
        _confirmController.clear();
        _resendTimer?.cancel();
        _resendRemaining = 0;
      }
    });
  }

  Future<void> _handleSendCode() async {
    if (_isSending || _isSubmitting) return;
    final email = _emailController.text.trim();
    setState(() => _errorMessage = null);
    if (!_emailLooksValid(email)) {
      setState(() => _errorMessage = '請輸入正確的 Email');
      return;
    }

    setState(() => _isSending = true);
    try {
      final result = await ApiService.sendEmailCode(
        email: email,
        purpose: 'reset_password',
      );
      if (!mounted) return;
      final data = result['data'];
      if (result['status'] == 'success') {
        final int resendAfter =
            (data is Map && data['resend_after'] is int) ? data['resend_after'] : 60;
        setState(() {
          _codeSent = true;
          _sentEmail = email;
          _codeController.clear();
        });
        _startResendCountdown(resendAfter);
      } else {
        setState(() => _errorMessage = _readableError(result, '驗證碼寄送失敗，請稍後再試'));
      }
    } catch (e) {
      debugPrint('⚠️ [ForgotPassword] 寄送驗證碼例外: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '目前連不上伺服器，請確認網路後再試一次');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _handleReset() async {
    if (_isSubmitting || _isSending) return;
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    setState(() => _errorMessage = null);

    if (!_emailLooksValid(email)) {
      setState(() => _errorMessage = '請輸入正確的 Email');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _errorMessage = '請輸入 6 位數驗證碼');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = '密碼至少需要 6 個字');
      return;
    }
    // bcrypt 只吃前 72 bytes，後端以 UTF-8 位元組數為準
    if (utf8.encode(password).length > 72) {
      setState(() => _errorMessage = '密碼太長了，請在 72 個字元內');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = '兩次輸入的新密碼不一致');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ApiService.resetPassword(
        email: email,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      if (result['status'] == 'success') {
        Navigator.pop(context, email);
      } else {
        setState(() => _errorMessage = _readableError(result, '重設密碼失敗，請稍後再試'));
      }
    } catch (e) {
      debugPrint('⚠️ [ForgotPassword] 重設密碼例外: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '目前連不上伺服器，請確認網路後再試一次');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final busy = _isSending || _isSubmitting;
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
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: UbanMarkBox(
                            size: 56,
                            radius: 18,
                            child: UbanHeartMark(size: 36),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('忘記密碼', style: ubanH1(context)),
                        const SizedBox(height: 8),
                        Text('輸入註冊時的 Email，我們會寄 6 位數驗證碼給您',
                            style: ubanBody(context, size: 17)),
                        const SizedBox(height: 22),

                        UbanTextField(
                          controller: _emailController,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          onChanged: _onEmailChanged,
                        ),
                        const SizedBox(height: 14),

                        if (!_codeSent)
                          UbanButton(
                            label: '寄送驗證碼',
                            loading: _isSending,
                            onPressed: busy ? null : _handleSendCode,
                          )
                        else ...[
                          // 不論該 Email 是否存在後端都回成功，文案刻意不洩漏帳號是否存在
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.mark_email_read_outlined,
                                  color: c.brandStrong),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '如果這個 Email 有註冊過，6 位數驗證碼已寄出，10 分鐘內有效',
                                  style: ubanText(15, FontWeight.w500, c.text2,
                                      height: 1.4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          UbanTextField(
                            controller: _codeController,
                            label: '6 位數驗證碼',
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) =>
                                setState(() => _errorMessage = null),
                          ),
                          const SizedBox(height: 14),
                          UbanTextField(
                            controller: _passwordController,
                            label: '新密碼',
                            obscureText: _obscurePassword,
                            onChanged: (_) =>
                                setState(() => _errorMessage = null),
                            suffixIcon: _visibilityButton(
                              obscured: _obscurePassword,
                              onTap: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          const SizedBox(height: 14),
                          UbanTextField(
                            controller: _confirmController,
                            label: '確認新密碼',
                            obscureText: _obscureConfirm,
                            onChanged: (_) =>
                                setState(() => _errorMessage = null),
                            suffixIcon: _visibilityButton(
                              obscured: _obscureConfirm,
                              onTap: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          const SizedBox(height: 14),
                          UbanButton(
                            label: _resendRemaining > 0
                                ? '重新寄送（$_resendRemaining 秒）'
                                : '重新寄送',
                            variant: UbanButtonVariant.outline,
                            loading: _isSending,
                            onPressed: (busy || _resendRemaining > 0)
                                ? null
                                : _handleSendCode,
                          ),
                        ],

                        const SizedBox(height: 18),

                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: c.dangerContainer,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: c.danger, width: 1.5),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: c.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: ubanText(15, FontWeight.w700, c.text,
                                        height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (_codeSent)
                          UbanButton(
                            label: '重設密碼',
                            loading: _isSubmitting,
                            onPressed: busy ? null : _handleReset,
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

  Widget _visibilityButton({
    required bool obscured,
    required VoidCallback onTap,
  }) {
    final c = UbanColors.of(context);
    return IconButton(
      tooltip: obscured ? '顯示密碼' : '隱藏密碼',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: c.text2,
      ),
      onPressed: onTap,
    );
  }
}
