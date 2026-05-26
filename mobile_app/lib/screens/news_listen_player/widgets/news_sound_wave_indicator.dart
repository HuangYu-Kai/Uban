import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class NewsSoundWaveIndicator extends StatefulWidget {
  final bool isPlaying;

  const NewsSoundWaveIndicator({
    super.key,
    required this.isPlaying,
  });

  @override
  State<NewsSoundWaveIndicator> createState() => _NewsSoundWaveIndicatorState();
}

class _NewsSoundWaveIndicatorState extends State<NewsSoundWaveIndicator> {
  Timer? _waveTimer;
  List<double> _waveHeights = List<double>.filled(11, 34);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      _startWaveAnimation();
    } else {
      _stopWaveAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant NewsSoundWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startWaveAnimation();
      } else {
        _stopWaveAnimation();
      }
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    super.dispose();
  }

  void _startWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted || !widget.isPlaying) return;
      setState(() {
        _waveHeights = List<double>.generate(11, (i) {
          final base = 28 + (i.isOdd ? 8 : 0);
          return base + _random.nextInt(50).toDouble();
        });
      });
    });
  }

  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
    if (!mounted) return;
    setState(() {
      _waveHeights = List<double>.filled(11, 34);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_waveHeights.length, (i) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 8,
            height: _waveHeights[i] * 0.6,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
            ),
          );
        }),
      ),
    );
  }
}
