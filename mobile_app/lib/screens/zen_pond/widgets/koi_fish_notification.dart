import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;

// 真正會「扭動身軀」且具備豐富細節的漂亮錦鯉
class PremiumKoiPainter extends CustomPainter {
  final double animationValue; // 0.0 到 1.0 的週期值

  PremiumKoiPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // 魚身長度稍微縮短，留空間給尾鰭
    final length = size.height * 0.8; 
    final maxWiggle = size.width * 0.25; // 扭動幅度

    // 1. 計算魚骨架 (脊椎)
    List<Offset> spine = [];
    final int segments = 20;
    for (int i = 0; i <= segments; i++) {
      double t = i / segments; // 0.0 (頭) 到 1.0 (尾)
      
      // 扭動公式：頭部(t=0)幾乎不動，尾部(t=1)擺動最大
      double wiggle = math.sin(t * math.pi * 2 - animationValue * math.pi * 2) * maxWiggle * math.pow(t, 1.8);
      
      // 往下偏移一點留給頭部空間
      spine.add(Offset(size.width * 0.5 + wiggle, t * length + size.height * 0.1));
    }

    // 計算每個骨架節點的角度與法向量
    List<double> angles = [];
    List<Offset> leftSide = [];
    List<Offset> rightSide = [];

    for (int i = 0; i <= segments; i++) {
      double t = i / segments;
      Offset p = spine[i];
      
      // 計算魚身寬度分佈 (流線型，頭部圓潤，身體至尾部漸細)
      double width;
      if (t < 0.15) {
        width = math.sin(t / 0.15 * math.pi * 0.5) * (size.width * 0.28); 
      } else {
        width = math.cos((t - 0.15) / 0.85 * math.pi * 0.5) * (size.width * 0.28);
      }

      double dx = 1.0;
      double dy = 0.0;
      if (i < segments - 1) {
        double dirX = spine[i+1].dx - p.dx;
        double dirY = spine[i+1].dy - p.dy;
        double len = math.sqrt(dirX * dirX + dirY * dirY);
        if (len > 0) {
          dx = -dirY / len;
          dy = dirX / len;
          angles.add(math.atan2(dirY, dirX));
        } else {
          angles.add(i > 0 ? angles[i-1] : math.pi / 2);
        }
      } else {
        angles.add(angles.isNotEmpty ? angles.last : math.pi / 2);
        if (i > 0) {
          double dirX = p.dx - spine[i-1].dx;
          double dirY = p.dy - spine[i-1].dy;
          double len = math.sqrt(dirX * dirX + dirY * dirY);
          if (len > 0) {
            dx = -dirY / len;
            dy = dirX / len;
          }
        }
      }

      leftSide.add(Offset(p.dx + dx * width, p.dy + dy * width));
      rightSide.add(Offset(p.dx - dx * width, p.dy - dy * width));
    }

    final finPaint = Paint()
      ..color = const Color(0xDDFF7043) // 半透明的亮橘色鰭
      ..style = PaintingStyle.fill;

    // 2. 畫胸鰭 (Pectoral Fins)
    int finBase = 4;
    int finEnd = 8;
    
    // 左胸鰭
    double leftFinAngle = angles[finBase] + math.pi * 0.35 + math.sin(animationValue * math.pi * 2) * 0.2;
    Path leftFin = Path()
      ..moveTo(leftSide[finBase].dx, leftSide[finBase].dy)
      ..quadraticBezierTo(
        leftSide[finBase].dx + math.cos(leftFinAngle) * size.width * 0.7,
        leftSide[finBase].dy + math.sin(leftFinAngle) * size.width * 0.7,
        leftSide[finEnd].dx, leftSide[finEnd].dy,
      );
    canvas.drawPath(leftFin, finPaint);

    // 右胸鰭
    double rightFinAngle = angles[finBase] - math.pi * 0.35 - math.sin(animationValue * math.pi * 2) * 0.2;
    Path rightFin = Path()
      ..moveTo(rightSide[finBase].dx, rightSide[finBase].dy)
      ..quadraticBezierTo(
        rightSide[finBase].dx + math.cos(rightFinAngle) * size.width * 0.7,
        rightSide[finBase].dy + math.sin(rightFinAngle) * size.width * 0.7,
        rightSide[finEnd].dx, rightSide[finEnd].dy,
      );
    canvas.drawPath(rightFin, finPaint);

    // 3. 畫魚身 (Body)
    final Path bodyPath = Path();
    bodyPath.moveTo(leftSide[0].dx, leftSide[0].dy);
    for (var p in leftSide) {
      bodyPath.lineTo(p.dx, p.dy);
    }
    for (var p in rightSide.reversed) {
      bodyPath.lineTo(p.dx, p.dy);
    }
    bodyPath.close();

