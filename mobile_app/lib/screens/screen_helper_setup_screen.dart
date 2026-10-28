import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/api_client.dart';
import '../widgets/ui/ui.dart';

/// 手機小幫手設定頁：說明功能、引導長輩到系統「無障礙」開啟服務。
///
/// 原生端（`android/.../screenhelper/ScreenHelperService.kt`）從
/// SharedPreferences 讀 `screen_helper_base_url`（伺服器根網址，不含 /api）
/// 與既有的 `access_token`，所以進入本頁時會把前者寫入。僅支援 Android。
class ScreenHelperSetupScreen extends StatefulWidget {
  const ScreenHelperSetupScreen({super.key});

  @override
  State<ScreenHelperSetupScreen> createState() =>
      _ScreenHelperSetupScreenState();
}

class _ScreenHelperSetupScreenState extends State<ScreenHelperSetupScreen> {
  static const String _packageName = 'com.example.flutter_application_1';

  bool _hasToken = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('screen_helper_base_url', ApiClient.serverRootUrl);
      final token = prefs.getString('access_token');
      if (mounted) setState(() => _hasToken = token != null && token.isNotEmpty);
    } catch (e) {
      debugPrint('[ScreenHelperSetup] 寫入設定失敗: $e');
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await const AndroidIntent(
        action: 'android.settings.ACCESSIBILITY_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (e) {
      debugPrint('[ScreenHelperSetup] 開啟無障礙設定失敗: $e');
    }
  }

  Future<void> _openAppInfo() async {
    try {
      await const AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$_packageName',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (e) {
      debugPrint('[ScreenHelperSetup] 開啟 App 資訊失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.text,
        title: Text('手機小幫手',
            style: ubanText(26, FontWeight.w900, c.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _card(
              c,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('這是什麼？', style: ubanText(24, FontWeight.w900, c.text)),
                  const SizedBox(height: 10),
                  Text(
                    '不會用手機時，按一下螢幕旁的小嘎按鈕，說出您想做的事，小嘎會看著畫面，一步一步帶您做。',
                    style: ubanText(20, FontWeight.w500, c.text),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '・想讓小嘎替您按，就按「幫我按」（付款、密碼等重要畫面不會幫您按）。',
                    style: ubanText(20, FontWeight.w500, c.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '・還是不會時，按「問家人」，會先讓您看畫面，再決定要不要一起傳給家人（付款、密碼等重要畫面不會傳）。',
                    style: ubanText(20, FontWeight.w500, c.text),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 26, color: c.brandStrong),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '平常只有您按下按鈕，或小嘎正在帶您做步驟時，才會看畫面，看完就丟掉。',
                          style: ubanText(20, FontWeight.w700, c.brandStrong),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!_isAndroid)
              _card(
                c,
                child: Text('這個功能目前只支援 Android 手機。',
                    style: ubanText(20, FontWeight.w700, c.text)),
              )
            else ...[
              if (!_hasToken) ...[
                _card(
                  c,
                  color: c.warmContainer,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 26, color: c.warm),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '目前沒有登入資料，小幫手可能無法使用，請家人協助重新登入',
                          style: ubanText(20, FontWeight.w700, c.warm),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _card(
                c,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('開啟步驟',
                        style: ubanText(24, FontWeight.w900, c.text)),
                    const SizedBox(height: 14),
                    _step(c, '1', '按下面的「前往開啟」'),
                    const SizedBox(height: 14),
                    _step(c, '2', '找到「已下載的應用程式」裡的「Uban 手機小幫手」'),
                    const SizedBox(height: 14),
                    _step(c, '3', '打開開關，並按「允許」'),
                    const SizedBox(height: 14),
                    _step(c, '4',
                        '（可選）長按桌面空白處 →「小工具」→ 找到「Uban 手機小幫手」拖到桌面；或從螢幕頂端往下滑兩次 →「編輯」→ 把「手機小幫手」拖進快速設定。之後一按就能顯示或隱藏按鈕'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton.icon(
                  onPressed: _openAccessibilitySettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brandFill,
                    foregroundColor: c.onBrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                  ),
                  icon: const Icon(Icons.settings_accessibility_rounded,
                      size: 28),
                  label: Text('前往開啟',
                      style: ubanText(24, FontWeight.w900, c.onBrand)),
                ),
              ),
              const SizedBox(height: 16),
              _card(
                c,
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    iconColor: c.text2,
                    collapsedIconColor: c.text2,
                    title: Text('開關是灰色的，打不開？',
                        style: ubanText(22, FontWeight.w900, c.text)),
                    children: [
                      Text(
                        '這是手機的安全保護（受限設定），請照著做：',
                        style: ubanText(20, FontWeight.w500, c.text),
                      ),
                      const SizedBox(height: 12),
                      _step(c, '1', '先按一次灰色的開關'),
                      const SizedBox(height: 10),
                      _step(c, '2', '回到這裡，按下面的「打開 App 資訊」'),
                      const SizedBox(height: 10),
                      _step(c, '3', '按右上角的「⋮」，選「允許受限設定」'),
                      const SizedBox(height: 10),
                      _step(c, '4', '再回去打開開關'),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _openAppInfo,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.brandStrong,
                            side: BorderSide(color: c.brandStrong, width: 2),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          icon: const Icon(Icons.info_outline_rounded,
                              size: 26),
                          label: Text('打開 App 資訊',
                              style: ubanText(
                                  22, FontWeight.w900, c.brandStrong)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(
    UbanColors c, {
    required Widget child,
    Color? color,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: c.shadows.card,
      ),
      child: Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  Widget _step(UbanColors c, String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.brandFill, shape: BoxShape.circle),
          child: Text(number, style: ubanText(22, FontWeight.w900, c.onBrand)),
        ),
        const SizedBox(width: 12),
        // 步驟文字可收縮換行，避免窄螢幕溢位。
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: ubanText(20, FontWeight.w700, c.text)),
          ),
        ),
      ],
    );
  }
}
