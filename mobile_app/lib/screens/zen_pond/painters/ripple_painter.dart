import 'package:flutter/material.dart';

class RippleInfo {
  final Offset position;
  double radius;
  double opacity;

  RippleInfo({required this.position, this.radius = 0.0, this.opacity = 1.0});
}

class RipplePainter extends CustomPainter {
  final List<RippleInfo> ripples;
  final bool isSOSMode;

  RipplePainter({required this.ripples, this.isSOSMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    for (var ripple in ripples) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSOSMode ? 8.0 : 3.0
        ..color = isSOSMode 
            ? Colors.redAccent.withOpacity(ripple.opacity)
            : Colors.white.withOpacity(ripple.opacity);

      canvas.drawCircle(ripple.position, ripple.radius, paint);
      
      // 內圈漣漪 (增加層次感)
      if (ripple.radius > 20) {
        final innerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSOSMode ? 4.0 : 1.5
          ..color = isSOSMode 
              ? Colors.red.withOpacity(ripple.opacity * 0.5)
              : Colors.white.withOpacity(ripple.opacity * 0.5);
        canvas.drawCircle(ripple.position, ripple.radius - 20, innerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RipplePainter oldDelegate) {
    return true; // 每幀都需要重繪漣漪
  }
}
