import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ParticleType {
  heart,
  star,
  confetti,
  score,
  crumb,
  pollen,
  smoke,
  firefly,
  sparkle,
}

class StudioParticle {
  Offset position;
  Offset velocity;
  double scale;
  double opacity;
  double rotation;
  double rotationSpeed;
  Color color;
  ParticleType type;
  String text;
  double life;
  double maxLife;

  StudioParticle({
    required this.position,
    required this.velocity,
    required this.scale,
    required this.opacity,
    required this.color,
    this.rotation = 0.0,
    this.rotationSpeed = 0.0,
    this.type = ParticleType.heart,
    this.text = '',
    this.life = 1.0,
    this.maxLife = 1.0,
  });
}

class PetParticleCanvas extends CustomPainter {
  final List<StudioParticle> particles;

  PetParticleCanvas(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;

      canvas.save();
      canvas.translate(p.position.dx, p.position.dy);
      canvas.rotate(p.rotation);
      canvas.scale(p.scale);

      final paint = Paint()
        ..color = p.color.withValues(alpha: p.opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      switch (p.type) {
        case ParticleType.heart:
          _drawHeart(canvas, paint, 14);
          break;
        case ParticleType.star:
          _drawStar(canvas, paint, 12);
          break;
        case ParticleType.confetti:
          _drawConfetti(canvas, paint, 10, 6);
          break;
        case ParticleType.crumb:
          canvas.drawCircle(Offset.zero, 3.5, paint);
          break;
        case ParticleType.pollen:
          _drawPollen(canvas, p.color, p.opacity);
          break;
        case ParticleType.smoke:
          _drawSmoke(canvas, paint, 16);
          break;
        case ParticleType.firefly:
          _drawFirefly(canvas, p.color, p.opacity);
          break;
        case ParticleType.sparkle:
          _drawSparkle(canvas, paint, 10);
          break;
        case ParticleType.score:
          _drawText(canvas, p.text, p.color, p.opacity);
          break;
      }

      canvas.restore();
    }
  }

  void _drawPollen(Canvas canvas, Color color, double opacity) {
    // 柔和光暈花粉
    final haloPaint = Paint()
      ..color = color.withValues(alpha: (opacity * 0.35).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 8.0, haloPaint);

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 3.0, corePaint);
  }

  void _drawSmoke(Canvas canvas, Paint paint, double radius) {
    // 裊裊白煙雲朵球
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.drawCircle(Offset(radius * 0.5, -radius * 0.2), radius * 0.75, paint);
    canvas.drawCircle(Offset(-radius * 0.4, -radius * 0.3), radius * 0.65, paint);
  }

  void _drawFirefly(Canvas canvas, Color color, double opacity) {
    // 螢火蟲微光呼吸
    final glowPaint = Paint()
      ..color = color.withValues(alpha: (opacity * 0.45).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 9.0, glowPaint);

    final corePaint = Paint()
      ..color = const Color(0xFFFEF08A).withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 2.8, corePaint);
  }

  void _drawSparkle(Canvas canvas, Paint paint, double radius) {
    // 四角星芒閃爍
    final path = Path();
    path.moveTo(0, -radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.quadraticBezierTo(0, 0, 0, radius);
    path.quadraticBezierTo(0, 0, -radius, 0);
    path.quadraticBezierTo(0, 0, 0, -radius);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Paint paint, double size) {
    final path = Path();
    path.moveTo(0, size * 0.35);
    path.cubicTo(-size * 0.7, -size * 0.3, -size * 0.7, size * 0.6, 0, size);
    path.cubicTo(size * 0.7, size * 0.6, size * 0.7, -size * 0.3, 0, size * 0.35);
    canvas.drawPath(path, paint);
  }

  void _drawStar(Canvas canvas, Paint paint, double radius) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final double outerAngle = i * math.pi * 2 / 5 - math.pi / 2;
      final double innerAngle = outerAngle + math.pi / 5;
      final double ox = math.cos(outerAngle) * radius;
      final double oy = math.sin(outerAngle) * radius;
      final double ix = math.cos(innerAngle) * (radius * 0.45);
      final double iy = math.sin(innerAngle) * (radius * 0.45);

      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawConfetti(Canvas canvas, Paint paint, double width, double height) {
    final rect = Rect.fromCenter(center: Offset.zero, width: width, height: height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
  }

  void _drawText(Canvas canvas, String text, Color color, double opacity) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        fontSize: 16,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.25 * opacity),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant PetParticleCanvas oldDelegate) => true;
}
