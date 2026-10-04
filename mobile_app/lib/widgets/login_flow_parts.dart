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

/// 設計稿 `#i-heartmark`：品牌愛心標誌（64×64 viewBox）。
class UbanHeartMark extends StatelessWidget {
  final double size;
  const UbanHeartMark({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HeartMarkPainter()),
      );
}

class _HeartMarkPainter extends CustomPainter {
  // 品牌標誌固定色（#D1EEE7）。
  static const Color _ink = Color(0xFFD1EEE7);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(32, 15), 9, fill);
    final heart = Path()
      ..moveTo(32, 54)
      ..cubicTo(20, 46, 12, 38, 12, 30)
      ..arcToPoint(const Offset(32, 27), radius: const Radius.circular(10))
      ..arcToPoint(const Offset(52, 30), radius: const Radius.circular(10))
      ..cubicTo(52, 38, 44, 46, 32, 54)
      ..close();
    canvas.drawPath(heart, stroke);
    canvas.drawLine(const Offset(17, 37), const Offset(32, 27), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
