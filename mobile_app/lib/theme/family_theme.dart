import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 子女端 (Family / Caregiver) 清新線條插畫風 (Clean Line & Flat Palette) 色彩系統
///
/// 依據 Realtime Colors 設計語言：
/// - Background: #FFFFFE (純淨純白底色)
/// - Headline & Stroke: #00214D (深海墨藍，作為大標題與 1.5px 俐落實線外框)
/// - Paragraph: #1B2D45 (沉穩板岩灰藍內文)
/// - Button / Highlight: #00EBC7 (活力薄荷青高亮與操作按鈕)
/// - Button Text: #00214D (深墨藍高對比文字)
/// - Secondary: #FF5470 (珊瑚紅，警報、心跳與緊急聯絡)
/// - Tertiary: #FDE24F (陽光金黃，今日關懷話題與溫馨標籤)
class FamilyTheme {
  FamilyTheme._();

  // ─── 淺色模式 (Light Theme) ────────────────────────────────
  static const Color lightBackground = Color(0xFFFFFFFE);
  static const Color lightHeadline = Color(0xFF00214D);
  static const Color lightParagraph = Color(0xFF1B2D45);
  static const Color lightHighlight = Color(0xFF00EBC7);
  static const Color lightStroke = Color(0xFF00214D);
  static const Color lightSecondary = Color(0xFFFF5470);
  static const Color lightTertiary = Color(0xFFFDE24F);

  // M3 映射 (Light)
  static const Color lightPrimary = lightHighlight;
  static const Color lightOnPrimary = lightHeadline;
  static const Color lightPrimaryContainer = lightHighlight;
  static const Color lightOnPrimaryContainer = lightHeadline;

  static const Color lightSurface = lightBackground;
  static const Color lightSurfaceContainerLow = lightBackground;
  static const Color lightSurfaceContainer = lightBackground;
  static const Color lightSurfaceContainerHigh = Color(0xFFF4F7F6);
  static const Color lightSurfaceContainerHighest = Color(0xFFE5ECE9);

  static const Color lightOnSurface = lightHeadline;
  static const Color lightOnSurfaceVariant = lightParagraph;

  static const Color lightOutline = lightStroke;
  static const Color lightOutlineVariant = Color(0xFFCBD5E1);

  // ─── 深色模式 (Dark Theme) ─────────────────────────────────
  static const Color darkBackground = Color(0xFF0B1320);
  static const Color darkHeadline = Color(0xFFFFFFFE);
  static const Color darkParagraph = Color(0xFFCBD5E1);
  static const Color darkHighlight = Color(0xFF00EBC7);
  static const Color darkStroke = Color(0xFF334155);
  static const Color darkSecondary = Color(0xFFFF5470);
  static const Color darkTertiary = Color(0xFFFDE24F);

  // M3 映射 (Dark)
  static const Color darkPrimary = darkHighlight;
  static const Color darkOnPrimary = Color(0xFF00214D);
  static const Color darkPrimaryContainer = Color(0xFF004D40);
  static const Color darkOnPrimaryContainer = Color(0xFF80F7E3);

  static const Color darkSurface = darkBackground;
  static const Color darkSurfaceContainerLow = Color(0xFF0F1B2D);
  static const Color darkSurfaceContainer = Color(0xFF142238);
  static const Color darkSurfaceContainerHigh = Color(0xFF1C2D47);
  static const Color darkSurfaceContainerHighest = Color(0xFF263957);

  static const Color darkOnSurface = darkHeadline;
  static const Color darkOnSurfaceVariant = darkParagraph;

  static const Color darkOutline = Color(0xFF475569);
  static const Color darkOutlineVariant = Color(0xFF1E293B);

  // ─── ColorScheme 定義 ──────────────────────────────────────
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: lightOnPrimary,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFE8EC),
    onSecondaryContainer: Color(0xFF5A0019),
    tertiary: lightTertiary,
    onTertiary: lightHeadline,
    tertiaryContainer: Color(0xFFFFF7C2),
    onTertiaryContainer: Color(0xFF423700),
    error: lightSecondary,
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
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF5A0019),
    onSecondaryContainer: Color(0xFFFFD9E0),
    tertiary: darkTertiary,
    onTertiary: Color(0xFF00214D),
    tertiaryContainer: Color(0xFF423700),
    onTertiaryContainer: Color(0xFFFFF085),
    error: darkSecondary,
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

  /// 實線卡片裝飾輔助方法 (提供標準 1.5px 墨藍邊框與純色微陰影)
  static BoxDecoration cardDecoration(
    BuildContext context, {
    Color? color,
    BorderRadius? borderRadius,
    Color? strokeColor,
    double strokeWidth = 1.5,
    bool hasShadow = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? cs.surfaceContainer,
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      border: Border.all(
        color: strokeColor ?? (isDark ? cs.outline : cs.outline),
        width: strokeWidth,
      ),
      boxShadow: hasShadow
          ? [
              BoxShadow(
                color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }

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
        titleTextStyle: GoogleFonts.notoSansTc(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outline,
            width: 1.5,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: GoogleFonts.notoSansTc(
          color: colorScheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: colorScheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outline, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.notoSansTc(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.notoSansTc(fontWeight: FontWeight.w800, fontSize: 15),
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
        trackOutlineColor: WidgetStateProperty.all(colorScheme.outline),
        trackOutlineWidth: WidgetStateProperty.all(1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.2),
        thickness: 1,
        space: 1,
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
