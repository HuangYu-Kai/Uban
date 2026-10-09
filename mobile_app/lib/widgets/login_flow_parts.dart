import 'package:flutter/material.dart';

import 'ui/ui.dart';

/// 登入流程各畫面共用的小零件（設計稿 `.mark`、`.label`、`.h1`、`.body`）。
///
/// 只負責外觀，不含任何行為；配色一律走 [UbanColors]。

/// 設計稿 `.h1`：30/900、行高 1.25。
TextStyle ubanH1(BuildContext context, {double size = 30}) =>
    ubanText(size, FontWeight.w900, UbanColors.of(context).text, height: 1.25);

/// 設計稿 `.body`：18、行高 1.55、text2。
TextStyle ubanBody(BuildContext context, {double size = 18}) =>
    ubanText(size, FontWeight.w400, UbanColors.of(context).text2, height: 1.55);

/// 設計稿 `.label`：13/700、字距 .1em、text3。
class UbanLabel extends StatelessWidget {
  final String text;
  const UbanLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: ubanText(13, FontWeight.w700, UbanColors.of(context).text3,
            letterSpacingEm: .1),
      );
}

/// 設計稿 `.mark`：圓角方塊。未指定 [color] 時為品牌綠漸層（與愛心標誌搭配）。
class UbanMarkBox extends StatelessWidget {
  final double size;
  final double radius;
  final Color? color;
  final Widget child;

  const UbanMarkBox({
    super.key,
    this.size = 72,
    this.radius = 22,
    this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        gradient: color == null
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 品牌標誌固定色（ui.css .mark），深淺色模式皆不變。
                colors: [Color(0xFF5CBB9B), Color(0xFF4DAD88)],
              )
            : null,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// 品牌標誌：直接顯示 App 圖示（`assets/images/app_icon.png`）。
///
/// 原本是照設計稿 `#i-heartmark` 用 CustomPaint 畫的愛心，造型與實際 App 圖示
/// 不一致（人頭與愛心比例、線條、配色都不同），改為全 App 共用同一張圖。
/// 圖檔本身已含綠底與圓角，不要再包 [UbanMarkBox]。
class UbanAppLogo extends StatelessWidget {
  final double size;
  final double radius;
  const UbanAppLogo({super.key, this.size = 72, this.radius = 22});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'Uban',
        ),
      );
}
