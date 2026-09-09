import 'package:flutter/material.dart';

/// 金鑰自繪圖形 (Golden Key)
class GoldenKeyPainter extends CustomPainter {
  const GoldenKeyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7043)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.5, size.height * 0.35);

    canvas.drawCircle(center, size.width * 0.22, paint);

    canvas.drawLine(
      center + Offset(0, size.width * 0.22),
      Offset(size.width * 0.5, size.height * 0.9),
      paint,
    );

    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.7),
      Offset(size.width * 0.75, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.85),
      Offset(size.width * 0.7, size.height * 0.85),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 虛線連線自繪圖形 (Connection Line)
class ConnectionLinePainter extends CustomPainter {
  const ConnectionLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF59B294).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final p0 = Offset(size.width * 0.32, size.height * 0.55);
    final p1 = Offset(size.width * 0.5, size.height * 0.15);
    final p2 = Offset(size.width * 0.68, size.height * 0.55);

    for (double t = 0; t <= 1.0; t += 0.05) {
      final x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
      final y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 錯誤叉叉自繪圖形 (Cozy Error)
class CozyErrorPainter extends CustomPainter {
  const CozyErrorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.3),
      Offset(size.width * 0.7, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.3),
      Offset(size.width * 0.3, size.height * 0.7),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
