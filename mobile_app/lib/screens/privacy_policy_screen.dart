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
    if (_isSaving) return;
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 溫暖圖標與標題
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primaryGreen, _darkGreen],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primaryGreen.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.volunteer_activism_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '👵 歡迎使用 UBan 陪伴生活',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '專為長輩與家人量身打造的暖心守護服務',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _textBody.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. 「👵 3 秒安心導讀卡（完全免費、保護隱私、關懷長輩）」
                _buildQuickAssuranceCard(),

                const SizedBox(height: 22),

                // 3. 特大「同意並開始使用」按鈕
                _buildAcceptButton(),

                const SizedBox(height: 12),

                // 4. 輔助詳細法律條款超連結
                _buildDetailedPolicyLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 3 秒安心導讀卡
  Widget _buildQuickAssuranceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _primaryGreen.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: _darkGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '安心使用承諾（完全免費・保護隱私）',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _darkGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPillarItem(
            icon: Icons.money_off_csred_rounded,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF2E7D32),
            title: '完全免費安心用',
            desc: '本服務完全免費、絕無廣告干擾，絕不向長輩收取任何電話費或月租費，請放心安心使用。',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE2ECE5)),
          ),
          _buildPillarItem(
            icon: Icons.lock_outline_rounded,
            iconBg: const Color(0xFFE3F2FD),
            iconColor: const Color(0xFF1976D2),
            title: '嚴密保護您的隱私',
            desc: '您的聊天、用藥與位置資料皆經高規格安全加密，僅供您與家人關心，絕不外流外洩。',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE2ECE5)),
          ),
          _buildPillarItem(
            icon: Icons.favorite_rounded,
            iconBg: const Color(0xFFFCE4EC),
            iconColor: const Color(0xFFD81B60),
            title: '關懷長輩日常生活',
            desc: '定時提醒吃藥、一鍵視訊通話聯絡家人、外出平平安安定位，長輩與全家生活好幫手。',
          ),
        ],
      ),
    );
  }

  Widget _buildPillarItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  height: 1.45,
                  color: _textBody,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 特大「同意並開始使用」按鈕
  Widget _buildAcceptButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _accept,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
          shadowColor: _primaryGreen.withValues(alpha: 0.4),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 26, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    '同意並開始使用',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 查閱完整詳細條款
  Widget _buildDetailedPolicyLink() {
    return Center(
      child: TextButton.icon(
        onPressed: _openPolicyDetail,
        icon: const Icon(Icons.description_outlined, size: 16, color: Color(0xFF718096)),
        label: Text(
          '查閱完整法律條款與隱私權細則',
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF718096),
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
