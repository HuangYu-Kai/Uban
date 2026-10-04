import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Uban 全 App 統一設計系統 (Design Tokens)
///
/// 目標：整體風格統一 —— 長輩端與家屬端共用同一組配色 / 間距 / 圓角 / 字體。
/// 主色統一為 teal 綠 `0xFF59B294`（原家屬端 blue 0xFF2563EB 已併入此系統）。
///
/// 使用方式：畫面內以 `AppColors.primary`、`AppSpacing.md`、`AppRadius.card` 等
/// 取代硬編碼字面值，避免各畫面顏色 / 間距不一致。
class AppColors {
  AppColors._();

  // --- 主色系 (Teal) ---
  /// 全 App 主色（品牌綠）。
  static const Color primary = Color(0xFF59B294);

  /// 主色深階（漸層 / 按下態 / 深色文字）。
  static const Color primaryDark = Color(0xFF2E7D78);

  /// 主色淺階（選中背景 / 淡底）。
  static const Color primaryLight = Color(0xFFE6F4EF);

  /// 主色漸層（按鈕 / 標題卡）。
  static const List<Color> primaryGradient = [primary, primaryDark];

  // --- 強調 / 狀態色 ---
  /// 橘色強調（提醒 / 警示 / 次要行動）。
  static const Color accent = Color(0xFFFF7043);

  /// 成功 / 在線。
  static const Color success = Color(0xFF4CAF50);

  /// 警告。
  static const Color warning = Color(0xFFFFA726);

  /// 錯誤 / 危險。
  static const Color danger = Color(0xFFE53935);

  // --- 中性色 / 背景 ---
  /// 全 App 頁面底色（淺灰）。
  static const Color background = Color(0xFFF1F5F9);

  /// 卡片 / 面板底色。
  static const Color surface = Colors.white;

  /// 分隔線 / 邊框。
  static const Color border = Color(0xFFE2E8F0);

  // --- 文字色階 ---
  /// 主要文字（近黑）。
  static const Color textPrimary = Color(0xFF1E293B);

  /// 次要文字（灰）。
  static const Color textSecondary = Color(0xFF64748B);

  /// 輔助 / 佔位文字（淺灰）。
  static const Color textHint = Color(0xFF94A3B8);
}

/// 統一間距（8pt 系統）。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// 統一圓角。
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double card = 16;
  static const double lg = 24;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
}

/// 統一文字樣式（Noto Sans TC）。
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get title => GoogleFonts.notoSansTc(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      );

  static TextStyle get heading => GoogleFonts.notoSansTc(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.notoSansTc(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get secondary => GoogleFonts.notoSansTc(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );
}

/// 適老化尺度（Elder-friendly）—— 長輩端專用的放大字級 / 大點擊區 / 高對比。
///
/// 客群為「不太會用手機的獨居長輩」，設計原則：字大、按鈕大、對比高、
/// 每屏選項少、圖示一律配文字。長輩端畫面請優先使用這組尺度。
class ElderScale {
  ElderScale._();

  // --- 文字（比一般大 1 級以上）---
  /// 超大標題（如日期、問候語）。
  static TextStyle get displayTitle => GoogleFonts.notoSansTc(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        height: 1.1,
      );

  /// 區塊標題。
  static TextStyle get sectionTitle => GoogleFonts.notoSansTc(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
      );

  /// 大按鈕文字。
  static TextStyle get button => GoogleFonts.notoSansTc(
        fontSize: 28,
        fontWeight: FontWeight.w800,
      );

  /// 內文（長輩可讀最小值）。
  static TextStyle get body => GoogleFonts.notoSansTc(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      );

  /// 次要說明文字。
  static TextStyle get caption => GoogleFonts.notoSansTc(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  /// 賽季卡片主標題（如「第 3 季」）。獨立於 [sectionTitle] 是刻意的——
  /// 賽季卡片是懸浮在畫面角落的窄卡片，30pt 的 [sectionTitle] 在該寬度下
  /// 容易換行或被裁切，24pt 是量過後仍讀得清楚、又能在窄卡片單行顯示的折衷。
  static TextStyle get seasonTitle => GoogleFonts.notoSansTc(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
      );

  /// 賽季卡片副標題（如「還有 12 天結束」）。
  static TextStyle get seasonSubtitle => GoogleFonts.notoSansTc(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // --- 尺寸 ---
  /// 主要大按鈕高度（最小點擊區）。
  static const double buttonHeight = 84;

  /// 大按鈕內圖示尺寸。
  static const double buttonIcon = 40;

  /// 卡片圓角。
  static const double cardRadius = 28;
}

/// 建立全 App 統一的 ThemeData。
ThemeData buildAppTheme(BuildContext context) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
  ).copyWith(
    surface: AppColors.surface,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    extensions: const <ThemeExtension<dynamic>>[UbanColors.light],
    textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
    ),
  );
}

