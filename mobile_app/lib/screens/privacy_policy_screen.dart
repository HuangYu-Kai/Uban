import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'identification_screen.dart';

/// ★ 2026-08-23：首次安裝的隱私權政策關卡。
///
/// 只會在「本機從未同意過本版政策」時顯示一次，同意後由這裡直接
/// `pushAndRemoveUntil` 到 [IdentificationScreen]，之後每次啟動都不會再看到
/// 這一頁（見 `splash_screen.dart::_goNext()` 的守門邏輯）。
///
/// `prefsKey` 帶版本號（`_v1`）：未來政策內容若有重大變更，只需改用新的
/// key（例如 `_v2`），即可讓所有裝置在下次啟動時重新看到最新版本，不需要
/// 額外的「政策版本比對」邏輯。
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  /// 與 `splash_screen.dart` 共用的字面量鍵——兩處各自持有一份常數字串
  /// （比照本專案 `pendingAcceptedCall` 等鍵位跨檔案以字面量重複的既有寫法），
  /// 修改鍵名時務必兩邊同步。
  static const String prefsKey = 'privacy_policy_accepted_v1';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static const Color _primaryGreen = Color(0xFF59B294);
  static const Color _textDark = Color(0xFF3A3A3A);
  static const Color _textBody = Color(0xFF4A4A4A);
  static const Color _background = Color(0xFFFDFDFB);

  bool _isSaving = false;

  static const List<_DisclosureItem> _items = [
    _DisclosureItem(
      icon: Icons.chat_bubble_outline,
      lead: 'AI 對話與陪伴記憶',
      body: '您與 AI 的對話內容會被記錄並轉換成資料，儲存為長期記憶，'
          '用於延續話題、生成貼心的關懷提醒與每日話題建議。',
    ),
    _DisclosureItem(
      icon: Icons.videocam_outlined,
      lead: '鏡頭影像分析（跌倒偵測／室內定位）',
      body: '當裝置設定為監控模式時，會持續擷取畫面並以 AI 分析人物動作，'
          '用於偵測跌倒、久躺等異常狀況，並可能藉此推估長輩所在的大致'
          '居家區域（例如客廳、臥室）。',
    ),
    _DisclosureItem(
      icon: Icons.mic_none_outlined,
      lead: '語音轉文字',
      body: '透過語音進行的對話或指令，會被系統轉換為文字，以提供辨識與回應。',
    ),
    _DisclosureItem(
      icon: Icons.mood_outlined,
      lead: '情緒傾向分析',
      body: '系統會透過 AI 分析對話文字內容判斷情緒傾向（例如快樂、悲傷、平靜），'
          '除用於調整 AI 語音回覆的語氣外，也可能提供趨勢紀錄供家屬參考。',
    ),
    _DisclosureItem(
      icon: Icons.notifications_active_outlined,
      lead: '強制推播通知（家屬端）',
      body: '偵測到疑似跌倒或緊急狀況時，家屬端可能收到略過手機「勿擾模式」、'
          '並強制點亮螢幕的高優先級警示通知，確保您能即時知悉。',
    ),
    _DisclosureItem(
      icon: Icons.phonelink_lock_outlined,
      lead: '強制開啟畫面（長輩端）',
      body: '長輩端在接獲來電或緊急通知時，App 可能自動跳至前景、'
          '甚至覆蓋於鎖定畫面之上顯示來電或警示內容，不需先解鎖手機。',
    ),
    _DisclosureItem(
      icon: Icons.directions_walk_outlined,
      lead: '活動與照護紀錄',
      body: '每日步數、活動日誌與通話紀錄等資訊，會用於遊戲化功能'
          '（如排行榜、寵物造型）以及家屬端的照護狀態摘要。',
    ),
  ];

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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      size: 48,
                      color: _primaryGreen,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '隱私權政策',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '為了保障您與長輩的權益，在開始使用「Uban」之前，'
                      '請您先了解以下本服務會用到的資料與功能。同意後即可'
                      '繼續選擇您的身分。',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        height: 1.6,
                        color: _textBody,
                      ),
                    ),
                    const SizedBox(height: 24),
                    for (int i = 0; i < _items.length; i++)
                      _buildNumberedItem(i + 1, _items[i]),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '更完整的個人資料蒐集、使用與第三方共用細節，'
                        '請參閱家屬註冊流程中的《隱私權保護政策》與'
                        '《醫療免責聲明》。',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          height: 1.5,
                          color: _textBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberedItem(int number, _DisclosureItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _primaryGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2F7A63),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.icon, size: 18, color: _primaryGreen),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.lead,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.body,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    height: 1.55,
                    color: _textBody,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: _background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _accept,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryGreen,
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
                  '我已閱讀並同意',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DisclosureItem {
  final IconData icon;
  final String lead;
  final String body;

  const _DisclosureItem({
    required this.icon,
    required this.lead,
    required this.body,
  });
}