    // 給魚身加上漂亮的漸層色
    final Rect bounds = bodyPath.getBounds();
    final Paint bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE64A19), Color(0xFFFF8A65)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds)
      ..style = PaintingStyle.fill;
    
    canvas.drawShadow(bodyPath, Colors.black26, 6.0, false);
    canvas.drawPath(bodyPath, bodyPaint);

    // 4. 畫尾鰭 (Tail Fin)
    canvas.save();
    canvas.translate(spine.last.dx, spine.last.dy);
    canvas.rotate(angles.last - math.pi / 2);
    
    Path tailFin = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-size.width * 0.4, size.height * 0.1, -size.width * 0.3, size.height * 0.2)
      ..quadraticBezierTo(0, size.height * 0.15, size.width * 0.3, size.height * 0.2)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.1, 0, 0);
      
    canvas.drawPath(tailFin, finPaint);
    canvas.restore();

    // 5. 畫有機形狀的白斑 (Markings)
    final spotPaint = Paint()..color = Colors.white.withOpacity(0.9);
    
    // 頭部白斑
    Path spot1 = Path()
      ..moveTo(spine[2].dx, spine[2].dy)
      ..quadraticBezierTo(leftSide[2].dx, leftSide[2].dy, leftSide[5].dx, leftSide[5].dy)
      ..quadraticBezierTo(spine[6].dx, spine[6].dy, rightSide[3].dx, rightSide[3].dy)
      ..close();
    canvas.drawPath(spot1, spotPaint);
    
    // 背部大白斑
    Path spot2 = Path()
      ..moveTo(spine[9].dx, spine[9].dy)
      ..quadraticBezierTo(leftSide[8].dx, leftSide[8].dy, leftSide[12].dx, leftSide[12].dy)
      ..quadraticBezierTo(spine[14].dx, spine[14].dy, rightSide[13].dx, rightSide[13].dy)
      ..quadraticBezierTo(rightSide[10].dx, rightSide[10].dy, spine[9].dx, spine[9].dy)
      ..close();
    canvas.drawPath(spot2, spotPaint);

    // 6. 畫眼睛 (Eyes)
    final Paint eyePaint = Paint()..color = Colors.black87;
    final Paint eyeWhite = Paint()..color = Colors.white;
    
    // 眼睛稍微往兩側邊緣靠
    Offset leftEye = Offset(leftSide[2].dx * 0.7 + spine[2].dx * 0.3, leftSide[2].dy * 0.7 + spine[2].dy * 0.3);
    Offset rightEye = Offset(rightSide[2].dx * 0.7 + spine[2].dx * 0.3, rightSide[2].dy * 0.7 + spine[2].dy * 0.3);
    
    canvas.drawCircle(leftEye, 3.0, eyePaint);
    canvas.drawCircle(leftEye, 1.0, eyeWhite); // 眼神光
    
    canvas.drawCircle(rightEye, 3.0, eyePaint);
    canvas.drawCircle(rightEye, 1.0, eyeWhite);
  }

  @override
  bool shouldRepaint(covariant PremiumKoiPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class KoiFishNotification extends StatefulWidget {
  final VoidCallback onTap;

  const KoiFishNotification({super.key, required this.onTap});

  @override
  State<KoiFishNotification> createState() => _KoiFishNotificationState();
}

class _KoiFishNotificationState extends State<KoiFishNotification> with SingleTickerProviderStateMixin {
  late AnimationController _swimController;

  @override
  void initState() {
    super.initState();
    _swimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 擺尾速度
    )..repeat(); 
  }

  @override
  void dispose() {
    _swimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      right: 40,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _swimController,
          builder: (context, child) {
            return Transform.rotate(
              angle: -math.pi / 4, // 魚頭朝向左上角(游動路徑)
              child: CustomPaint(
                size: const Size(60, 120), // 魚的空間範圍
                painter: PremiumKoiPainter(
                  animationValue: _swimController.value,
                ),
              ),
            );
          },
        ),
      ),
    )
    .animate()
    .fadeIn(duration: 800.ms)
    // 對角線斜向游進來
    .move(
      begin: const Offset(150, 150),
      end: Offset.zero,
      duration: 3500.ms,
      curve: Curves.easeOutCubic,
    )
    .moveX(
      begin: 50,
      end: 0,
      duration: 2000.ms,
      curve: Curves.easeInOutSine,
    )
    .then()
    // 原地輕微浮動
    .moveY(
      begin: 0,
      end: -10,
      duration: 2500.ms,
      curve: Curves.easeInOutSine,
    ).animate(onPlay: (c) => c.repeat(reverse: true));
  }
}