/// 新設計系統的深色 ThemeData（與 [buildAppTheme] 同結構）。
ThemeData buildAppDarkTheme(BuildContext context) {
  const c = UbanColors.dark;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  ).copyWith(surface: c.surface);

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: c.bg,
    extensions: const <ThemeExtension<dynamic>>[UbanColors.dark],
    textTheme: GoogleFonts.notoSansTcTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.text,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
    ),
  );
}

/// 新設計系統陰影（ui.css 的 --shadow / --glass-shadow，中性、不帶色光暈）。
@immutable
class UbanShadows {
  final List<BoxShadow> card;
  final List<BoxShadow> glass;

  const UbanShadows({required this.card, required this.glass});

  static const light = UbanShadows(
    card: [
      BoxShadow(
          color: Color.fromRGBO(16, 40, 30, .05),
          blurRadius: 2,
          offset: Offset(0, 1)),
      BoxShadow(
          color: Color.fromRGBO(16, 40, 30, .05),
          blurRadius: 20,
          offset: Offset(0, 6)),
    ],
    glass: [
      BoxShadow(
          color: Color.fromRGBO(20, 40, 32, .12),
          blurRadius: 30,
          offset: Offset(0, 10)),
    ],
  );

  static const dark = UbanShadows(
    card: [
      BoxShadow(
          color: Color.fromRGBO(0, 0, 0, .3),
          blurRadius: 2,
          offset: Offset(0, 1)),
      BoxShadow(
          color: Color.fromRGBO(0, 0, 0, .2),
          blurRadius: 20,
          offset: Offset(0, 6)),
    ],
    glass: [
      BoxShadow(
          color: Color.fromRGBO(0, 0, 0, .45),
          blurRadius: 30,
          offset: Offset(0, 10)),
    ],
  );

  static UbanShadows lerp(UbanShadows a, UbanShadows b, double t) =>
      UbanShadows(
        card: BoxShadow.lerpList(a.card, b.card, t) ?? a.card,
        glass: BoxShadow.lerpList(a.glass, b.glass, t) ?? a.glass,
      );
}

/// 新設計系統色票（對應 design_prototype/ui.css 的 CSS 變數，淺／深各一組）。
///
/// 取用：`UbanColors.of(context).brand`。既有 [AppColors] 保留作相容層。
@immutable
class UbanColors extends ThemeExtension<UbanColors> {
  final Color brand,
      brandFill,
      onBrand,
      brandStrong,
      brandContainer,
      brandSoft,
      bg,
      surface,
      surface2,
      surface3,
      glass,
      glassLine,
      line,
      text,
      text2,
      text3,
      warm,
      warmContainer,
      danger,
      dangerContainer,
      info,
      infoContainer,
      lineGreen,
      scrim;
  final UbanShadows shadows;

  const UbanColors({
    required this.brand,
    required this.brandFill,
    required this.onBrand,
    required this.brandStrong,
    required this.brandContainer,
    required this.brandSoft,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.glass,
    required this.glassLine,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.warm,
    required this.warmContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
    required this.lineGreen,
    required this.scrim,
    required this.shadows,
  });

  static const UbanColors light = UbanColors(
    brand: Color(0xFF59B294),
    brandFill: Color(0xFF3D9C7C),
    onBrand: Color(0xFFFFFFFF),
    brandStrong: Color(0xFF1F7A5C),
    brandContainer: Color(0xFFDFF3EB),
    brandSoft: Color(0xFFEEF8F4),
    bg: Color(0xFFF6F8F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF3F1),
    surface3: Color(0xFFE3EAE7),
    glass: Color.fromRGBO(255, 255, 255, .76),
    glassLine: Color.fromRGBO(255, 255, 255, .8),
    line: Color(0xFFE3EAE7),
    text: Color(0xFF16201C),
    text2: Color(0xFF5B6B64),
    text3: Color(0xFF8A9A93),
    warm: Color(0xFFB8661F),
    warmContainer: Color(0xFFFDF0E2),
    danger: Color(0xFFE5484D),
    dangerContainer: Color(0xFFFDE8E8),
    info: Color(0xFF2F6FB3),
    infoContainer: Color(0xFFE5EFFA),
    lineGreen: Color(0xFF06C755),
    scrim: Color.fromRGBO(5, 15, 11, .45),
    shadows: UbanShadows.light,
  );

