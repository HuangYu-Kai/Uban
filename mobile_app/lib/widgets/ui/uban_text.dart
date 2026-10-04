import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 設計系統內部用的字型輔助（Noto Sans TC 走本地 family，Poppins 走 google_fonts）。
TextStyle ubanText(
  double size,
  FontWeight weight,
  Color color, {
  double letterSpacingEm = 0,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'NotoSansTC',
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacingEm * size,
      height: height,
    );

/// 品牌數字字型（Poppins），用於數字、時間、計數。
TextStyle ubanBrandText(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
