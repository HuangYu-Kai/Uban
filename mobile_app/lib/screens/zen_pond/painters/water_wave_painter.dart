import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaterWavePainter extends CustomPainter {
  final double animationValue;
  final bool isSOSMode;

  WaterWavePainter({required this.animationValue, this.isSOSMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    
    // 繪製兩層波浪
    _drawWave(canvas, size, paint, 
        color: const Color(0xFFD4E9DF).withOpacity(0.5), 
        amplitude: 15.0, 
        frequency: 0.015, 
        phaseShift: animationValue * 2 * math.pi, 
        verticalShift: size.height * 0.4);
        
    _drawWave(canvas, size, paint, 
        color: const Color(0xFFBCE0D1).withOpacity(0.4), 
        amplitude: 20.0, 
        frequency: 0.01, 
        phaseShift: animationValue * 2 * math.pi + math.pi, 
        verticalShift: size.height * 0.6);
  }

  void _drawWave(Canvas canvas, Size size, Paint paint, 
      {required Color color, required double amplitude, required double frequency, required double phaseShift, required double verticalShift}) {
    paint.color = color;
    final path = Path();
    path.moveTo(0, size.height);
    
    for (double i = 0; i <= size.width; i++) {
      double y = math.sin((i * frequency) + phaseShift) * amplitude + verticalShift;
      if (i == 0) {
        path.lineTo(0, y);
      } else {
        path.lineTo(i, y);
      }
    }
    
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.isSOSMode != isSOSMode;
  }
}
