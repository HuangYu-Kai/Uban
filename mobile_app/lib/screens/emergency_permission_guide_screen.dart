import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/utils/app_logger.dart';

/// ★ 2026-08-20 新增：MIUI 專有的「鎖定螢幕顯示」「後台彈出介面」權限引導頁。
///
/// 背景：這兩項是小米（MIUI／HyperOS）家族 ROM 專有的 AppOps，Android 標準
/// API 完全沒有公開的方式可以讀取目前狀態，因此本畫面**絕對不會**顯示「已
/// 授權」這種需要驗證才能講的字眼——只有使用者自己按下「我已完成設定」時，
/// 才會記錄一個「已確認過」（帶有「這是使用者自己講的，不是 APP 驗證出來
/// 的」語意），詳見 [_buildStatusBanner]。這個原則是本專案在多輪修復後刻意
/// 維持的：先前已經移除過好幾處「顯示了驗證不了的『已授權』」的 UI，不要在
/// 這裡重蹈覆轍。
///
/// 角色無關：長輩端與家屬端都可能需要這兩項權限（長輩端要能在鎖定畫面顯示
/// 來電，家屬端要能在背景彈出跌倒警報），因此本畫面的文案兩者都提到，不分
/// 角色顯示不同內容。
///
/// 進入點：
/// - 自動：`elder_home_screen.dart` 在長輩端第一次進入首頁、且偵測到是 MIUI
///   家族裝置時，會自動 push 一次（見該檔 `_maybeShowMiuiPermissionGuide`）。
/// - 手動：`family_settings_view.dart`「緊急通知權限」區塊新增的入口列，讓
///   按過「稍後再說」的使用者可以再次回來查看。
class EmergencyPermissionGuideScreen extends StatefulWidget {
  const EmergencyPermissionGuideScreen({super.key});

  /// 使用者是否已經「看過」這個畫面（不論最後按哪個按鈕）。
  /// 由本畫面 initState 寫入，`elder_home_screen.dart` 的自動彈出邏輯讀取，
  /// 用來確保「只在第一次自動彈出一次」——手動從設定頁再次打開不受這個鍵
  /// 影響（那條路徑本來就不會再檢查它）。
  static const String prefsSeenKey = 'miui_permission_guide_seen';

  /// 使用者是否按過「我已完成設定」。只有這個按鈕會寫 true；「稍後再說」與
  /// 直接返回都不會動到這個鍵。由 `family_settings_view.dart` 讀取，用來決定
  /// 顯示「已確認過」還是「需手動確認」——**絕不**代表 APP 驗證過使用者真的
  /// 開啟了那兩項設定，純粹是使用者自己回報的狀態。
  static const String prefsAcknowledgedKey = 'miui_permission_guide_acknowledged';

  @override
  State<EmergencyPermissionGuideScreen> createState() =>
      _EmergencyPermissionGuideScreenState();
}

