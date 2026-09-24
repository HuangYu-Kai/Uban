import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/privacy_policy_content.dart';
import '../services/api_service.dart';
import '../widgets/policy_detail_dialog.dart';
import '../widgets/age_stepper_field.dart';
import '../widgets/city_district_picker.dart';
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

  bool _isLoading = false;
  bool _agreedToTerms = true;
  // ★ 持久化錯誤訊息：取代原本的 SnackBar，避免使用者錯過失敗原因（見第 27 輪卡關根因）
  String? _errorMessage;

  // ★ 第五十三輪 onboard53：年齡／居住地改為必填（家 4）。使用者明確決定
  //   「由選填改為必填，不再允許沒填就跳過」，故這三個欄位沒有預設值、
  //   沒有「以後再說」的出路——送出前會擋在 _handleRegister() 裡。
  //   僅收集到縣市／行政區（不含街道門牌），因為這筆資料只用於開發者統計。
  int? _age;
  String? _residenceCity;
  String? _residenceDistrict;

  void _showDisclaimerDialog(BuildContext context) {
    PolicyDetailDialog.show(
      context,
      title: '醫療免責聲明',
      introText: '本聲明旨在明確界定系統非醫療器材，且不負擔因 AI 判斷、語音建議或緊急求救（SOS）延誤而產生的醫療法律責任。',
      headerIcon: Icons.gavel_rounded,
      primaryColor: const Color(0xFFFF7043),
      secondaryColor: const Color(0xFFFF8A65),
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
      primaryColor: const Color(0xFF0284C7),
      secondaryColor: const Color(0xFF0EA5E9),
      sections: PrivacyPolicyContent.sections,
      lastUpdated: '最後更新：${PrivacyPolicyContent.lastUpdated}',
    );
  }

  /// ★ 將後端錯誤負載轉為可顯示的繁體中文字串。
  /// FastAPI 422 驗證錯誤的 `detail` 是 List（例如密碼長度不足），
  /// 若直接丟進 Text() 會是執行期型別錯誤，必須先轉字串。
  String _readableError(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
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
    return '註冊失敗，請稍後再試';
  }

  Future<void> _handleRegister() async {
    setState(() => _errorMessage = null);

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
          _errorMessage = _readableError(result['error'] ?? result['detail']);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '連線失敗，請檢查網路後再試一次');
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

              _buildTextField(
                _nameController,
                '您的姓名',
                Icons.person_outline,
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                _emailController,
                'Email',
                Icons.email_outlined,
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                _passwordController,
                '密碼',
                Icons.lock_outline,
                isPassword: true,
                onChanged: (_) => setState(() => _errorMessage = null),
              ),
              const SizedBox(height: 24),

              // ★ 第五十三輪 onboard53（家 4）：年齡／居住地改為必填，
              //   在註冊表單一次收集，不再另開一個可略過的畫面。
              Text(
                '年齡與居住地',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '僅用於平台統計分析，不會對外公開',
                style: GoogleFonts.notoSansTc(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              AgeStepperField(
                value: _age,
                onChanged: (v) => setState(() {
                  _age = v;
                  _errorMessage = null;
                }),
              ),
              const SizedBox(height: 16),
              CityDistrictPicker(
                initialCity: _residenceCity,
                initialDistrict: _residenceDistrict,
                onChanged: (city, district) => setState(() {
                  _residenceCity = city;
                  _residenceDistrict = district;
                  _errorMessage = null;
                }),
              ),
              const SizedBox(height: 24),

              // 同意條款 Checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreedToTerms,
                    activeColor: const Color(0xFFFF7043),
                    onChanged: (val) {
                      setState(() {
                        _agreedToTerms = val ?? false;
                        _errorMessage = null;
                      });
                    },
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        text: '我已閱讀並同意 ',
                        style: GoogleFonts.notoSansTc(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () => _showPrivacyPolicyDialog(context),
                              child: Text(
                                '《隱私權政策》',
                                style: GoogleFonts.notoSansTc(
                                  color: const Color(0xFFFF7043),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          TextSpan(
                            text: ' 與 ',
                            style: GoogleFonts.notoSansTc(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () => _showDisclaimerDialog(context),
                              child: Text(
                                '《醫療免責聲明》',
                                style: GoogleFonts.notoSansTc(
                                  color: const Color(0xFFFF7043),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ★ 持久化錯誤橫幅：取代原本容易被忽略的 SnackBar，
              //   確保使用者（包含自動化測試代理）能看到失敗原因並停留在畫面上。
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDC2626)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

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

              const SizedBox(height: 16),
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
    ValueChanged<String>? onChanged,
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
        onChanged: onChanged,
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
