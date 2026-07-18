import 'package:flutter/material.dart';

class SoundWaveIndicator extends StatefulWidget {
  final Color color;
  const SoundWaveIndicator({super.key, required this.color});

  @override
  State<SoundWaveIndicator> createState() => _SoundWaveIndicatorState();
}

class _SoundWaveIndicatorState extends State<SoundWaveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final double begin = 0.2 + (i * 0.2);
          final Animation<double> animation = Tween<double>(begin: begin, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(i * 0.15, 1.0, curve: Curves.easeInOut),
            ),
          );

          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Container(
                width: 4,
                height: 4 + animation.value * 12,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
