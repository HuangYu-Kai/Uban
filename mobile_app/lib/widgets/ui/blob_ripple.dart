import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/uban_motion.dart';

/// 液態暈開（ui.js blobPoly）：從觸點長出一圈邊緣起伏的色塊，620ms、easeOutQuart，
/// k>.55 後淡出。系統「移除動畫」時停用。
///
/// 包住 [child]，在其上方疊一層不吃事件的暈開層；以 [borderRadius] 裁切。
class BlobRipple extends StatefulWidget {
  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final bool enabled;

  const BlobRipple({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = BorderRadius.zero,
    this.enabled = true,
  });

  @override
  State<BlobRipple> createState() => _BlobRippleState();
}

class _Blob {
  final Offset center;
  final AnimationController controller;
  _Blob(this.center, this.controller);
}

class _BlobRippleState extends State<BlobRipple> with TickerProviderStateMixin {
  final List<_Blob> _blobs = [];

  static const int points = 90;
  static const Duration duration = Duration(milliseconds: 620);

  void _spawn(Offset local) {
    if (!widget.enabled || reduceMotion(context)) return;
    final c = AnimationController(vsync: this, duration: duration);
    final blob = _Blob(local, c);
    setState(() => _blobs.add(blob));
    c.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _blobs.remove(blob));
      c.dispose();
    });
  }

  @override
  void dispose() {
    for (final b in _blobs) {
      b.controller.dispose();
    }
    _blobs.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _spawn(e.localPosition),
      child: Stack(
        // passthrough：父層給固定寬（Expanded／stretch）時子元件照樣撐滿；
        // 預設 loose 會把它放鬆，雙欄卡就縮成文字寬、中間空一大塊。
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_blobs.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
                  child: Stack(
                    children: [
                      for (final b in _blobs)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: b.controller,
                            builder: (context, _) {
                              final k = b.controller.value;
                              final p = Curves.easeOutQuart.transform(k);
                              final opacity =
                                  k < .55 ? 1.0 : 1 - (k - .55) / .45;
                              return ClipPath(
                                clipper:
                                    BlobClipper(center: b.center, progress: p),
                                child: Opacity(
                                  opacity: opacity.clamp(0.0, 1.0),
                                  child: ColoredBox(color: widget.color),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 暈開輪廓：r(t)=R+sin(3t)·A·.7+cos(5t−6p)·A·.5+sin(7t+4p)·A·.3。
class BlobClipper extends CustomClipper<Path> {
  final Offset center;
  final double progress;

  const BlobClipper({required this.center, required this.progress});

  @override
  Path getClip(Size size) {
    final x = center.dx, y = center.dy;
    final maxR = math.sqrt(
      math.pow(math.max(x, size.width - x), 2) +
          math.pow(math.max(y, size.height - y), 2),
    );
    final p = progress;
    final a = maxR * 0.08 * p;
    final r0 = maxR * p * 1.2;
    final path = Path();
    for (var i = 0; i < _BlobRippleState.points; i++) {
      final t = i / _BlobRippleState.points * math.pi * 2;
      final r = r0 +
          math.sin(3 * t) * a * .7 +
          math.cos(5 * t - p * 6) * a * .5 +
          math.sin(7 * t + p * 4) * a * .3;
      final px = x + math.cos(t) * r;
      final py = y + math.sin(t) * r;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(BlobClipper old) =>
      old.progress != progress || old.center != center;
}
