import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// 家屬端主題（2026-10 新設計：海灣藍 ocean，色票來自 [UbanColors.familyLight]／
/// [UbanColors.familyDark]，對應 design_prototype/family.css 的 ocean 區塊）。
///
/// 原則：不要科技感、少用小圖示、暖色只用於「待處理」、不帶色光暈陰影。
class FamilyTheme {
  FamilyTheme._();

  static const String _fontFamily = 'NotoSansTC';

  static ColorScheme _scheme(UbanColors c, Brightness b) => ColorScheme(
        brightness: b,
        primary: c.brandFill,
        onPrimary: c.onBrand,
        primaryContainer: c.brandContainer,
        onPrimaryContainer: c.brandStrong,
        secondary: c.brandStrong,
        onSecondary: c.onBrand,
        secondaryContainer: c.brandContainer,
        onSecondaryContainer: c.brandStrong,
        tertiary: c.warm,
        onTertiary: c.surface,
        tertiaryContainer: c.warmContainer,
        onTertiaryContainer: c.warm,
        error: c.danger,
        onError: b == Brightness.dark ? const Color(0xFF3A0A0C) : Colors.white,
        errorContainer: c.dangerContainer,
        onErrorContainer: c.danger,
        surface: c.surface,
        onSurface: c.text,
        surfaceContainerLowest: c.surface,
        surfaceContainerLow: c.surface,
        surfaceContainer: c.surface,
        surfaceContainerHigh: c.surface2,
        surfaceContainerHighest: c.surface3,
        onSurfaceVariant: c.text2,
        outline: c.text3,
        outlineVariant: c.line,
        shadow: Colors.black,
        scrim: c.scrim,
      );

  /// 舊 API：供截圖腳本等直接取用的 ColorScheme。
  static ColorScheme get lightColorScheme =>
      _scheme(UbanColors.familyLight, Brightness.light);
  static ColorScheme get darkColorScheme =>
      _scheme(UbanColors.familyDark, Brightness.dark);

  /// 卡片裝飾輔助：surface 底、圓角 24、中性雙層陰影、無描邊。
  ///
  /// [strokeColor] 有給才畫邊線（保留舊簽章；預設不畫）。
  static BoxDecoration cardDecoration(
    BuildContext context, {
    Color? color,
    BorderRadius? borderRadius,
    Color? strokeColor,
    double strokeWidth = 1.5,
    bool hasShadow = true,
  }) {
    final c = UbanColors.of(context);
    return BoxDecoration(
      color: color ?? c.surface,
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      border: strokeColor == null
          ? null
          : Border.all(color: strokeColor, width: strokeWidth),
      boxShadow: hasShadow ? c.shadows.card : null,
    );
  }

  /// 建立家屬端 Material 3 ThemeData。
  static ThemeData buildTheme(BuildContext context, {bool isDark = false}) {
    final c = isDark ? UbanColors.familyDark : UbanColors.familyLight;
    final cs = _scheme(c, isDark ? Brightness.dark : Brightness.light);
    final base = ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
    ).textTheme;
    final textTheme = base.apply(
      fontFamily: _fontFamily,
      bodyColor: c.text,
      displayColor: c.text,
    );
    const pill = StadiumBorder();
    const btnText = TextStyle(
        fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 16);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: cs.brightness,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      fontFamily: _fontFamily,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          color: c.text,
        ),
        iconTheme: IconThemeData(color: c.text),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface2,
        selectedColor: c.brandContainer,
        labelStyle: TextStyle(
          fontFamily: _fontFamily,
          color: c.text2,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: pill,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brandFill,
        foregroundColor: c.onBrand,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brandFill,
          foregroundColor: c.onBrand,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: pill,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: btnText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brandFill,
          foregroundColor: c.onBrand,
          shape: pill,
          minimumSize: const Size(0, 48),
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.brandStrong,
          side: BorderSide(color: c.line, width: 1.5),
          shape: pill,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brandStrong,
          shape: pill,
          textStyle: btnText.copyWith(fontSize: 15),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onBrand : c.surface),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brandFill : c.surface3),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.text,
        contentTextStyle:
            TextStyle(fontFamily: _fontFamily, color: c.surface, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brandFill,
        linearTrackColor: c.surface3,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    );
  }

  /// 供子元件便捷取得當前 M3 色系的角色
  static FamilyM3Tokens of(BuildContext context) {
    final theme = Theme.of(context);
    return FamilyM3Tokens(
        cs: theme.colorScheme, isDark: theme.brightness == Brightness.dark);
  }
}

