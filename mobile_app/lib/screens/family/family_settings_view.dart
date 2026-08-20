import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/elder_manager.dart';
import '../../services/session_manager.dart';
import '../identification_screen.dart';
import '../caregiver_pairing_screen.dart';
import '../elder_profile_edit_screen.dart';
import '../device_selection_screen.dart';
import '../emergency_permission_guide_screen.dart';
import 'package:flutter_application_1/utils/app_logger.dart';

class FamilySettingsView extends StatefulWidget {
  final int userId;
  final String userName;

  const FamilySettingsView({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FamilySettingsView> createState() => _FamilySettingsViewState();
}

class _FamilySettingsViewState extends State<FamilySettingsView>
    with WidgetsBindingObserver {
  String _userName = '載入中...';  // 初始值改為載入中
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = false;
  List<dynamic> _pairedElders = [];
  bool _isLoadingElders = true;

  // ★ 2026-08-20 新增：緊急通知權限（勿擾模式例外／全螢幕緊急通知）。
  //   由原生端（MainActivity.kt）另一支子代理新增的 MethodChannel 提供查詢與開啟設定頁，
  //   本檔只負責呼叫與顯示。null＝尚未查詢完成或查詢失敗，一律視為「未知」，
  //   不可當成「已授權」處理（見 _refreshNotificationPolicyStatus）。
  static const MethodChannel _notificationPolicyChannel =
      MethodChannel('com.example.app/notification_policy');
  bool? _isDndAccessGranted;
  bool? _canUseFullScreenIntent;
  // ★ 2026-08-20 追加：Android SDK 版本（androidSdkInt），只用來判斷「全螢幕緊急
  //   通知」列在 API 34（Android 14）以下要不要顯示成「此系統版本不需要」。
  //   原生端失敗時回傳 0；null／0 都視為「未知版本」，見 _isKnownBelowAndroid14。
  int? _androidSdkInt;

  /// SDK 版本「已知且確定低於 34」時才算數；未知（null／0）一律回傳 false，
  /// 讓全螢幕列退回既有的已授權／未授權／檢查中判斷，不去猜測版本。
  bool get _isKnownBelowAndroid14 =>
      _androidSdkInt != null && _androidSdkInt! > 0 && _androidSdkInt! < 34;

  // ★ 2026-08-20 追加：MIUI 專有的「鎖屏顯示／後台彈出介面」設定引導入口。
  //   _isMiuiFamily 預設 false（查詢完成前／失敗時都不顯示這一列，比顯示一列
  //   查不到狀態的引導安全）。_isOemGuideAcknowledged 是使用者自己回報的狀態，
  //   不是 APP 驗證出來的，詳見 EmergencyPermissionGuideScreen.prefsAcknowledgedKey。
  bool _isMiuiFamily = false;
  bool _isOemGuideAcknowledged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
    _fetchPairedElders();
    _refreshNotificationPolicyStatus();
    _loadOemGuideAcknowledgedState();
  }

  @override
  void dispose() {
    // ★ 這個 State 因新增 WidgetsBindingObserver 而必須在 dispose 移除，
    //   否則 observer 會一直掛在 WidgetsBinding 上造成洩漏（本專案已有前例）。
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 使用者可能剛從系統設定頁（勿擾權限／全螢幕通知權限）切回本畫面，
    // 回到前景時重新查詢一次，讓權限狀態不需手動刷新就能自動更新。
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPolicyStatus();
    }
  }

  /// 查詢「勿擾模式例外」「全螢幕緊急通知」兩項系統層級權限，以及 Android SDK
  /// 版本的目前狀態。三個 MethodChannel 呼叫依規格保證不會拋例外，但仍加
  /// try/catch 保底——若原生端尚未實作該 method（例如負責 MainActivity.kt 的
  /// 子代理還沒完成），invokeMethod 會丟出 MissingPluginException，此時一律
  /// 視為「未知」，不可誤判為「已授權」或「版本很舊」。
  Future<void> _refreshNotificationPolicyStatus() async {
    bool? dndGranted;
    try {
      dndGranted = await _notificationPolicyChannel.invokeMethod<bool>(
        'isDndAccessGranted',
      );
    } catch (e) {
      appLogger.d('⚠️ 查詢勿擾權限狀態失敗，視為未知: $e');
      dndGranted = null;
    }

    bool? fullScreenGranted;
    try {
      fullScreenGranted = await _notificationPolicyChannel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );
    } catch (e) {
      appLogger.d('⚠️ 查詢全螢幕通知權限狀態失敗，視為未知: $e');
      fullScreenGranted = null;
    }

