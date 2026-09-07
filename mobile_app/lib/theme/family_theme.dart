import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 子女端 (Family / Caregiver) Material Design 3 (M3) 薄荷綠動態色彩系統
///
/// 依據 M3 Dynamic Color Roles 規範設計：
/// - 以清爽柔和的薄荷綠 (Mint Green, #006C4C / #A8E6CF) 為核心
/// - 強調低飽和度的輔助色 (Secondary #4D6355 / #B4CCB9) 與暖藍灰 (Tertiary #3C6472 / #A4CDDC)
/// - 提供完整且清晰對比的淺色模式 (Light) 與深色模式 (Dark)
class FamilyTheme {
  FamilyTheme._();

  // ─── 淺色模式 (Light Theme) ────────────────────────────────
  static const Color lightPrimary = Color(0xFF006C4C);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFF90F7BE);
  static const Color lightOnPrimaryContainer = Color(0xFF002114);

  static const Color lightSecondary = Color(0xFF4D6355);
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightSecondaryContainer = Color(0xFFCFE8D7);
  static const Color lightOnSecondaryContainer = Color(0xFF0B1F15);

  static const Color lightTertiary = Color(0xFF3C6472);
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  static const Color lightTertiaryContainer = Color(0xFFBFE9F9);
  static const Color lightOnTertiaryContainer = Color(0xFF001F27);

  static const Color lightSurface = Color(0xFFF6FBF4);
  static const Color lightSurfaceContainerLow = Color(0xFFF0F5EE);
  static const Color lightSurfaceContainer = Color(0xFFEAEFE8);
  static const Color lightSurfaceContainerHigh = Color(0xFFE4EAE2);
  static const Color lightSurfaceContainerHighest = Color(0xFFDEE4DC);

  static const Color lightOnSurface = Color(0xFF171D19);
  static const Color lightOnSurfaceVariant = Color(0xFF404943);

  static const Color lightOutline = Color(0xFF707973);
  static const Color lightOutlineVariant = Color(0xFFC0C9C1);

  // ─── 深色模式 (Dark Theme) ─────────────────────────────────
  static const Color darkPrimary = Color(0xFF74DAA2);
  static const Color darkOnPrimary = Color(0xFF003824);
  static const Color darkPrimaryContainer = Color(0xFF005238);
  static const Color darkOnPrimaryContainer = Color(0xFF90F7BE);

  static const Color darkSecondary = Color(0xFFB4CCB9);
  static const Color darkOnSecondary = Color(0xFF203529);
  static const Color darkSecondaryContainer = Color(0xFF364B3E);
  static const Color darkOnSecondaryContainer = Color(0xFFD0E8D7);

  static const Color darkTertiary = Color(0xFFA4CDDC);
  static const Color darkOnTertiary = Color(0xFF053542);
  static const Color darkTertiaryContainer = Color(0xFF234C5A);
  static const Color darkOnTertiaryContainer = Color(0xFFBFE9F9);

  static const Color darkSurface = Color(0xFF0F1511);
  static const Color darkSurfaceContainerLow = Color(0xFF131B15);
  static const Color darkSurfaceContainer = Color(0xFF1B211D);
  static const Color darkSurfaceContainerHigh = Color(0xFF252C27);
  static const Color darkSurfaceContainerHighest = Color(0xFF303732);

  static const Color darkOnSurface = Color(0xFFE0E4DE);
  static const Color darkOnSurfaceVariant = Color(0xFFC0C9C1);

  static const Color darkOutline = Color(0xFF8A938C);
  static const Color darkOutlineVariant = Color(0xFF404943);

  // ─── ColorScheme 定義 ──────────────────────────────────────
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: lightOnPrimary,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: lightOnSecondary,
    secondaryContainer: lightSecondaryContainer,
    onSecondaryContainer: lightOnSecondaryContainer,
    tertiary: lightTertiary,
    onTertiary: lightOnTertiary,
    tertiaryContainer: lightTertiaryContainer,
    onTertiaryContainer: lightOnTertiaryContainer,
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: lightSurface,
    onSurface: lightOnSurface,
    surfaceContainerLow: lightSurfaceContainerLow,
    surfaceContainer: lightSurfaceContainer,
    surfaceContainerHigh: lightSurfaceContainerHigh,
    surfaceContainerHighest: lightSurfaceContainerHighest,
    onSurfaceVariant: lightOnSurfaceVariant,
    outline: lightOutline,
    outlineVariant: lightOutlineVariant,
  );

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
    primaryContainer: darkPrimaryContainer,
    onPrimaryContainer: darkOnPrimaryContainer,
    secondary: darkSecondary,
    onSecondary: darkOnSecondary,
    secondaryContainer: darkSecondaryContainer,
    onSecondaryContainer: darkOnSecondaryContainer,
    tertiary: darkTertiary,
    onTertiary: darkOnTertiary,
    tertiaryContainer: darkTertiaryContainer,
    onTertiaryContainer: darkOnTertiaryContainer,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: darkSurface,
    onSurface: darkOnSurface,
    surfaceContainerLow: darkSurfaceContainerLow,
    surfaceContainer: darkSurfaceContainer,
    surfaceContainerHigh: darkSurfaceContainerHigh,
    surfaceContainerHighest: darkSurfaceContainerHighest,
    onSurfaceVariant: darkOnSurfaceVariant,
    outline: darkOutline,
    outlineVariant: darkOutlineVariant,
  );

  /// 建立子女端 Material 3 ThemeData
  static ThemeData buildTheme(BuildContext context, {bool isDark = false}) {
    final colorScheme = isDark ? darkColorScheme : lightColorScheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: GoogleFonts.notoSansTcTextTheme(
        Theme.of(context).textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedColor: colorScheme.secondaryContainer,
        secondarySelectedColor: colorScheme.primaryContainer,
        labelStyle: GoogleFonts.notoSansTc(
          color: colorScheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: GoogleFonts.notoSansTc(
          color: colorScheme.onPrimaryContainer,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  /// 供子元件便捷取得當前 M3 色系的角色
  static FamilyM3Tokens of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return FamilyM3Tokens(cs: cs, isDark: isDark);
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

  /// 卡片底色 (M3 Surface Container)
  Color get cardBackground => cs.surfaceContainer;

  /// 浮動選單 / 彈窗底色
  Color get dialogBackground => cs.surfaceContainerHigh;

  /// 柔和邊線 (M3 Outline Variant)
  Color get subtleBorder => cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6);

  /// 警示強調邊框
  Color get focusBorder => cs.primary.withValues(alpha: isDark ? 0.6 : 0.4);

  /// 文字主色
  Color get textPrimary => cs.onSurface;

  /// 文字次色
  Color get textSecondary => cs.onSurfaceVariant;

  /// 微弱提示文字
  Color get textHint => cs.outline;
}