  static const UbanColors dark = UbanColors(
    brand: Color(0xFF6FCBAA),
    brandFill: Color(0xFF6FCBAA),
    onBrand: Color(0xFF062A1D),
    brandStrong: Color(0xFF9BE3C8),
    brandContainer: Color(0xFF17372C),
    brandSoft: Color(0xFF132520),
    bg: Color(0xFF0E1412),
    surface: Color(0xFF171E1B),
    surface2: Color(0xFF1E2724),
    surface3: Color(0xFF26302C),
    glass: Color.fromRGBO(30, 39, 36, .74),
    glassLine: Color.fromRGBO(255, 255, 255, .09),
    line: Color(0xFF26302C),
    text: Color(0xFFECF2EF),
    text2: Color(0xFF9DB0A8),
    text3: Color(0xFF6E7F78),
    warm: Color(0xFFF5B877),
    warmContainer: Color(0xFF3A2A18),
    danger: Color(0xFFFF6B6E),
    dangerContainer: Color(0xFF3A1A1B),
    info: Color(0xFF8DBBEA),
    infoContainer: Color(0xFF18273A),
    lineGreen: Color(0xFF06C755),
    scrim: Color.fromRGBO(0, 0, 0, .6),
    shadows: UbanShadows.dark,
  );

  /// 取目前主題的色票；沒掛 extension 時退回淺色。
  static UbanColors of(BuildContext context) =>
      Theme.of(context).extension<UbanColors>() ?? light;

  @override
  UbanColors copyWith({
    Color? brand,
    Color? brandFill,
    Color? onBrand,
    Color? brandStrong,
    Color? brandContainer,
    Color? brandSoft,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? glass,
    Color? glassLine,
    Color? line,
    Color? text,
    Color? text2,
    Color? text3,
    Color? warm,
    Color? warmContainer,
    Color? danger,
    Color? dangerContainer,
    Color? info,
    Color? infoContainer,
    Color? lineGreen,
    Color? scrim,
    UbanShadows? shadows,
  }) =>
      UbanColors(
        brand: brand ?? this.brand,
        brandFill: brandFill ?? this.brandFill,
        onBrand: onBrand ?? this.onBrand,
        brandStrong: brandStrong ?? this.brandStrong,
        brandContainer: brandContainer ?? this.brandContainer,
        brandSoft: brandSoft ?? this.brandSoft,
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        glass: glass ?? this.glass,
        glassLine: glassLine ?? this.glassLine,
        line: line ?? this.line,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        text3: text3 ?? this.text3,
        warm: warm ?? this.warm,
        warmContainer: warmContainer ?? this.warmContainer,
        danger: danger ?? this.danger,
        dangerContainer: dangerContainer ?? this.dangerContainer,
        info: info ?? this.info,
        infoContainer: infoContainer ?? this.infoContainer,
        lineGreen: lineGreen ?? this.lineGreen,
        scrim: scrim ?? this.scrim,
        shadows: shadows ?? this.shadows,
      );

  @override
  UbanColors lerp(ThemeExtension<UbanColors>? other, double t) {
    if (other is! UbanColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return UbanColors(
      brand: l(brand, other.brand),
      brandFill: l(brandFill, other.brandFill),
      onBrand: l(onBrand, other.onBrand),
      brandStrong: l(brandStrong, other.brandStrong),
      brandContainer: l(brandContainer, other.brandContainer),
      brandSoft: l(brandSoft, other.brandSoft),
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      glass: l(glass, other.glass),
      glassLine: l(glassLine, other.glassLine),
      line: l(line, other.line),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      text3: l(text3, other.text3),
      warm: l(warm, other.warm),
      warmContainer: l(warmContainer, other.warmContainer),
      danger: l(danger, other.danger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      lineGreen: l(lineGreen, other.lineGreen),
      scrim: l(scrim, other.scrim),
      shadows: UbanShadows.lerp(shadows, other.shadows, t),
    );
  }
}
