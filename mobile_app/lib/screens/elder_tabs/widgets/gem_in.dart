import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../theme/uban_motion.dart';

/// 設計稿 `.gem-in`「寶石鑲入」入場（ui.css 716–720）：由上方略大降下 → 壓入卡一下 →
/// 插槽鎖定，0.66s、每項錯開 [index] × 95ms。
///
/// 播放時機：首次建構、以及「所在分頁由隱藏變為可見」時各一次。長輩外殼用
/// `IndexedStack` 保活各分頁，被切走的分頁其 `TickerMode` 會被關閉，所以這裡監聽
/// `TickerMode` 的開關就能做到「每次切回首頁重播」。系統開啟「移除動畫」時完全不播。
///
/// 延遲用 [AnimationController] 內的時間軸實作（不用 Timer），測試不會留下未結束的計時器。
class GemIn extends StatefulWidget {
  final int index;
  final double radius;
  final Widget child;

  const GemIn({
    super.key,
    required this.index,
    required this.child,
    this.radius = 24,
  });

  @override
  State<GemIn> createState() => _GemInState();
}

class _GemInState extends State<GemIn> with SingleTickerProviderStateMixin {
  static const int _durMs = 660;
  static const int _staggerMs = 95;
  static const Cubic _curve = Cubic(.3, .85, .3, 1);

  late final AnimationController _c;
  ValueListenable<TickerModeData>? _mode;
  bool _wasEnabled = true;
  bool _started = false;

  int get _delayMs => widget.index * _staggerMs;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durMs + _delayMs),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = TickerMode.getValuesNotifier(context);
    if (!identical(n, _mode)) {
      _mode?.removeListener(_onModeChanged);
      _mode = n..addListener(_onModeChanged);
      _wasEnabled = n.value.enabled;
    }
    if (!_started) {
      _started = true;
      _play();
    }
  }

  void _onModeChanged() {
    final enabled = _mode!.value.enabled;
    if (enabled && !_wasEnabled) _play();
    _wasEnabled = enabled;
  }

  void _play() {
    if (!mounted) return;
    if (reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _mode?.removeListener(_onModeChanged);
    _c.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b) =>
      _curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (_c.value >= 1) return child!;
        final totalMs = _durMs + _delayMs;
        final t = ((_c.value * totalMs - _delayMs) / _durMs).clamp(0.0, 1.0);

        // 關鍵影格 0 / 58 / 73 / 88 / 100%（ui.css gemset）。
        final double y, scale, opacity;
        if (t < .58) {
          final s = _seg(t, 0, .58);
          y = _lerp(-16, 0, s);
          scale = _lerp(1.07, 1, s);
          opacity = s;
        } else if (t < .73) {
          final s = _seg(t, .58, .73);
          y = _lerp(0, 1.5, s);
          scale = _lerp(1, .99, s);
          opacity = 1;
        } else if (t < .88) {
          final s = _seg(t, .73, .88);
          y = _lerp(1.5, 0, s);
          scale = _lerp(.99, 1.004, s);
          opacity = 1;
        } else {
          final s = _seg(t, .88, 1);
          y = 0;
          scale = _lerp(1.004, 1, s);
          opacity = 1;
        }

        // gemseat：卡片上緣的內陰影，46% 起浮現、62% 最深、之後淡出。
        double seat = 0;
        if (t >= .46 && t < .62) {
          seat = (t - .46) / .16;
        } else if (t >= .62) {
          seat = 1 - (t - .62) / .38;
        }

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, y, 0)
              ..scaleByDouble(scale, scale, 1, 1),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                if (seat > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 22,
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(widget.radius)),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: .14 * seat),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
