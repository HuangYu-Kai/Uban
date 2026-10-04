import 'package:flutter/material.dart';

import '../../theme/uban_motion.dart';

/// 按下縮到 0.96（50ms easeOut），放開以 springBack 回彈（320ms）。
/// 系統開啟「移除動畫」時不縮放。
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.pressedScale = 0.96,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _active =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool v) {
    if (_down == v || !mounted) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final scale = (_down && !reduce) ? widget.pressedScale : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _active ? (_) => _set(true) : null,
      onTapUp: _active ? (_) => _set(false) : null,
      onTapCancel: _active ? () => _set(false) : null,
      onTap: _active ? widget.onTap : null,
      onLongPress: _active ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: scale,
        duration: reduce
            ? Duration.zero
            : (_down
                ? UbanMotion.pressOutDuration
                : UbanMotion.springBackDuration),
        curve: _down ? UbanMotion.pressOut : UbanMotion.springBack,
        child: widget.child,
      ),
    );
  }
}
