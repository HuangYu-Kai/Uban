import 'package:flutter/material.dart';

class FlyingFood extends StatefulWidget {
  final Offset startPos;
  final Offset endPos;
  final String foodEmoji;
  final VoidCallback onComplete;

  const FlyingFood({
    super.key,
    required this.startPos,
    required this.endPos,
    this.foodEmoji = '🍎',
    required this.onComplete,
  });

  @override
  State<FlyingFood> createState() => _FlyingFoodState();
}

class _FlyingFoodState extends State<FlyingFood> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad);

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        
        // 拋物線邏輯
        // X 是線性插值
        final x = widget.startPos.dx + (widget.endPos.dx - widget.startPos.dx) * t;
        // Y 加上一個弧度 (拱橋形)
        final yBase = widget.startPos.dy + (widget.endPos.dy - widget.startPos.dy) * t;
        final arc = -150 * (4 * (t - 0.5) * (t - 0.5) - 1); // 拋物線高度
        
        // 縮放 (飛過去變小)
        final scale = 1.2 - (t * 0.5);

        return Positioned(
          left: x - 25,
          top: yBase + arc - 25,
          child: Opacity(
            opacity: t < 0.1 ? t * 10 : (t > 0.9 ? (1 - t) * 10 : 1.0),
            child: Transform.scale(
              scale: scale,
              child: Text(widget.foodEmoji, style: const TextStyle(fontSize: 40)),
            ),
          ),
        );
      },
    );
  }
}
