import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── 大頭貼位置點（目前位置） ────────────────────────────────
class AvatarPin extends StatefulWidget {
  const AvatarPin({super.key});

  @override
  State<AvatarPin> createState() => _AvatarPinState();
}

class _AvatarPinState extends State<AvatarPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceOffsetY;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bounceOffsetY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -7,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -7,
          end: 3,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 3,
          end: -1.5,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -1.5,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
    ]).animate(_bounceController);
    _bounceController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceOffsetY,
      builder: (context, child) {
        final dy = _bounceOffsetY.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 頭像（上方）
            Positioned(
              top: 4 + dy,
              left: 12,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE0E0E0),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const ClipOval(
                  child: Icon(Icons.person, size: 28, color: Color(0xFF757575)),
                ),
              ),
            ),
            // 倒三角（中間）
            Positioned(
              top: 57 + dy,
              left: 26,
              child: const SizedBox(
                width: 20,
                height: 14,
                child: CustomPaint(
                  painter: PinPointerPainter(),
                ),
              ),
            ),
            // 綠色圓環（所在地錨點）
            Positioned(
              left: 29,
              top: 74,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF59B294), width: 3),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PinPointerPainter extends CustomPainter {
  const PinPointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pointerPath = _buildRoundedTrianglePath(size);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.save();
    canvas.translate(0, 1);
    canvas.drawPath(pointerPath, shadowPaint);
    canvas.restore();

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(pointerPath, fillPaint);
  }

  Path _buildRoundedTrianglePath(Size size) {
    const baseRadius = 2.6;
    final a = const Offset(0, 0);
    final b = Offset(size.width, 0);
    final c = Offset(size.width / 2, size.height);
    final radius = math.min(
      baseRadius,
      math.min(size.width, size.height) / 4,
    );

    final aIn = _pointToward(a, c, radius);
    final aOut = _pointToward(a, b, radius);
    final bIn = _pointToward(b, a, radius);
    final bOut = _pointToward(b, c, radius);
    final cIn = _pointToward(c, b, radius);
    final cOut = _pointToward(c, a, radius);

    return Path()
      ..moveTo(aOut.dx, aOut.dy)
      ..lineTo(bIn.dx, bIn.dy)
      ..quadraticBezierTo(b.dx, b.dy, bOut.dx, bOut.dy)
      ..lineTo(cIn.dx, cIn.dy)
      ..quadraticBezierTo(c.dx, c.dy, cOut.dx, cOut.dy)
      ..lineTo(aIn.dx, aIn.dy)
      ..quadraticBezierTo(a.dx, a.dy, aOut.dx, aOut.dy)
      ..close();
  }

  Offset _pointToward(Offset from, Offset to, double distance) {
    final vector = to - from;
    final length = vector.distance;
    if (length == 0) return from;
    final safeDistance = math.min(distance, length / 2);
    return from + (vector / length) * safeDistance;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 步數泡泡下方小三角 ──────────────────────────────────────
class TrianglePainter extends CustomPainter {
  const TrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
