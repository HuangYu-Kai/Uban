import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/age_stepper_field.dart';
import '../services/api_service.dart';
import '../widgets/ui/ui.dart';
import '../widgets/login_flow_parts.dart';
import 'qr_scanner_screen.dart';
import 'elder_selection_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';

/// 從 QR Code 或輸入文字取出 4 位數配對碼；不是剛好 4 位數字則回傳 null。
String? extractPairingCode(String raw) {
  final t = raw.trim();
  return RegExp(r'^\d{4}$').hasMatch(t) ? t : null;
}

class CaregiverPairingScreen extends StatefulWidget {
  final int familyId;
  final String familyName;

  const CaregiverPairingScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  @override
  State<CaregiverPairingScreen> createState() => _CaregiverPairingScreenState();
}

class _CaregiverPairingScreenState extends State<CaregiverPairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  // ★ 2026-10-06 登入流程改善：年齡改為選填且預設留空（不再預填 '70'）。
  //   家屬知道就填；不確定留空，長輩第一次登入的補填畫面會自己選。
  final TextEditingController _ageController = TextEditingController();
  // ★ 2026-10-06 登入流程審查：性別預設「不填」（null），不再替家屬預設成男性；
  //   後端 /pairing/confirm 已接受 gender = null。
  String? _gender;
  bool _isLoading = false;
  // ★ 持久化錯誤訊息：取代原本的 SnackBar，避免 409/410/404 都顯示同一句看不出差異的訊息
  String? _errorMessage;

  /// ★ 將後端錯誤負載轉為可顯示的繁體中文字串（與 registration_screen.dart 同樣的處理邏輯，
  /// 因改動範圍要求維持獨立，故各自保留一份，不抽共用 util）。
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
    return '配對沒有成功，請確認配對碼後再試一次';
  }

  /// ★ 2026-10-06 登入流程審查：後端 detail 現為中文可直接顯示；
  /// 但若仍含英文技術字樣（Exception／Error／status code…）或舊的「連線失敗」，
  /// 一律改成友善預設，避免把技術訊息丟給家屬。
  String _friendlyPairingError(dynamic raw) {
    final text = _readableError(raw);
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    final looksTechnical = RegExp(
            r'exception|error|socket|timeout|failed|null|\b[45]\d\d\b|<|\{',
            caseSensitive: false)
        .hasMatch(text);
    if (!hasCjk || looksTechnical || text.contains('連線失敗')) {
      debugPrint('⚠️ [CaregiverPairing] 後端錯誤原文: $text');
      return '目前連不上伺服器，請確認網路後再試一次';
    }
    return text;
  }

  Future<void> _handleConfirmPairing() async {
    setState(() => _errorMessage = null);

    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final ageText = _ageController.text.trim();
    final int? age = ageText.isEmpty ? null : int.tryParse(ageText);

    if (code.length != 4) {
      setState(() => _errorMessage = '請輸入 4 位配對碼');
      return;
    }

    if (name.isEmpty) {
      setState(() => _errorMessage = '請輸入長輩姓名');
      return;
    }

    // 有填才驗證範圍（與長輩端 AgeStepperField 一致：1～120）；留空送 null。
    if (ageText.isNotEmpty &&
        (age == null ||
            age < AgeStepperField.minAge ||
            age > AgeStepperField.maxAge)) {
      setState(() => _errorMessage =
          '年齡請輸入 ${AgeStepperField.minAge}～${AgeStepperField.maxAge} 的數字，或留空');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.confirmPairing(
        familyId: widget.familyId,
        code: code,
        elderName: name,
        gender: _gender,
        age: age,
      );

      if (!mounted) return;

      // 檢查響應結構：{ status: "success", data: { elder_id, elder_profile_id, ... } }
      final data = result['data'] as Map<String, dynamic>?;
      if (result['status'] == 'success' && data != null && data.containsKey('elder_id')) {
        // 配對成功！
        setState(() => _errorMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('配對成功！已建立守護關係 ✨'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: UbanColors.of(context).brandFill,
          ),
        );

        // 配對完成後，導向長輩選擇頁面（子女端首頁）
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => ElderSelectionScreen(
              userId: widget.familyId,
              userName: widget.familyName,
            ),
          ),
          (route) => false, // 清除所有舊頁面，防止回到配對或引導頁
        );
      } else {
        // ★ 補讀 result['detail']：後端 /api/pairing/confirm 一律以 HTTPException 回傳，
        //   回應本體是 { "detail": "..." }，原本漏讀 detail 導致 409/410/404 都顯示同一句
        //   「配對失敗，請檢查配對碼」，使用者無從分辨代碼已被使用／已過期／不存在。
        setState(() {
          _errorMessage = _friendlyPairingError(
            result['detail'] ?? result['error'] ?? result['message'] ?? data?['message'],
          );
        });
      }
    } catch (e) {
      debugPrint('⚠️ [CaregiverPairing] confirmPairing 例外: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '目前連不上伺服器，請確認網路後再試一次');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    // ★ 2026-09-01 第三十九輪 item 2：改走 SessionManager.releaseSession()，
    //   不可再用 prefs.clear()——那會把整個 SharedPreferences 洗空，連字體
    //   大小、通知偏好、wake_word_enabled 等與帳號無關的設定、以及長輩端
    //   保留的 last_elder_* 快速登入記憶鍵（護欄 G24／G125）都一併清掉。
    //   使用者常用同一支手機輪流測試家屬端與長輩端，這裡呼叫 prefs.clear()
    //   會導致「長輩登出後無法快速登入同一長輩」。
    //   不帶 preserveQuickLogin（維持預設 false＝全清）：那個參數只給長輩
    //   自己登出時保留記憶用，家屬端登出語意上是「這台裝置的授權已收回」，
    //   本就該全清，見 session_manager.dart 的參數註解。
    await SessionManager.releaseSession();

    // 同步登出第三方
    await AuthService.signOutGoogle();
    await AuthService.signOutLine();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (result != null && mounted) {
      // ★ 2026-10-06：QR 內容直接 .text= 會繞過 maxLength；
      //   只接受剛好 4 位數字，其餘視為不是 Uban 的 QR Code。
      final scanned = extractPairingCode(result);
      if (scanned != null) {
        setState(() {
          _codeController.text = scanned;
          _errorMessage = null;
        });
      } else {
        setState(() => _errorMessage =
            '這不是 Uban 的配對 QR Code，請掃描長輩手機上的 QR Code');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          '新增長輩連結',
          style: ubanText(18, FontWeight.w800, c.text),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: c.text,
        actions: [
          IconButton(
            onPressed: _handleLogout,
            icon: Icon(Icons.logout_rounded, color: c.danger),
            tooltip: '登出',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(Icons.favorite, size: 64, color: c.brand),
                  const SizedBox(height: 16),
                  Text('建立守護關係', style: ubanH1(context, size: 24)),
                  const SizedBox(height: 8),
                  Text(
                    '請看長輩手機上的 4 位數配對碼\n並填寫長輩的資訊開始守護',
                    textAlign: TextAlign.center,
                    style: ubanText(14, FontWeight.w400, c.text2, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionLabel('1. 連結長輩的手機'),
            UbanButton(
              label: '掃描長輩手機上的 QR Code',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: _isLoading ? null : _scanQr,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: c.line)),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '或手動輸入 4 位數配對碼',
                      textAlign: TextAlign.center,
                      style: ubanText(13, FontWeight.w600, c.text3),
                    ),
                  ),
                ),
                Expanded(child: Divider(color: c.line)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: ubanText(26, FontWeight.w800, c.text,
                  letterSpacingEm: 0.3),
              cursorColor: c.brandStrong,
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: _inputDecoration(
                Icons.vpn_key_rounded,
                '4 位數字',
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('2. 長輩基本資訊'),
            TextField(
              controller: _nameController,
              style: ubanText(18, FontWeight.w400, c.text),
              cursorColor: c.brandStrong,
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: _inputDecoration(
                Icons.person_add_rounded,
                '長輩名稱 (例如：王大明)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: ubanText(18, FontWeight.w400, c.text),
              cursorColor: c.brandStrong,
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: _inputDecoration(Icons.cake_rounded, '年齡（選填）'),
            ),
            const SizedBox(height: 16),
            // ★ 2026-10-06：性別三選一（男／女／不填），獨立一整列，三格各佔 1/3 不會溢位。
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _genderChoice(
                    label: '男',
                    isSelected: _gender == 'M',
                    onTap: () => setState(() => _gender = 'M'),
                  ),
                  _genderChoice(
                    label: '女',
                    isSelected: _gender == 'F',
                    onTap: () => setState(() => _gender = 'F'),
                  ),
                  _genderChoice(
                    label: '不填',
                    isSelected: _gender == null,
                    onTap: () => setState(() => _gender = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 說明文字獨立一行（不放進窄欄位的 hint，避免被截斷／溢位）
            Text(
              '年齡、性別不確定都可以不填，長輩登入時會自己填',
              style: ubanText(13, FontWeight.w400, c.text3),
            ),
            const SizedBox(height: 32),

            // ★ 持久化錯誤橫幅：取代原本容易被忽略的 SnackBar，並補讀後端 detail 欄位，
            //   讓 409（代碼已被使用）/410（已過期）/404（代碼不存在）顯示各自的真實原因。
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.dangerContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.danger),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, color: c.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: ubanText(15, FontWeight.w700, c.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            UbanButton(
              label: '開始配對',
              loading: _isLoading,
              onPressed: _isLoading ? null : _handleConfirmPairing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: ubanText(15, FontWeight.w700, UbanColors.of(context).text),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String label) {
    final c = UbanColors.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: ubanText(16, FontWeight.w400, c.text3),
      floatingLabelStyle: ubanText(16, FontWeight.w400, c.brandStrong),
      prefixIcon: Icon(icon, size: 22, color: c.text2),
      filled: true,
      fillColor: c.surface2,
      counterText: "",
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.brand, width: 1.5),
      ),
    );
  }

  Widget _genderChoice({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? UbanColors.of(context).surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: ubanText(
              16,
              isSelected ? FontWeight.w700 : FontWeight.w400,
              isSelected
                  ? UbanColors.of(context).brandStrong
                  : UbanColors.of(context).text2,
            ),
          ),
        ),
      ),
    );
  }
}
