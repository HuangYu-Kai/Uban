import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 動效常數（對應 design_prototype/ui.css、ui.js）。
class UbanMotion {
  UbanMotion._();

  // 按下：50ms easeOut；放開：320ms springBack（過衝回彈）
  static const Duration pressOutDuration = Duration(milliseconds: 50);
  static const Curve pressOut = Curves.easeOut;

  static const Duration springBackDuration = Duration(milliseconds: 320);
  static const Curve springBack = Cubic(.34, 1.56, .64, 1);

  static const Duration enterDuration = Duration(milliseconds: 320);
  static const Curve enter = Cubic(.2, .8, .2, 1);

  static const Duration pushDuration = Duration(milliseconds: 380);
  static const Curve push = Cubic(.2, .8, .2, 1);

  static const Duration sheetDuration = Duration(milliseconds: 450);
  static const Curve sheet = Cubic(.32, 1.2, .5, 1);

  static const Duration dialogDuration = Duration(milliseconds: 400);
  static const Curve dialog = Cubic(.34, 1.4, .64, 1);

  static const Duration segThumbDuration = Duration(milliseconds: 420);
  static const Curve segThumb = Cubic(.34, 1.4, .64, 1);

  static const Duration ringDuration = Duration(milliseconds: 700);
  static const Curve ring = Cubic(.34, 1.3, .64, 1);

  static const Duration switchDuration = Duration(milliseconds: 380);

  static final SpringDescription navSpring = uSpring(0.8, 380);
  static final SpringDescription fastSpring = uSpring(0.6, 800);
  static final SpringDescription tutorialSpring = uSpring(0.75, 300);
}

/// 同 ui.js `Spring(zeta, k)`：mass 1、stiffness k、damping 2ζ√k。
SpringDescription uSpring(double zeta, double k) =>
    SpringDescription(mass: 1, stiffness: k, damping: 2 * zeta * math.sqrt(k));

/// 系統「移除動畫」開啟時回傳 true。
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
