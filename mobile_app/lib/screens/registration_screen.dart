import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/privacy_policy_content.dart';
import '../services/api_service.dart';
import '../widgets/policy_detail_dialog.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';
import '../widgets/locate_city_button.dart';
import '../widgets/ui/ui.dart';
import 'family_onboarding_screen.dart';
import '../globals.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  // Email 驗證碼：寄送 `POST /api/auth/email-code`（purpose=register），
  // 註冊時以 email_code 一併送出。驗證碼綁定寄送時的 Email。
  final TextEditingController _codeController = TextEditingController();
  bool _isSendingCode = false;
  String _sentEmail = '';
  int _resendRemaining = 0;
  Timer? _resendTimer;

  bool _isLoading = false;
  // ★ 2026-10-06 登入流程審查：同意條款不得預設勾選（需使用者主動同意）。
  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  // ★ 持久化錯誤訊息：取代原本的 SnackBar，避免使用者錯過失敗原因（見第 27 輪卡關根因）
  String? _errorMessage;

  // ★ 第五十三輪 onboard53：年齡／居住地改為必填（家 4）。使用者明確決定
  //   「由選填改為必填，不再允許沒填就跳過」，故這三個欄位沒有預設值、
  //   沒有「以後再說」的出路——送出前會擋在 _handleRegister() 裡。
  //   僅收集到縣市／行政區（不含街道門牌），因為這筆資料只用於開發者統計。
  int? _age;
  String? _residenceCity;
  final ValueNotifier<int> _locateReset = ValueNotifier<int>(0);
  String? _residenceDistrict;

  void _showDisclaimerDialog(BuildContext context) {
    PolicyDetailDialog.show(
      context,
      title: '醫療免責聲明',
      introText: '本聲明旨在明確界定系統非醫療器材，且不負擔因 AI 判斷、語音建議或緊急求救（SOS）延誤而產生的醫療法律責任。',
      headerIcon: Icons.gavel_rounded,
      primaryColor: UbanColors.of(context).warm,
      secondaryColor: UbanColors.of(context).warm,
      sections: const [
        PrivacyPolicySection(
          title: '1. 非醫療診斷與建議之提供',
          icon: Icons.health_and_safety_outlined,
          bulletPoints: [
            '本服務所生成之所有語音、文字、圖表及分析結果，**僅供日常生活陪伴與一般健康促進參考**，不構成任何醫療診斷、藥物處方、臨床治療或專業醫學建議。',
            '本服務所提供之內容，**絕不可替代**專業醫師、藥師或其他合格醫療人員之現場診斷或專業諮詢。',
          ],
        ),
        PrivacyPolicySection(
          title: '2. 藥物提醒之限制',
          icon: Icons.medication_outlined,
          bulletPoints: [
            '系統中之「用藥提醒」功能**僅作日常記事與備忘用途**。',
            '本服務不對用藥種類、劑量、服用時間之絕對準確性承擔責任。',
            '長輩與家屬應自行核對藥袋指示與藥師囑咐，並以真實藥物標示為準。',
          ],
        ),
        PrivacyPolicySection(
          title: '3. AI 技術限制與幻覺免責',
          icon: Icons.psychology_outlined,
          bulletPoints: [
            '用戶理解並同意，本服務之對話核心由**生成式人工智慧（Generative AI）**驅動。',
            'AI 在對話中可能產生錯誤、不實、不完整或具誤導性之資訊（即**「AI 幻覺」**）。',
            '本服務不保證 AI 對話內容的絕對正確性。使用者因信賴 AI 對話而採取或不採取任何行動，其所衍生之任何風險與損害，均由**用戶自行承擔**，本服務及其開發團隊不負任何損害賠償責任。',
          ],
        ),
        PrivacyPolicySection(
          title: '4. 緊急求救（SOS）與視訊功能免責',
          icon: Icons.emergency_share_outlined,
          bulletPoints: [
            '本服務之「緊急求救（SOS）通知家屬」功能依賴網際網路連線、推播通知系統及第三方通訊服務（如 Socket、Firebase）。',
            '**本服務非內政部消防署之 119 通報系統，亦非緊急救護機關。**',
            '如遇突發性重大身體不適、意外受傷或其他緊急狀況，**請立即撥打 119** 或求助於當地緊急醫療救援機構。',
            '本服務對因網路中斷、系統延遲、硬體故障或任何原因導致求救通知延誤或未能送達家屬，所造成之傷亡或損害，均不承擔任何直接或間接之法律責任。',
          ],
        ),
        PrivacyPolicySection(
          title: '5. 同意與受約束',
          icon: Icons.assignment_turned_in_outlined,
          bulletPoints: [
            '使用本服務即代表您（長輩及家屬）已閱讀、理解並**完全同意本免責聲明之全部內容**。',
          ],
        ),
      ],
    );
  }

  /// ★ 2026-09-11 第四十五輪：內容改為引用單一權威來源
  /// `PrivacyPolicyContent`（見 `../data/privacy_policy_content.dart`），
  /// 與首次安裝的精簡同意頁 (`privacy_policy_screen.dart`) 共用同一份文字，
  /// 不再各自維護一份。呈現外觀改用共用的 [PolicyDetailDialog]。
  void _showPrivacyPolicyDialog(BuildContext context) {
    PolicyDetailDialog.show(
      context,
      title: PrivacyPolicyContent.title,
      introText: PrivacyPolicyContent.introText,
      headerIcon: Icons.shield_outlined,
      primaryColor: UbanColors.of(context).brandStrong,
      secondaryColor: UbanColors.of(context).brandFill,
      sections: PrivacyPolicyContent.sections,
      lastUpdated: '最後更新：${PrivacyPolicyContent.lastUpdated}',
    );
  }

  /// ★ 將後端錯誤負載轉為可顯示的繁體中文字串。
  /// FastAPI 422 驗證錯誤的 `detail` 是 List（例如密碼長度不足），
  /// 若直接丟進 Text() 會是執行期型別錯誤，必須先轉字串。
  String _readableError(dynamic raw, {String fallback = '註冊失敗，請稍後再試'}) {
    if (raw is String && raw.trim().isNotEmpty) {
      final msg = raw.trim();
      debugPrint('⚠️ [Register] 後端回應: $msg');
      // ★ 2026-10-06：技術／英文字串不直接給使用者看
      if (msg.toLowerCase().contains('already exists')) {
        return '這個 Email 已經註冊過了，請直接登入';
      }
      if (msg.contains('網路連線失敗') || msg.contains('伺服器回應格式錯誤')) {
        return '目前連不上伺服器，請確認網路後再試一次';
      }
      if (!RegExp(r'[一-鿿]').hasMatch(msg)) {
        return fallback;
      }
      return msg;
    }
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map && first['msg'] != null) {
        return first['msg'].toString();
      }
      return first.toString();
    }
    if (raw is Map) {
      final msg = raw['msg'] ?? raw['detail'] ?? raw['message'];
      if (msg != null) return msg.toString();
      return raw.toString();
    }
    return fallback;
  }

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

  /// 寄碼後又改了 Email → 清空驗證碼並停止倒數，需重新寄送。
  void _onEmailChanged(String value) {
    setState(() {
      _errorMessage = null;
      if (_sentEmail.isNotEmpty && value.trim() != _sentEmail) {
        _sentEmail = '';
        _codeController.clear();
        _resendTimer?.cancel();
        _resendRemaining = 0;
      }
    });
  }

  Future<void> _handleSendCode() async {
    if (_isSendingCode || _isLoading) return;
    final email = _emailController.text.trim();
    setState(() => _errorMessage = null);
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '請先輸入正確的 Email');
      return;
    }
    setState(() => _isSendingCode = true);
    try {
      final result = await ApiService.sendEmailCode(
        email: email,
        purpose: 'register',
      );
      if (!mounted) return;
      if (result['status'] == 'success') {
        final data = result['data'];
        final int resendAfter =
            (data is Map && data['resend_after'] is int) ? data['resend_after'] : 60;
        setState(() {
          _sentEmail = email;
          _codeController.clear();
        });
        _startResendCountdown(resendAfter);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('驗證碼已寄出，10 分鐘內有效')),
        );
      } else {
        // 409（已註冊）、429（太頻繁）、503（寄信失敗）皆顯示後端中文 detail
        setState(() {
          _errorMessage = _readableError(
              result['detail'] ?? result['error'] ?? result['message'],
              fallback: '驗證碼寄送失敗，請稍後再試');
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Register] 寄送驗證碼例外: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '目前連不上伺服器，請確認網路後再試一次');
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _handleRegister() async {
    setState(() => _errorMessage = null);

    if (_isLoading) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = '請填寫姓名、Email 與密碼');
      return;
    }

    if (!_agreedToTerms) {
      setState(() => _errorMessage = '請先勾選並同意隱私權政策與醫療免責聲明');
      return;
    }

    // ★ 後端 schemas/auth.py 要求密碼至少 6 碼，未先檢查會得到不友善的 422 錯誤
    if (password.length < 6) {
      setState(() => _errorMessage = '密碼至少需要 6 個字');
      return;
    }
    // ★ 2026-10-06 登入流程審查：bcrypt 只吃前 72 bytes，後端以 UTF-8 位元組數為準。
    if (utf8.encode(password).length > 72) {
      setState(() => _errorMessage = '密碼太長了，請在 72 個字元內');
      return;
    }
    if (name.length > 30) {
      setState(() => _errorMessage = '名字請在 30 個字以內');
      return;
    }

    // Email 驗證碼：必須是寄送過的同一個 Email、6 位數字
    final emailCode = _codeController.text.trim();
    if (_sentEmail != email) {
      setState(() => _errorMessage = '請先按「寄送驗證碼」驗證 Email');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(emailCode)) {
      setState(() => _errorMessage = '請輸入 6 位數 Email 驗證碼');
      return;
    }

    // ★ 第五十三輪 onboard53：年齡／居住地改為必填，不提供略過。這裡是唯一
    //   的擋點——三個欄位任一未填都不送出註冊請求。後端 routers/auth.py::
    //   register() 仍會再驗證一次範圍／白名單，這裡的檢查只是提早給出
    //   對使用者友善的錯誤訊息，不是唯一防線。
    if (_age == null || _residenceCity == null || _residenceDistrict == null) {
      setState(() => _errorMessage = '請填寫年齡與居住地（縣市／行政區）');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ApiService.register(
        username: name,
        email: email,
        password: password,
        role: 'family', // 子女端註冊
        age: _age,
        residenceCity: _residenceCity,
        residenceDistrict: _residenceDistrict,
        emailCode: emailCode,
      );

      if (!mounted) return;

      // API 回傳格式: { status: "success", data: { user_id, ... } }
      final data = result['data'];
      if (result['status'] == 'success' && data != null && data['user_id'] != null) {
        // ★ 核心優化：註冊成功直接自動登入，流暢接續家屬主流程
        try {
          final loginResult = await ApiService.login(email, password);
          if (!mounted) return;
          final loginData = loginResult['data'];
          if (loginResult['status'] == 'success' && loginData != null && loginData['user_id'] != null) {
            final int userId = loginData['user_id'];
            final String userName = loginData['user_name'] ?? name;

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('caregiver_id', userId);
            await prefs.setString('caregiver_name', userName);
            await prefs.setString('user_role', 'family');
            await prefs.setString('saved_role', 'family');
            appRole = 'family';

            if (!mounted) return;
            setState(() => _errorMessage = null);
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => FamilyOnboardingScreen(userId: userId, userName: userName),
              ),
              (route) => false,
            );
            return;
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() => _errorMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('註冊成功，請登入')),
        );
        Navigator.pop(context); // 備援：回到登入頁
      } else {
        // ★ 顯示持久化錯誤訊息，避免 SnackBar 稍縱即逝導致使用者看不到失敗原因
        setState(() {
          // 後端 detail 現為中文；舊版 message 也一併涵蓋（含網路層錯誤）
          _errorMessage = _readableError(
              result['detail'] ?? result['error'] ?? result['message']);
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Register] 註冊例外: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '目前連不上伺服器，請確認網路後再試一次');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    _locateReset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UbanTopBar(
                    title: '帳號註冊',
                    onBack: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 18),

                  _buildTextField(
                    _nameController,
                    '您的名字',
                    onChanged: (_) => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    _emailController,
                    'Email',
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onEmailChanged,
                  ),
                  const SizedBox(height: 10),
                  UbanButton(
                    label: _resendRemaining > 0
                        ? '重新寄送（$_resendRemaining 秒）'
                        : (_sentEmail.isEmpty ? '寄送驗證碼' : '重新寄送'),
                    variant: UbanButtonVariant.outline,
                    loading: _isSendingCode,
                    onPressed: (_isSendingCode || _isLoading || _resendRemaining > 0)
                        ? null
                        : _handleSendCode,
                  ),
                  const SizedBox(height: 14),
                  UbanTextField(
                    controller: _codeController,
                    label: '6 位數 Email 驗證碼',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    _passwordController,
                    '密碼',
                    isPassword: true,
                    onChanged: (_) => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: 14),

                  // ★ 第五十三輪 onboard53（家 4）：年齡／居住地改為必填，
                  //   在註冊表單一次收集，不再另開一個可略過的畫面。
                  AgeStepperField(
                    value: _age,
                    onChanged: (v) => setState(() {
                      _age = v;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 14),
                  // ★ 2026-10-06：一鍵定位按鈕（只在權限已授予時開頁自動帶入）
                  LocateCityButton(
                    resetNotifier: _locateReset,
                    autoLocateIfGranted: true,
                    canAutoFill: () =>
                        _residenceCity == null && _residenceDistrict == null,
                    onLocated: (city, district) => setState(() {
                      _residenceCity = city;
                      _residenceDistrict = district;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  CityDistrictPicker(
                    initialCity: _residenceCity,
                    initialDistrict: _residenceDistrict,
                    onChanged: (city, district) => setState(() {
                      _locateReset.value++; // 手動改選 → 清掉「已依位置填入」提示
                      _residenceCity = city;
                      _residenceDistrict = district;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '年齡與居住地僅用於平台統計分析，不會對外公開',
                    style: ubanText(14, FontWeight.w500, c.text3, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  // 同意條款（設計稿 .trow + .tick）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Semantics(
                        button: true,
                        checked: _agreedToTerms,
                        label: '同意隱私權政策與醫療免責聲明',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _agreedToTerms = !_agreedToTerms;
                              _errorMessage = null;
                            });
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: _TermsTick(checked: _agreedToTerms),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          textScaler: MediaQuery.textScalerOf(context),
                          text: TextSpan(
                            text: '我已閱讀並同意 ',
                            style: ubanText(16, FontWeight.w400, c.text2,
                                height: 1.5),
                            children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: GestureDetector(
                                  onTap: () => _showPrivacyPolicyDialog(context),
                                  child: Text(
                                    '《隱私權政策》',
                                    style: ubanText(
                                        16, FontWeight.w700, c.brandStrong,
                                        height: 1.5),
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: ' 與 ',
                                style: ubanText(16, FontWeight.w400, c.text2,
                                    height: 1.5),
                              ),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: GestureDetector(
                                  onTap: () => _showDisclaimerDialog(context),
                                  child: Text(
                                    '《醫療免責聲明》',
                                    style: ubanText(
                                        16, FontWeight.w700, c.brandStrong,
                                        height: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ★ 持久化錯誤橫幅：取代原本容易被忽略的 SnackBar，
                  //   確保使用者（包含自動化測試代理）能看到失敗原因並停留在畫面上。
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
                          Icon(Icons.error_outline_rounded, color: c.danger),
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

                  UbanButton(
                    label: '建立帳號',
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _handleRegister,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return UbanTextField(
      controller: controller,
      label: label,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      onChanged: onChanged,
      suffixIcon: isPassword
          ? IconButton(
              tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: UbanColors.of(context).text2,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            )
          : null,
    );
  }
}

/// 設計稿 `.tick`：40 圓，勾選後填品牌色並顯示勾。
class _TermsTick extends StatelessWidget {
  final bool checked;
  const _TermsTick({required this.checked});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? c.brandFill : Colors.transparent,
        border: Border.all(
            color: checked ? c.brandFill : c.surface3, width: 2.5),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 24, color: c.onBrand)
          : null,
    );
  }
}
