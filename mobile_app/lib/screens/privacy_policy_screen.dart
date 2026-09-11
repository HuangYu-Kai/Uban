import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/privacy_policy_content.dart';
import '../services/video_call_permission_service.dart';
import '../widgets/policy_detail_dialog.dart';
import 'identification_screen.dart';

/// ★ 2026-08-23 建立、2026-09-11 第四十五輪改為「勾選同意」形式。
///
/// 首次安裝的隱私權政策關卡。只會在「本機從未同意過本版政策」時顯示一次，
/// 同意後由這裡直接 `pushAndRemoveUntil` 到 [IdentificationScreen]，之後
/// 每次啟動都不會再看到這一頁（見 `splash_screen.dart::_goNext()` 的守門邏輯）。
///
/// ⚠️ 本頁刻意不修改、也不需要修改 `splash_screen.dart` / `main.dart` 的
/// 導航邏輯——那兩個檔案只引用 [prefsKey] 這個常數本身，改鍵名或改畫面
/// 內容都會自動生效（見 `splash_screen.dart::_goNext()` 上方的安全性論證：
/// 能走到 `_goNext()` 的唯一情境是「無待接聽來電、且判斷不出任何本機
/// session」，正是唯一需要顯示本頁的時機，不會擋到待接聽來電）。
///
/// 政策全文集中於 [PrivacyPolicyContent]（見 `../data/privacy_policy_content.dart`），
/// 與家屬註冊頁 (`registration_screen.dart`) 共用同一份資料，兩處只是呈現方式
/// 不同：這裡是精簡的勾選同意頁，點擊「隱私權政策」超連結才彈出完整內容。
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  /// 與 `splash_screen.dart` 共用的字面量鍵——兩處各自持有一份常數字串
  /// （比照本專案 `pendingAcceptedCall` 等鍵位跨檔案以字面量重複的既有寫法），
  /// 修改鍵名時務必兩邊同步。
  ///
  /// 2026-09-11 由 `_v1` 升版為 `_v2`：政策內容大幅擴充（新增 CCTV／YOLO
  /// 監控、Pinecone 長期記憶、GPS／IPS 定位、第三方服務共用範圍等章節），
  /// 依既有設計意圖（見下方原註解）屬於「重大變更」，故升版讓已同意舊版的
  /// 使用者於下次啟動時重新看過新版並再次同意。
  ///
  /// 未來政策內容若再有重大變更，只需改用新的 key（例如 `_v3`），即可讓所有
  /// 裝置在下次啟動時重新看到最新版本，不需要額外的「政策版本比對」邏輯。
  static const String prefsKey = 'privacy_policy_accepted_v2';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static const Color _primaryGreen = Color(0xFF59B294);
  static const Color _darkGreen = Color(0xFF2F7A63);
  static const Color _textDark = Color(0xFF3A3A3A);
  static const Color _textBody = Color(0xFF4A4A4A);
  static const Color _background = Color(0xFFFDFDFB);

  bool _isSaving = false;
  bool _agreed = false;

  void _openPolicyDetail() {
    PolicyDetailDialog.show(
      context,
      title: PrivacyPolicyContent.title,
      introText: PrivacyPolicyContent.introText,
      headerIcon: Icons.privacy_tip_outlined,
      primaryColor: _primaryGreen,
      secondaryColor: _darkGreen,
      sections: PrivacyPolicyContent.sections,
      lastUpdated: '最後更新：${PrivacyPolicyContent.lastUpdated}',
    );
  }

  Future<void> _accept() async {
    if (_isSaving || !_agreed) return;
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      await prefs.setBool(PrivacyPolicyScreen.prefsKey, true);
    } catch (e) {
      // ★ 寫入失敗不阻擋使用者：本頁不是通話路徑，沒有「卡住」的風險。
      //   最壞情況只是下次啟動再看到一次本頁，不會讓 App 無法使用。
      debugPrint('⚠️ [PrivacyPolicy] 寫入同意狀態失敗（不影響繼續使用）: $e');
    }

    // ★ 2026-08-31 第三十七輪：權限請求移到這裡——同意隱私權政策之後才要權限，
    //   順序正確，也避免了 splash 的 pushReplacement 把權限對話框換掉
    //   （詳見 main.dart 對應註解）。await 到完成再導航，確保對話框不會被
    //   接下來的 pushAndRemoveUntil 取代。
    if (mounted) {
      await VideoCallPermissionService.requestOnFirstUse(context);
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IdentificationScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  size: 56,
                  color: _primaryGreen,
                ),
                const SizedBox(height: 20),
                Text(
                  '開始使用 UBan 之前',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '為了保障您與長輩的權益，請詳閱本服務的隱私權政策後再繼續使用。',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    height: 1.6,
                    color: _textBody,
                  ),
                ),
                const SizedBox(height: 28),
                _buildConsentRow(),
                const SizedBox(height: 24),
                _buildAcceptButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConsentRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: _agreed,
            activeColor: _primaryGreen,
            onChanged: (val) => setState(() => _agreed = val ?? false),
          ),
          // ★ 溢位規則（CLAUDE.md 3.1 #14）：勾選同意列是 Checkbox + 長文字
          //   + 超連結同一個 Row 最容易溢位的組合。這裡用 Expanded 包住
          //   Text.rich，讓整句話（含超連結）在窄螢幕上自動換行，
          //   而不是把合約文字截斷成刪節號——同意文字不適合被省略顯示。
          Expanded(
            child: Text.rich(
              TextSpan(
                text: '同意',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  color: _textDark,
                  height: 1.4,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: _openPolicyDetail,
                      child: Text(
                        '《隱私權政策》',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                          decoration: TextDecoration.underline,
                          decorationColor: _darkGreen,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(
                    text: '並使用 APP',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      color: _textDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptButton() {
    final bool canProceed = _agreed && !_isSaving;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canProceed ? _accept : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryGreen,
          disabledBackgroundColor: _primaryGreen.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                '使用 APP',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
