import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 長輩端外觀偏好：跟隨系統／淺色／深色（預設跟隨系統），存在本機。
///
/// 只餵給 `MaterialApp.themeMode`；家屬端頁面由 `FamilyThemeScope` 以自己的
/// `Theme` 覆蓋，不受此值影響。
class ElderThemeModeController extends ValueNotifier<ThemeMode> {
  ElderThemeModeController([super.value = ThemeMode.system]);

  static const String prefsKey = 'elder_theme_mode';

  /// App 內共用實例。
  static final ElderThemeModeController instance = ElderThemeModeController();

  Future<void>? _loading;

  /// 從 SharedPreferences 讀取偏好（只讀一次；再呼叫回傳同一個 Future）。
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = decode(prefs.getString(prefsKey));
    } catch (e) {
      debugPrint('⚠️ [ElderThemeModeController] 讀取外觀偏好失敗: $e');
    }
  }

  /// 切換並持久化。
  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, encode(mode));
    } catch (e) {
      debugPrint('⚠️ [ElderThemeModeController] 寫入外觀偏好失敗: $e');
    }
  }

  /// 'system'|'light'|'dark'；缺值或不合法一律視為跟隨系統。
  static ThemeMode decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
