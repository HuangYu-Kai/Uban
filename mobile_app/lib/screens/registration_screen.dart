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

  bool _isLoading = false;
  bool _agreedToTerms = false;

  void _showDisclaimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'UBan 醫療免責聲明',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              '【1. 非醫療診斷與建議之提供】\n'
              '本服務所生成之所有語音、文字、圖表及分析結果，僅供日常生活陪伴與一般健康促進參考，不構成任何醫療診斷、藥物處方、臨床治療或專業醫學建議。本服務所提供之內容，絕不可替代專業醫師、藥師或其他合格醫療人員之現場診斷或專業諮詢。\n\n'
              '【2. 藥物提醒之限制】\n'
              '系統中之「用藥提醒」功能僅作日常記事與備忘用途。本服務不對用藥種類、劑量、服用時間之絕對準確性承擔責任。長輩與家屬應自行核對藥袋指示與藥師囑咐，並以真實藥物標示為準。\n\n'
              '【3. AI 技術限制與幻覺免責】\n'
              '用戶理解並同意，本服務之對話核心由生成式人工智慧（Generative AI）驅動。AI 在對話中可能產生錯誤、不實、不完整或具誤導性之資訊（即「AI 幻覺」）。本服務不保證 AI 對話內容的絕對正確性。使用者因信賴 AI 對話內容而採取或不採取任何行動，其所衍生之任何風險與損害，均由用戶自行承擔，本服務及其開發團隊不負任何損害賠償責任。\n\n'
              '【4. 緊急求救（SOS）與視訊功能免責】\n'
              '本服務之「緊急求救（SOS）通知家屬」功能依賴網際網路連線、推播通知系統及第三方通訊服務（如 Socket、Firebase）。本服務非內政部消防署之 119 通報系統，亦非緊急救護機關。如遇突發性重大身體不適、意外受傷或其他緊急狀況，請立即撥打 119 或求助於當地緊急醫療救援機構。本服務對於因網路中斷、系統延遲、硬體故障或任何原因導致求救通知延誤或未能送達家屬，所造成之傷亡或損害，均不承擔任何直接或間接之法律責任。\n\n'
              '【5. 同意與受約束】\n'
              '使用本服務即代表您（長輩及家屬）已閱讀、理解並完全同意本免責聲明之全部內容。',
              style: GoogleFonts.notoSansTc(fontSize: 14, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '關閉',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'UBan 隱私權保護政策',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              '【1. 個人資料之收集範圍】\n'
              '本服務將依功能需求收集：家屬姓名、Email、登入密碼；長輩姓名、居住地區、稱謂偏好、慢性病史、用藥習慣與提醒備忘錄；長輩與 AI 對話之語音音訊（用於 STT）；長輩拍攝或上傳之影像及系統互動日誌。\n\n'
              '【2. 資料使用目的與方式】\n'
              '收集的資料將用於：日常陪伴與對話生成之脈絡優化、家屬端儀表板健康與情緒狀態呈現、語音與影像指令辨識、緊急通知發送以及去識別化後之系統優化。\n\n'
              '【3. 資料儲存與保護機制】\n'
              '我們採用符合業界標準之防護措施（如 SSL/TLS 傳輸加密、資料庫加密儲存）。長輩的健康史與用藥備忘錄僅儲存於安全的加密資料庫中，且語音/影像暫存檔會定期進行清理與去識別化。\n\n'
              '【4. 與第三方共用個人資料之政策】\n'
              '本服務不會出售或出租個人資料。但在對話生成時，我們會將「去識別化後」之對話文字傳送予第三方 LLM API（如 Google Gemini API）以獲取 AI 回應。另於配合司法機關調查或緊急防免生命危害時，亦得依法提供或揭露資訊。\n\n'
              '【5. 使用者權利】\n'
              '您隨時可以查詢、閱覽或更正個人資料。如刪除帳號，系統將在 30 天內完全清除所有歷史對話與日誌。\n\n'
              '【6. 隱私權政策之修改】\n'
              '政策將因應法規與需求調整，修正後的條款將公告於 App 內並提示同意。',
              style: GoogleFonts.notoSansTc(fontSize: 14, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '關閉',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫所有欄位')));
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請先閱讀並同意隱私權政策與醫療免責聲明'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ApiService.register(
        username: name,
        email: email,
        password: password,
        role: 'family', // 子女端註冊
      );

      if (!mounted) return;

      // API 回傳格式: { status: "success", data: { user_id, ... } }
      final data = result['data'];
      if (result['status'] == 'success' && data != null && data['user_id'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('註冊成功，請登入')),
        );
        Navigator.pop(context); // 回到登入頁
      } else {
        // 顯示錯誤訊息
        final errorMsg = result['error'] ?? result['detail'] ?? '註冊失敗';
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