    int? sdkInt;
    try {
      sdkInt = await _notificationPolicyChannel.invokeMethod<int>(
        'androidSdkInt',
      );
    } catch (e) {
      appLogger.d('⚠️ 查詢 Android SDK 版本失敗，視為未知: $e');
      sdkInt = null;
    }

    // ★ 2026-08-20 新增：是否為 MIUI 家族裝置，決定下方「鎖屏顯示與背景彈出」
    //   引導列要不要顯示。查詢失敗一律視為「非 MIUI」（false）並隱藏該列，
    //   比顯示一列查不到狀態的引導安全——查不到就當作沒有，不去猜。
    bool isMiuiFamily = false;
    try {
      isMiuiFamily = await _notificationPolicyChannel.invokeMethod<bool>(
            'isMiuiFamily',
          ) ??
          false;
    } catch (e) {
      appLogger.d('⚠️ 查詢是否為 MIUI 裝置失敗，視為非 MIUI: $e');
      isMiuiFamily = false;
    }

    if (!mounted) return;
    setState(() {
      _isDndAccessGranted = dndGranted;
      _canUseFullScreenIntent = fullScreenGranted;
      _androidSdkInt = sdkInt;
      _isMiuiFamily = isMiuiFamily;
    });
  }

  /// 讀取使用者是否曾在「鎖屏與背景權限設定」引導頁按過「我已完成設定」。
  /// 純粹是使用者自行回報的狀態，不代表 APP 驗證過任何東西（見
  /// `EmergencyPermissionGuideScreen.prefsAcknowledgedKey` 的說明）。
  Future<void> _loadOemGuideAcknowledgedState() async {
    bool acknowledged = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      acknowledged = prefs.getBool(
            EmergencyPermissionGuideScreen.prefsAcknowledgedKey,
          ) ??
          false;
    } catch (e) {
      appLogger.d('⚠️ 讀取 MIUI 權限引導確認狀態失敗，視為未確認: $e');
      acknowledged = false;
    }
    if (!mounted) return;
    setState(() => _isOemGuideAcknowledged = acknowledged);
  }

  /// 打開／重新打開「鎖屏與背景權限設定」引導頁。回來後重新讀取確認狀態，
  /// 讓 chip 能反映使用者剛剛在該畫面按下的「我已完成設定」。
  Future<void> _openOemPermissionGuide() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmergencyPermissionGuideScreen(),
      ),
    );
    _loadOemGuideAcknowledgedState();
  }

  Future<void> _openDndSettings() async {
    bool opened = false;
    try {
      opened =
          await _notificationPolicyChannel.invokeMethod<bool>(
            'openDndAccessSettings',
          ) ??
          false;
    } catch (e) {
      appLogger.d('⚠️ 開啟勿擾權限設定頁失敗: $e');
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      _showCannotOpenSettingsMessage();
    }
  }

  Future<void> _openFullScreenIntentSettings() async {
    bool opened = false;
    try {
      opened =
          await _notificationPolicyChannel.invokeMethod<bool>(
            'openFullScreenIntentSettings',
          ) ??
          false;
    } catch (e) {
      appLogger.d('⚠️ 開啟全螢幕通知設定頁失敗: $e');
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      _showCannotOpenSettingsMessage();
    }
  }

  void _showCannotOpenSettingsMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '此裝置無法直接開啟該設定頁，請手動前往「系統設定 → 應用程式 → 特殊存取權」設定',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _loadUserInfo() async {
    // 從 SharedPreferences 讀取真實的登入用戶資訊
    final prefs = await SharedPreferences.getInstance();
    final savedUserId = prefs.getInt('caregiver_id');
    final savedUserName = prefs.getString('caregiver_name');
    
    appLogger.d('🔍 FamilySettingsView loading from SharedPreferences:');
    appLogger.d('   caregiver_id: $savedUserId');
    appLogger.d('   caregiver_name: $savedUserName');
    
    if (mounted && savedUserName != null) {
      setState(() {
        _userName = savedUserName;
      });
      appLogger.d('   ✅ Updated _userName to: $_userName');
    } else {
      // 備用方案：使用 widget 參數
      setState(() {
        _userName = widget.userName;
      });
      appLogger.d('   ⚠️  Using widget.userName: $_userName');
    }
  }

  Future<void> _fetchPairedElders() async {
    try {
      final elders = await ApiService.getPairedElders(widget.userId);
      if (mounted) {
        setState(() {
          _pairedElders = elders;
          _isLoadingElders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingElders = false);
      }
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出並回到身分選擇頁面嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await SessionManager.releaseSession();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: const Text('登出', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(int targetUserId) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在上傳大頭照...'), duration: Duration(seconds: 1)),
      );
      final result = await ApiService.uploadAvatar(targetUserId, image.path);

      if (!mounted) return;
      if (result.containsKey('avatar_url')) {
        setState(() {}); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('大頭照更新成功！'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失敗: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAvatar(int userId, String defaultName, double radius) {
    return GestureDetector(
      onTap: () => _pickAndUploadAvatar(userId),
      child: Stack(
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange[100],
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.network(
              '${ApiService.baseUrl}/user/$userId/avatar?v=${DateTime.now().millisecondsSinceEpoch}',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    defaultName.isNotEmpty ? defaultName[0] : 'U',
                    style: GoogleFonts.notoSansTc(
                      fontSize: radius * 0.7,
                      color: Colors.orange[800],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[200]!, width: 1),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 14,
                color: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleEditProfile() {
    final TextEditingController controller = TextEditingController(
      text: _userName,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯個人資料'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '顯示名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                // 保存到 SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('caregiver_name', newName);
                
                setState(() {
                  _userName = newName;
                });
                
                appLogger.d('✅ Profile updated: $_userName');
                appLogger.d('   Saved to SharedPreferences');
              }
              if (!mounted) return;
              navigator.pop();
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          _buildAvatar(widget.userId, _userName, 36),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: user_${widget.userId}',
                  style: GoogleFonts.inter(color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleEditProfile,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> items) {
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
          color: Colors.white,
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingItem(
    IconData icon,
    String title,
    String subtitle, {
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: GoogleFonts.notoSansTc()),
      subtitle: Text(subtitle, style: GoogleFonts.notoSansTc(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchItem(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: GoogleFonts.notoSansTc()),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFFFF9800).withValues(alpha: 0.5),
        activeThumbColor: const Color(0xFFFF9800),
      ),
    );
  }

  // ★ 2026-08-20 新增：「緊急通知權限」整個區塊。這兩項是 Android 的特殊存取權，
  //   無法用一般的權限請求對話框取得，使用者必須自己到系統設定頁開啟；
  //   平時完全沒有入口告訴使用者這兩項存在，家屬可能誤以為警報永遠會正常送達，
  //   實際上卻可能被靜音或不會亮屏。僅在 Android 顯示（DND／全螢幕通知都是
  //   Android 概念，iOS 沒有對應設定頁）。
  Widget _buildEmergencyPermissionsSection() {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return _buildSettingsGroup('緊急通知權限', [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text.rich(
          TextSpan(
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.5,
            ),
            children: [
              const TextSpan(text: '這些權限只用於'),
              TextSpan(
                text: '跌倒警報與緊急來電',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const TextSpan(
                text: '，讓警報在手機靜音或勿擾模式下仍能響起、並能在螢幕關閉時亮起畫面。'
                    '平時的一般通知不會使用這些權限。',
              ),
            ],
          ),
        ),
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      _buildEmergencyPermissionRow(
        icon: Icons.do_not_disturb_on_outlined,
        title: '勿擾模式例外',
        granted: _isDndAccessGranted,
        lostIfNotGrantedText: '未授權時，手機開啟勿擾模式時，跌倒警報可能不會發出聲音',
        onOpenSettings: _openDndSettings,
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      _buildEmergencyPermissionRow(
        icon: Icons.fullscreen_outlined,
        title: '全螢幕緊急通知',
        granted: _canUseFullScreenIntent,
        // Android 14 以下沒有這項限制，canUseFullScreenIntent 會恆為 true，
        // 但那不代表使用者「已授權」了什麼——只有在版本已知且確定 < 34 時，
        // 才把這列改成中性的「此系統版本不需要」，未知版本一律不猜。
        notApplicable: _isKnownBelowAndroid14,
        lostIfNotGrantedText: '未授權時，螢幕關閉時，跌倒警報只會顯示為一般通知，不會自動亮起畫面',
        onOpenSettings: _openFullScreenIntentSettings,
      ),
      _buildOemPermissionGuideRow(),
    ]);
  }

  /// 單一權限列：名稱／目前狀態／未授權時的具體影響／前往設定按鈕。
  /// 狀態顯示邏輯：
  /// - `notApplicable`＝true：中性灰「此系統版本不需要」，不顯示警語、不顯示按鈕
  ///   （目前只有全螢幕列在「SDK 版本已知且 < 34」時會是這個狀態）。
  /// - `granted == true`：綠「已授權」。
  /// - `granted == false`：amber「未授權」。
  /// - `granted == null`：灰「檢查中…」（尚未查完或查詢失敗，不可當已授權）。
  Widget _buildEmergencyPermissionRow({
    required IconData icon,
    required String title,
    required bool? granted,
    required String lostIfNotGrantedText,
    required VoidCallback onOpenSettings,
    bool notApplicable = false,
  }) {
    late final Color chipBg;
    late final Color chipFg;
    late final String stateLabel;
    if (notApplicable) {
      // 資訊性狀態，不是「達成了什麼」——這支手機的 Android 版本本來就沒有
      // 這項限制，使用者沒有任何事需要做，不可用綠色「已授權」樣式呈現，
      // 以免看起來像是使用者自己去授權過。
      chipBg = Colors.grey[200]!;
      chipFg = Colors.grey[700]!;
      stateLabel = '此系統版本不需要';
    } else if (granted == true) {
      chipBg = Colors.green[50]!;
      chipFg = Colors.green[700]!;
      stateLabel = '已授權';
    } else if (granted == false) {
      chipBg = Colors.amber[50]!;
      chipFg = Colors.amber[900]!;
      stateLabel = '未授權';
    } else {
      // null：尚未查詢完成，或查詢失敗（不可當成已授權）
      chipBg = Colors.grey[200]!;
      chipFg = Colors.grey[700]!;
      stateLabel = '檢查中…';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.black87, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stateLabel,
                  style: TextStyle(
                    color: chipFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // 已授權、或這支手機的版本本來就不需要這項權限時，都不顯示警語——
          // 兩種情況都沒有東西需要處理，顯示警語會自相矛盾。
          if (granted != true && !notApplicable) ...[
            const SizedBox(height: 6),
            Text(
              lostIfNotGrantedText,
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
          // notApplicable 時不出現「前往設定」——沒有東西需要使用者去授權，
          // 而且 openFullScreenIntentSettings 在 API 34 以下本來就恆回傳
          // false，留著按鈕只會讓使用者按了卻沒有反應。
          if (!notApplicable) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onOpenSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF9800),
                  side: const BorderSide(color: Color(0xFFFF9800)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  '前往設定',
                  style: GoogleFonts.notoSansTc(fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ★ 2026-08-20 新增：入口列，讓使用者能重新打開「鎖屏與背景權限設定」
  /// 引導頁（`EmergencyPermissionGuideScreen`）。這一列刻意跟上面兩列用不同
  /// 邏輯、不共用 `_buildEmergencyPermissionRow`：上面兩列的 granted 狀態來自
  /// Android 標準 API，可以分辨「已授權／未授權」；這一列對應的「鎖定螢幕
  /// 顯示」「後台彈出介面」是 MIUI 專有 AppOps，沒有標準 API 能讀取狀態，
  /// 因此**絕不能**顯示「已授權」——只能顯示使用者自己回報的「已確認過」，
  /// 或尚未回報的「需手動確認」。只在 MIUI 家族裝置上顯示；非 MIUI 裝置沒有
  /// 這兩項設定，顯示這一列只會造成困惑，故 `_isMiuiFamily` 為 false 時直接
  /// 回傳空 widget（不加多餘的 Divider）。
  Widget _buildOemPermissionGuideRow() {
    if (!_isMiuiFamily) return const SizedBox.shrink();

    final chipBg =
        _isOemGuideAcknowledged ? Colors.blueGrey[50]! : Colors.amber[50]!;
    final chipFg =
        _isOemGuideAcknowledged ? Colors.blueGrey[700]! : Colors.amber[900]!;
    final stateLabel = _isOemGuideAcknowledged ? '已確認過' : '需手動確認';

    return Column(
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.black87, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '鎖屏顯示與背景彈出設定',
                      style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      stateLabel,
                      style: TextStyle(
                        color: chipFg,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '小米（MIUI）系統的專有設定，APP 無法自動驗證，請依引導頁步驟手動確認',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _openOemPermissionGuide,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9800),
                    side: const BorderSide(color: Color(0xFFFF9800)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    '查看設定引導',
                    style: GoogleFonts.notoSansTc(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildElderTile(dynamic elder) {
    return ListTile(
      leading: _buildAvatar(elder['id'], elder['user_name'] ?? '長', 20),
      title: Text(elder['user_name'] ?? '未知長輩'),
      subtitle: Text(
        'ID: ${elder['id']} | 年齡: ${elder['age']} | 性別: ${elder['gender'] == 'M' ? '男' : '女'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '已連線',
              style: TextStyle(color: Colors.green[700], fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_note, color: Colors.blueAccent, size: 20),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ElderProfileEditScreen(
              elderData: elder,
              familyId: widget.userId,
              onUnbind: () {
                Navigator.pop(context); 
                _showUnbindConfirmDialog(elder);
              },
            ),
          ),
        ).then((_) {
          _fetchPairedElders(); 
        });
      },
    );
  }

  // ★ 新增：選擇要新增監控機的長輩，並開啟其設備管理頁
  void _showSelectElderForMonitor() {
    if (_pairedElders.isEmpty) return;
    if (_pairedElders.length == 1) {
      _openMonitorDeviceManager(_pairedElders.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('選擇要新增監控機的長輩',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._pairedElders.map((elder) => ListTile(
                  leading: const Icon(Icons.elderly),
                  title: Text(elder['user_name'] ?? '未知長輩'),
                  subtitle: Text('ID: ${elder['elder_id']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMonitorDeviceManager(elder);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _openMonitorDeviceManager(dynamic elder) {
    // ★ 注意：房間以 elder_id 為準（comm_elder_/monitor_elder_），不可用 user_id(elder['id'])
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          elderId: (elder['elder_id'] ?? elder['id']).toString(),
          elderName: elder['user_name'] ?? '長輩',
        ),
      ),
    );
  }

  void _showUnbindConfirmDialog(dynamic elder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '解除綁定',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '確定要解除與「${elder['user_name']}」的綁定嗎？\n\n警告：這將會永久刪除該長輩的所有資料與對話紀錄，無法復原。',
          style: GoogleFonts.notoSansTc(color: Colors.redAccent, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final result = await ApiService.unbindElder(
                widget.userId,
                elder['id'],
              );
              if (!mounted) return;
              if (result['status'] == 'success') {
                navigator.pop();
                await ElderManager().refresh();
                _fetchPairedElders();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('已刪除並解除綁定'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } else {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('刪除失敗: ${result['error']}'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: Text(
              '確定刪除',
              style: GoogleFonts.notoSansTc(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          '設定',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileSection(),
            const SizedBox(height: 12),
            _buildSettingsGroup('健康與安全', [
              _buildSwitchItem(
                Icons.emergency_rounded,
                '緊急廣播通知',
                _isEmergencyOn,
                (val) => setState(() => _isEmergencyOn = val),
              ),
              _buildSwitchItem(
                Icons.summarize_rounded,
                '每日健康摘要',
                _isDailySummaryOn,
                (val) => setState(() => _isDailySummaryOn = val),
              ),
              _buildSwitchItem(
                Icons.psychology_rounded,
                'AI 平安洞察',
                _isAiInsightOn,
                (val) => setState(() => _isAiInsightOn = val),
              ),
            ]),
            const SizedBox(height: 12),
            _buildEmergencyPermissionsSection(),
            const SizedBox(height: 12),
            _buildSettingsGroup('已配對長輩', [
              if (_isLoadingElders)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_pairedElders.isEmpty)
                ListTile(
                  title: const Text('尚未配對任何長輩'),
                  trailing: const Icon(Icons.add_link),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: _userName,
                        ),
                      ),
                    ).then((_) => _fetchPairedElders());
                  },
                )
              else
                ..._pairedElders.map((elder) => _buildElderTile(elder)),
              if (_pairedElders.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.videocam_outlined, color: Colors.deepPurple),
                  title: const Text('監控設備', style: TextStyle(color: Colors.deepPurple)),
                  subtitle: const Text('查看監控畫面／管理設備。新增監控機：用另一台裝置以同一位長輩登入即可自動成為監控機', style: TextStyle(fontSize: 12)),
                  onTap: _showSelectElderForMonitor,
                ),
              if (_pairedElders.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                  title: const Text('配對新設備', style: TextStyle(color: Colors.blueAccent)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: _userName,
                        ),
                      ),
                    ).then((_) => _fetchPairedElders());
                  },
                ),
            ]),
            const SizedBox(height: 12),
            _buildSettingsGroup('系統', [
              _buildSettingItem(
                Icons.help_outline_rounded,
                '幫助與支援',
                '常見問題、聯繫客服',
                onTap: () {},
              ),
              _buildSettingItem(
                Icons.info_outline_rounded,
                '關於 Uban',
                '版本 1.0.0 (Build 20240320)',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('登出帳號'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 120), 
          ],
        ),
      ),
    );
  }
}
