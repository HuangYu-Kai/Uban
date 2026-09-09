import 'package:flutter/material.dart';
import '../models/pet_mood.dart';

/// 🐾 寵物摸摸愛心粒子繪製器
class PetHeartPainter extends CustomPainter {
  final List<PetHeartParticle> particles;

  PetHeartPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;
      _drawHeart(canvas, p.position, 16 * p.scale, paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final w = size;
    final h = size;
    final x = center.dx - w / 2;
    final y = center.dy - h / 2;

    path.moveTo(x + w / 2, y + h / 4);
    path.cubicTo(x + w / 2, y, x, y, x, y + h / 3);
    path.cubicTo(x, y + h / 2, x + w / 2, y + h * 0.8, x + w / 2, y + h);
    path.cubicTo(x + w / 2, y + h * 0.8, x + w, y + h / 2, x + w, y + h / 3);
    path.cubicTo(x + w, y, x + w / 2, y, x + w / 2, y + h / 4);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PetHeartPainter oldDelegate) => true;
}
