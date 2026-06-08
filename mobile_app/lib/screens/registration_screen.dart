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
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ).value,
          child: Opacity(
            opacity: anim1.value,
            child: _ModernPolicyDialog(
              title: '醫療免責聲明',
              introText: '本聲明旨在明確界定系統非醫療器材，且不負擔因 AI 判斷、語音建議或緊急求救（SOS）延誤而產生的醫療法律責任。',
              headerIcon: Icons.gavel_rounded,
              primaryColor: const Color(0xFFFF7043),
              secondaryColor: const Color(0xFFFF8A65),
              sections: [
                _SectionData(
                  title: '1. 非醫療診斷與建議之提供',
                  icon: Icons.health_and_safety_outlined,
                  bulletPoints: [
                    '本服務所生成之所有語音、文字、圖表及分析結果，**僅供日常生活陪伴與一般健康促進參考**，不構成任何醫療診斷、藥物處方、臨床治療或專業醫學建議。',
                    '本服務所提供之內容，**絕不可替代**專業醫師、藥師或其他合格醫療人員之現場診斷或專業諮詢。',
                  ],
                ),
                _SectionData(
                  title: '2. 藥物提醒之限制',
                  icon: Icons.medication_outlined,
                  bulletPoints: [
                    '系統中之「用藥提醒」功能**僅作日常記事與備忘用途**。',
                    '本服務不對用藥種類、劑量、服用時間之絕對準確性承擔責任。',
                    '長輩與家屬應自行核對藥袋指示與藥師囑咐，並以真實藥物標示為準。',
                  ],
                ),
                _SectionData(
                  title: '3. AI 技術限制與幻覺免責',
                  icon: Icons.psychology_outlined,
                  bulletPoints: [
                    '用戶理解並同意，本服務之對話核心由**生成式人工智慧（Generative AI）**驅動。',
                    'AI 在對話中可能產生錯誤、不實、不完整或具誤導性之資訊（即**「AI 幻覺」**）。',
                    '本服務不保證 AI 對話內容的絕對正確性。使用者因信賴 AI 對話而採取或不採取任何行動，其所衍生之任何風險與損害，均由**用戶自行承擔**，本服務及其開發團隊不負任何損害賠償責任。',
                  ],
                ),
                _SectionData(
                  title: '4. 緊急求救（SOS）與視訊功能免責',
                  icon: Icons.emergency_share_outlined,
                  bulletPoints: [
                    '本服務之「緊急求救（SOS）通知家屬」功能依賴網際網路連線、推播通知系統及第三方通訊服務（如 Socket、Firebase）。',
                    '**本服務非內政部消防署之 119 通報系統，亦非緊急救護機關。**',
                    '如遇突發性重大身體不適、意外受傷或其他緊急狀況，**請立即撥打 119** 或求助於當地緊急醫療救援機構。',
                    '本服務對因網路中斷、系統延遲、硬體故障或任何原因導致求救通知延誤或未能送達家屬，所造成之傷亡或損害，均不承擔任何直接或間接之法律責任。',
                  ],
                ),
                _SectionData(
                  title: '5. 同意與受約束',
                  icon: Icons.assignment_turned_in_outlined,
                  bulletPoints: [
                    '使用本服務即代表您（長輩及家屬）已閱讀、理解並**完全同意本免責聲明之全部內容**。',
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ).value,
          child: Opacity(
            opacity: anim1.value,
            child: _ModernPolicyDialog(
              title: '隱私權保護政策',
              introText: '為了讓您能安心使用「UBan」各項服務，特此向您說明本服務的隱私權保護政策，以保障您的權益，請詳閱下列內容：',
              headerIcon: Icons.shield_outlined,
              primaryColor: const Color(0xFF0284C7),
              secondaryColor: const Color(0xFF0EA5E9),
              sections: [
                _SectionData(
                  title: '1. 個人資料之收集範圍',
                  icon: Icons.assignment_ind_outlined,
                  bulletPoints: [
                    '**家屬帳號資訊**：家屬姓名、Email、登入密碼、聯絡電話。',
                    '**長輩基本資料**：長輩姓名、居住地區、稱謂偏好、慢性病史、用藥習慣與提醒備忘錄。',
                    '**互動與多媒體資料**：長輩與 AI 對話之語音音訊、拍攝或上傳之影像、系統互動日誌（情緒標籤、通話紀錄等）。',
                  ],
                ),
                _SectionData(
                  title: '2. 資料使用目的與方式',
                  icon: Icons.insights_outlined,
                  bulletPoints: [
                    '**日常陪伴與對話生成**：將長輩的背景資料作為 AI 提示詞脈絡，以生成更親切、精準且具溫度的對話。',
                    '**家屬端儀表板呈現**：將長輩的活動日誌、情緒狀態及每日活動趨勢摘要呈現給家屬。',
                    '**語音與影像辨識**：處理長輩發送之語音與影像，以轉換為對應之文字與指令。',
                    '**緊急通知發送**：於長輩觸發 SOS 求救時，利用聯絡資料發送即時推播通知。',
                    '**系統改善**：去識別化後之互動統計分析，用於優化系統與 AI 回應品質。',
                  ],
                ),
                _SectionData(
                  title: '3. 資料儲存與保護機制',
                  icon: Icons.lock_outline,
                  bulletPoints: [
                    '**資料安全**：採用符合業界標準之安全防護措施（如 SSL/TLS 傳輸加密、資料庫加密儲存）。',
                    '**敏感資料最小化**：長輩的健康史與用藥備忘錄僅儲存於安全的加密資料庫中，且僅由授權 API 用於上下文注入，不作大範圍機器學習訓練。',
                    '**語音/影像暫存**：長輩發送的語音檔與圖片，於 API 處理完成後定期進行清理與去識別化。',
                  ],
                ),
                _SectionData(
                  title: '4. 與第三方共用個人資料之政策',
                  icon: Icons.share_outlined,
                  bulletPoints: [
                    '本服務**絕不會任意出售、交換、或出租**任何您的個人資料給其他團體或個人。',
                    '**第三方 AI 服務供應商**：在處理對話時，會將**「去識別化後」**之對話文字與上下文傳送予第三方 LLM API（如 Google Gemini API）以獲取回應。',
                    '**法律與避難**：配合司法機關調查，或為防免長輩生命、身體急迫危險時，得依法提供必要資訊。',
                  ],
                ),
                _SectionData(
                  title: '5. 使用者權利',
                  icon: Icons.admin_panel_settings_outlined,
                  bulletPoints: [
                    '您隨時可以查詢、閱覽、補充或更正您與長輩的個人資料。',
                    '**刪除帳號**：一旦刪除帳號，系統將在 30 天內完全清除與該帳號相關之所有個人歷史對話與日誌。',
                  ],
                ),
                _SectionData(
                  title: '6. 隱私權保護政策之修改',
                  icon: Icons.published_with_changes_outlined,
                  bulletPoints: [
                    '政策將因應法規與需求調整，修正後的條款將公告於 App 內並提示同意。',
                  ],
                ),
              ],
            ),
          ),
        );
      },
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

class _SectionData {
  final String title;
  final IconData icon;
  final List<String> bulletPoints;

  const _SectionData({
    required this.title,
    required this.icon,
    required this.bulletPoints,
  });
}

class _ModernPolicyDialog extends StatefulWidget {
  final String title;
  final String introText;
  final List<_SectionData> sections;
  final Color primaryColor;
  final Color secondaryColor;
  final IconData headerIcon;

  const _ModernPolicyDialog({
    required this.title,
    required this.introText,
    required this.sections,
    required this.primaryColor,
    required this.secondaryColor,
    required this.headerIcon,
  });

  @override
  State<_ModernPolicyDialog> createState() => _ModernPolicyDialogState();
}

class _ModernPolicyDialogState extends State<_ModernPolicyDialog> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onScroll();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0) {
      setState(() {
        _scrollProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
      });
    } else {
      setState(() {
        _scrollProgress = 1.0;
      });
    }
  }

  bool get _isFullyRead {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return true;
    return _scrollProgress >= 0.92;
  }

  @override
  Widget build(BuildContext context) {
    final bool isRead = _isFullyRead;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. Header (Gradient background with icon & title)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [widget.primaryColor, widget.secondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.headerIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "最後更新：2026 年 6 月 4 日",
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // 2. Scroll Progress bar
            Container(
              height: 4,
              width: double.infinity,
              color: widget.primaryColor.withValues(alpha: 0.1),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _scrollProgress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.primaryColor, widget.secondaryColor],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Scrollable Content
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbColor: widget.primaryColor.withValues(alpha: 0.3),
                radius: const Radius.circular(4),
                thickness: 4,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Intro Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.primaryColor.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: widget.primaryColor,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.introText,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 12.5,
                                  color: widget.primaryColor.withValues(alpha: 0.85),
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Section list
                      ...widget.sections.asMap().entries.map((entry) {
                        return _buildSectionCard(entry.value, entry.key + 1);
                      }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Bottom Action Area
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isRead
                                ? [widget.primaryColor, widget.secondaryColor]
                                : [Colors.grey[400]!, Colors.grey[500]!],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: isRead
                                  ? widget.primaryColor.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            if (isRead) {
                              Navigator.pop(context);
                            } else {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isRead ? Icons.check_circle_outline : Icons.arrow_downward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRead ? '我已閱讀並理解' : '向下滾動閱讀全文',
                                style: GoogleFonts.notoSansTc(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(_SectionData section, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: widget.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: widget.primaryColor.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            section.icon,
                            size: 16,
                            color: widget.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            section.title,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...section.bulletPoints.map((point) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0, right: 8.0),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: widget.primaryColor.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RichText(
                                  text: _parseFormattedText(point),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _parseFormattedText(String text) {
    final List<TextSpan> children = [];
    final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in regExp.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(
          text: text.substring(start, match.start),
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            color: const Color(0xFF4B5563),
            height: 1.5,
          ),
        ));
      }
      children.add(TextSpan(
        text: match.group(1),
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
          height: 1.5,
        ),
      ));
      start = match.end;
    }

    if (start < text.length) {
      children.add(TextSpan(
        text: text.substring(start),
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          color: const Color(0xFF4B5563),
          height: 1.5,
        ),
      ));
    }

    return TextSpan(children: children);
  }
}
