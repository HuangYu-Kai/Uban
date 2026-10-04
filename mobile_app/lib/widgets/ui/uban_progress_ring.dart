import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';
import 'uban_text.dart';

/// 設計稿 `.ring`：88×88、半徑 38、線寬 9、底 surface3、前景 brand 圓頭，
/// 中央 Poppins「done/total」（/total 17）；值變化 700ms 彈性動畫。
class UbanProgressRing extends StatelessWidget {
  final int done;
  final int total;

  const UbanProgressRing({super.key, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final target = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final dur = reduceMotion(context) ? Duration.zero : UbanMotion.ringDuration;
    return Semantics(
      label: '完成 $done，共 $total',
      excludeSemantics: true,
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: dur,
              curve: UbanMotion.ring,
              builder: (context, v, _) => CustomPaint(
                size: const Size(88, 88),
                painter: _RingPainter(
                  progress: v,
                  track: c.surface3,
                  fill: c.brand,
                ),
              ),
            ),
            // 環內空間固定，數字不隨系統字級放大，並可縮小以免溢出。
            SizedBox(
              width: 60,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: '$done',
                    style:
                        ubanBrandText(26, FontWeight.w600, c.text, height: 1),
                    children: [
                      TextSpan(
                        text: '/$total',
                        style: ubanBrandText(17, FontWeight.w600, c.text2,
                            height: 1),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color fill;

  _RingPainter(
      {required this.progress, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = 38.0;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = track;
    canvas.drawCircle(center, r, bg);
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = fill;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2,
        2 * math.pi * p, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.fill != fill;
}