/// 家屬端深淺色偏好。
///
/// 讀寫的是**既有**的 SharedPreferences 鍵 [prefsKey]（`family_theme_is_dark`），
/// 與舊版 `FamilyMainScreen` 相同，升級後使用者的偏好不會消失。
/// 主殼與每個 [FamilyThemeScope] 都監聽同一個實例，資料分頁的開關即時套用到所有家屬頁。
class FamilyThemeController extends ValueNotifier<bool> {
  FamilyThemeController([super.value = false]);

  static const String prefsKey = 'family_theme_is_dark';

  /// App 內共用實例。
  static final FamilyThemeController instance = FamilyThemeController();

  Future<void>? _loading;

  bool get isDark => value;

  /// 從 SharedPreferences 讀取偏好（只讀一次；再呼叫回傳同一個 Future）。
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(prefsKey) ?? false;
    } catch (e) {
      debugPrint('⚠️ [FamilyThemeController] 讀取深色偏好失敗: $e');
    }
  }

  /// 切換並持久化。
  Future<void> setDark(bool isDark) async {
    value = isDark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, isDark);
    } catch (e) {
      debugPrint('⚠️ [FamilyThemeController] 寫入深色偏好失敗: $e');
    }
  }
}

/// 以家屬端偏好包住 [child]：`Theme(data: FamilyTheme.buildTheme(...))`。
///
/// push 出去的家屬頁不在主殼的 Theme 之下，需在 build 最外層包一層。
/// [controller] 預設為 [FamilyThemeController.instance]（測試可注入）。
class FamilyThemeScope extends StatefulWidget {
  final Widget child;
  final FamilyThemeController? controller;

  const FamilyThemeScope({super.key, required this.child, this.controller});

  @override
  State<FamilyThemeScope> createState() => _FamilyThemeScopeState();
}

class _FamilyThemeScopeState extends State<FamilyThemeScope> {
  FamilyThemeController get _ctrl =>
      widget.controller ?? FamilyThemeController.instance;

  @override
  void initState() {
    super.initState();
    // 冷啟動直達子頁（例如點通知）時主殼可能還沒載入偏好。
    if (widget.controller == null) _ctrl.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _ctrl,
      builder: (context, isDark, _) => Theme(
        data: FamilyTheme.buildTheme(context, isDark: isDark),
        child: widget.child,
      ),
    );
  }
}

/// 封裝 M3 常用語意化視覺 Token
class FamilyM3Tokens {
  final ColorScheme cs;
  final bool isDark;

  const FamilyM3Tokens({required this.cs, required this.isDark});

  Color get primary => cs.primary;
  Color get onPrimary => cs.onPrimary;
  Color get primaryContainer => cs.primaryContainer;
  Color get onPrimaryContainer => cs.onPrimaryContainer;

  Color get secondary => cs.secondary;
  Color get onSecondary => cs.onSecondary;
  Color get secondaryContainer => cs.secondaryContainer;
  Color get onSecondaryContainer => cs.onSecondaryContainer;

  Color get tertiary => cs.tertiary;
  Color get onTertiary => cs.onTertiary;
  Color get tertiaryContainer => cs.tertiaryContainer;
  Color get onTertiaryContainer => cs.onTertiaryContainer;

  Color get surface => cs.surface;
  Color get onSurface => cs.onSurface;
  Color get onSurfaceVariant => cs.onSurfaceVariant;

  Color get surfaceContainer => cs.surfaceContainer;
  Color get surfaceContainerLow => cs.surfaceContainerLow;
  Color get surfaceContainerHigh => cs.surfaceContainerHigh;
  Color get surfaceContainerHighest => cs.surfaceContainerHighest;

  Color get outline => cs.outline;
  Color get outlineVariant => cs.outlineVariant;

  Color get error => cs.error;
  Color get onError => cs.onError;
  Color get errorContainer => cs.errorContainer;
  Color get onErrorContainer => cs.onErrorContainer;

  Color get cardBackground => cs.surfaceContainer;
  Color get dialogBackground => cs.surfaceContainerHigh;
  Color get subtleBorder => cs.outlineVariant;
  Color get focusBorder => cs.primary.withValues(alpha: isDark ? 0.6 : 0.4);
  Color get textPrimary => cs.onSurface;
  Color get textSecondary => cs.onSurfaceVariant;
  Color get textHint => cs.outline;
}
