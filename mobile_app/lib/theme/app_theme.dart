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
