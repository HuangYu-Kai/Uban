import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/privacy_policy_content.dart';
import '../services/video_call_permission_service.dart';
import '../widgets/policy_detail_dialog.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';
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
  ///
  /// 2026-09-30 由 `_v2` 升版為 `_v3`：第 9 節新增長輩端**背景持續** GPS 定位
  /// 與移動軌跡（且位置分享系統預設開啟），屬於新增資料蒐集項目的重大變更。
  static const String prefsKey = 'privacy_policy_accepted_v3';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  bool _isSaving = false;

  void _openPolicyDetail() {
    PolicyDetailDialog.show(
      context,
      title: PrivacyPolicyContent.title,
      introText: PrivacyPolicyContent.introText,
      headerIcon: Icons.privacy_tip_outlined,
      primaryColor: UbanColors.of(context).brandStrong,
      secondaryColor: UbanColors.of(context).brandFill,
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
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 32),
            child: ConstrainedBox(
              // 內容不足一屏時，CTA 沉到底部；內容超出（小螢幕／大字級）則整頁可捲。
              constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 60).clamp(0.0, double.infinity),
                  maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: UbanMarkBox(child: UbanHeartMark()),
                      ),
                      const SizedBox(height: 22),
                      Text('開始之前，\n先跟您說三件事', style: ubanH1(context)),
                      const SizedBox(height: 22),
                      // 三個安心承諾
                      _buildPillarItem(
                        icon: Icons.check_circle_outline_rounded,
                        title: '完全免費安心用',
                        desc: '基本功能不收費，不會偷偷扣款',
                      ),
                      const SizedBox(height: 10),
                      _buildPillarItem(
                        icon: Icons.verified_user_outlined,
                        title: '嚴密保護您的隱私',
                        desc: '資料只給您配對的家人看',
                      ),
                      const SizedBox(height: 10),
                      _buildPillarItem(
                        icon: Icons.favorite_border_rounded,
                        title: '關懷長輩日常生活',
                        desc: '提醒吃藥、陪聊天、一鍵視訊',
                      ),
                      const SizedBox(height: 26),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 特大「同意並開始使用」按鈕
                      UbanButton(
                        label: '同意並開始使用',
                        size: UbanButtonSize.xl,
                        loading: _isSaving,
                        onPressed: _isSaving ? null : _accept,
                      ),
                      const SizedBox(height: 6),
                      // 輔助詳細法律條款
                      UbanButton(
                        label: '閱讀完整條款',
                        variant: UbanButtonVariant.ghost,
                        onPressed: _openPolicyDetail,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 設計稿卡片列：52 圖示底＋標題 20/900＋說明 16。
  Widget _buildPillarItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final c = UbanColors.of(context);
    return UbanCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 24, color: c.brandStrong),
          ),
          const SizedBox(width: 16),
          // 標題／說明可收縮換行，大字級不溢位。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: ubanText(20, FontWeight.w900, c.text, height: 1.3)),
                const SizedBox(height: 2),
                Text(desc,
                    style:
                        ubanText(16, FontWeight.w400, c.text2, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