class _EmergencyPermissionGuideScreenState
    extends State<EmergencyPermissionGuideScreen> {
  static const MethodChannel _notificationPolicyChannel =
      MethodChannel('com.example.app/notification_policy');

  bool _isAcknowledged = false;
  bool _isOpeningSettings = false;

  @override
  void initState() {
    super.initState();
    _markSeen();
    _loadAcknowledgedState();
  }

  /// 記錄「使用者看過這個畫面」。刻意 fire-and-forget（不 await、不擋畫面
  /// 顯示）——這只是給 `elder_home_screen.dart` 自動彈出邏輯看的旗標，寫入
  /// 失敗也不影響本畫面正常使用，因此只需要 try/catch 吞掉例外。
  Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(EmergencyPermissionGuideScreen.prefsSeenKey, true);
    } catch (e) {
      appLogger.d('⚠️ 記錄「已看過 MIUI 權限引導」失敗（不影響本畫面使用）: $e');
    }
  }

  Future<void> _loadAcknowledgedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final acknowledged = prefs.getBool(
            EmergencyPermissionGuideScreen.prefsAcknowledgedKey,
          ) ??
          false;
      if (!mounted) return;
      setState(() => _isAcknowledged = acknowledged);
    } catch (e) {
      appLogger.d('⚠️ 讀取「已確認過」狀態失敗，視為未確認: $e');
    }
  }

  /// 呼叫原生端 `openOemPermissionEditor`。回傳 true 只代表「成功開啟了某個
  /// 設定頁」，不代表使用者真的完成設定——所以這裡不論成功與否都不會去動
  /// `_isAcknowledged`，那個狀態只能由使用者親自按「我已完成設定」設定。
  Future<void> _openSettings() async {
    if (_isOpeningSettings) return;
    setState(() => _isOpeningSettings = true);
    bool opened = false;
    try {
      opened = await _notificationPolicyChannel.invokeMethod<bool>(
            'openOemPermissionEditor',
          ) ??
          false;
    } catch (e) {
      appLogger.d('⚠️ 開啟 MIUI 權限編輯頁失敗: $e');
      opened = false;
    }
    if (!mounted) return;
    setState(() => _isOpeningSettings = false);
    if (!opened) {
      // 沒能自動跳轉不算失敗——步驟已經永遠顯示在畫面上（見 _buildStepsCard），
      // 這裡只是額外提醒使用者改用手動路徑，而不是靜默沒有任何反應。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('無法直接開啟設定頁，請依下方步驟手動前往設定'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _acknowledge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        EmergencyPermissionGuideScreen.prefsAcknowledgedKey,
        true,
      );
    } catch (e) {
      appLogger.d('⚠️ 記錄「已確認過」失敗: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _dismissLater() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          '鎖屏與背景權限設定',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildIntroCard(),
              const SizedBox(height: 12),
              _buildStepsCard(),
              const SizedBox(height: 12),
              _buildStatusBanner(),
              const SizedBox(height: 24),
              _buildActionButtons(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// 卡片外層樣式比照 `family_settings_view.dart` 的 `_buildSettingsGroup`
  /// （灰色小標題 + 白底容器），維持同一套視覺語言，不另外發明新樣式。
  Widget _buildGroup(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            title,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }

  Widget _buildIntroCard() {
    return _buildGroup(
      '為什麼需要這兩項設定',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: Colors.grey[800],
                height: 1.6,
              ),
              children: [
                const TextSpan(text: '這兩項設定只用於緊急情況：'),
                TextSpan(
                  text: '長輩端的來電畫面顯示、家屬端的跌倒警報彈出',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: Colors.grey[900],
                    fontWeight: FontWeight.bold,
                    height: 1.6,
                  ),
                ),
                const TextSpan(
                  text: '。開啟後，即使手機處於鎖定畫面，或 Uban 正在背景執行，'
                      '緊急來電與警報仍能正常顯示；平時的一般使用不會用到這兩項'
                      '權限。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '「鎖定螢幕顯示」與「後台彈出介面」是小米（MIUI）系統專有的設定，'
            'Android 本身沒有提供讓 APP 讀取目前狀態的方式，因此需要您手動確認'
            '已經開啟——這是誠實的作法，不是 APP 偷懶。',
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepsCard() {
    return _buildGroup(
      '設定步驟',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPermissionExplainRow(
            icon: Icons.lock_outline,
            title: '鎖定螢幕顯示',
            description: '讓長輩端手機處於鎖定畫面時，家人的來電畫面仍能顯示出來',
          ),
          const SizedBox(height: 12),
          _buildPermissionExplainRow(
            icon: Icons.layers_outlined,
            title: '後台彈出介面',
            description: '讓家屬端在背景使用其他 APP 時，長輩的跌倒警報仍能立即彈出',
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '設定 → 應用程式 → Uban → 其他權限 → 開啟「鎖定螢幕顯示」與「後台'
              '彈出介面」',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: const Color(0xFF8A5A00),
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '按下方「前往設定」按鈕，部分機型會直接進入上述頁面；若您的機型沒有'
            '直接跳轉，請依這個路徑自行前往。',
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionExplainRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFF9800), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 狀態橫幅——這是本畫面「誠實限制」的具體呈現：只有「需手動確認」（amber，
  /// 尚未回報）與「已確認過」（藍灰色，使用者自行回報）兩種狀態，**沒有**
  /// 任何一種會顯示綠色或「已授權」字樣，避免讓使用者誤以為 APP 驗證過。
  Widget _buildStatusBanner() {
    final chipBg = _isAcknowledged ? Colors.blueGrey[50]! : Colors.amber[50]!;
    final chipFg =
        _isAcknowledged ? Colors.blueGrey[700]! : Colors.amber[900]!;
    final label = _isAcknowledged ? '已確認過' : '需手動確認';
    final explain = _isAcknowledged
        ? '這是您先前自行確認的結果，並非 APP 驗證過的授權狀態。若手機重新開機'
            '或更新過系統，建議重新檢查一次。'
        : 'APP 無法讀取這兩項 MIUI 專有設定的實際開關狀態，因此無法顯示「已'
            '授權」，請依上方步驟確認後按下方「我已完成設定」。';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipFg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: chipFg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              explain,
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                color: chipFg,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isOpeningSettings ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(
                '前往設定',
                style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _dismissLater,
                  child: Text(
                    '稍後再說',
                    style: GoogleFonts.notoSansTc(color: Colors.grey[700]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _acknowledge,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9800),
                    side: const BorderSide(color: Color(0xFFFF9800)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '我已完成設定',
                    style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
