import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';

enum ProceduralMood {
  idle,
  anticipating,
  chewing,
  superHappy,
  celebratingGoal,
  sleeping,
}

class ProceduralPigletActor extends StatefulWidget {
  final ProceduralMood mood;
  final Function(PetFoodItem food)? onFoodAccepted;
  final VoidCallback? onPetHead;
  final VoidCallback? onPokeBelly;
  final double size;
  final String speechText;
  final bool isCrownUnlocked;

  const ProceduralPigletActor({
    super.key,
    this.mood = ProceduralMood.idle,
    this.onFoodAccepted,
    this.onPetHead,
    this.onPokeBelly,
    this.size = 280,
    this.speechText = '',
    this.isCrownUnlocked = false,
  });

  @override
  State<ProceduralPigletActor> createState() => _ProceduralPigletActorState();
}

class _ProceduralPigletActorState extends State<ProceduralPigletActor>
    with TickerProviderStateMixin {
  // ── 骨骼與物理動畫控制器 ──
  late AnimationController _breatheController;
  late AnimationController _blinkController;
  late AnimationController _earTwitchController;
  late AnimationController _chewController;
  late AnimationController _jumpController;
  late AnimationController _squishController;
  late AnimationController _tailWagController;

  Timer? _blinkTimer;
  Timer? _earTwitchTimer;

  Offset _lookTarget = Offset.zero; // 眼睛注視目標（正規化 -1.0 ~ 1.0）
  bool _isDragHovering = false;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // 1. 溫和呼吸 (Breathing Cycle)
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 2. 自然眨眼 (Autonomic Blinking)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scheduleNextBlink();

    // 3. 耳朵偶爾抖動 (Ear Twitching)
    _earTwitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scheduleNextEarTwitch();

    // 4. 咀嚼動態 (Chewing Cycle)
    _chewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    // 5. 歡呼跳躍 (Joyful Jump)
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 6. Q 彈壓扁物理回彈 (Elastic Squish & Rebound)
    _squishController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 7. 尾巴搖擺 (Tail Wagging)
    _tailWagController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final delayMs = 2500 + _random.nextInt(3500);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted && widget.mood != ProceduralMood.sleeping) {
        _blinkController.forward(from: 0.0).then((_) {
          if (mounted) {
            _blinkController.reverse().then((_) => _scheduleNextBlink());
          }
        });
      } else {
        _scheduleNextBlink();
      }
    });
  }

  void _scheduleNextEarTwitch() {
    _earTwitchTimer?.cancel();
    final delayMs = 3000 + _random.nextInt(4000);
    _earTwitchTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) {
        _earTwitchController.forward(from: 0.0).then((_) {
          if (mounted) {
            _earTwitchController.reverse().then((_) => _scheduleNextEarTwitch());
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProceduralPigletActor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.mood != oldWidget.mood) {
      if (widget.mood == ProceduralMood.chewing) {
        _chewController.repeat(reverse: true);
        Timer(const Duration(milliseconds: 2000), () {
          if (mounted && widget.mood != ProceduralMood.chewing) {
            _chewController.stop();
          }
        });
      } else {
        _chewController.stop();
      }

      if (widget.mood == ProceduralMood.superHappy ||
          widget.mood == ProceduralMood.celebratingGoal) {
        _jumpController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _earTwitchTimer?.cancel();
    _breatheController.dispose();
    _blinkController.dispose();
    _earTwitchController.dispose();
    _chewController.dispose();
    _jumpController.dispose();
    _squishController.dispose();
    _tailWagController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    // 即時追蹤手指觸摸位置，計算眼球注視角度
    final center = Offset(size.width / 2, size.height / 2);
    final delta = details.localPosition - center;
    final double maxDist = size.width / 2;
    setState(() {
      _lookTarget = Offset(
        (delta.dx / maxDist).clamp(-1.0, 1.0),
        (delta.dy / maxDist).clamp(-1.0, 1.0),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // 放開手指後眼睛緩慢回正
    setState(() {
      _lookTarget = Offset.zero;
    });
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    _squishController.forward(from: 0.0);
    _jumpController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  Color get _themeColor {
    if (widget.mood == ProceduralMood.celebratingGoal) return const Color(0xFFF59E0B);
    if (widget.mood == ProceduralMood.chewing) return const Color(0xFF10B981);
    if (widget.mood == ProceduralMood.superHappy) return const Color(0xFFEC4899);
    if (widget.mood == ProceduralMood.sleeping) return const Color(0xFF8B5CF6);
    return const Color(0xFF59B294);
  }

  @override
  Widget build(BuildContext context) {
    final double actorSize = widget.size;

    return DragTarget<PetFoodItem>(
      onWillAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = true;
          _lookTarget = const Offset(0.4, -0.6); // 抬頭注視拖曳食物
        });
        HapticFeedback.selectionClick();
        return true;
      },
      onLeave: (data) {
        setState(() {
          _isDragHovering = false;
          _lookTarget = Offset.zero;
        });
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = false;
          _lookTarget = Offset.zero;
        });
        widget.onFoodAccepted?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. 大字氣泡對話框 ──
            if (widget.speechText.isNotEmpty)
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _themeColor.withValues(alpha: 0.35),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _themeColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _themeColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        widget.mood == ProceduralMood.celebratingGoal ? '👑' : '💬',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.speechText,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── 2. 向量骨骼主角繪製區 ──
            GestureDetector(
              onTap: _handleTap,
              onPanUpdate: (d) => _onPanUpdate(d, Size(actorSize, actorSize)),
              onPanEnd: _onPanEnd,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _breatheController,
                  _blinkController,
                  _earTwitchController,
                  _chewController,
                  _jumpController,
                  _squishController,
                  _tailWagController,
                ]),
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(actorSize * 1.35, actorSize * 1.35),
                    painter: _ProceduralPigletPainter(
                      mood: widget.mood,
                      breatheValue: _breatheController.value,
                      blinkValue: _blinkController.value,
                      earTwitchValue: _earTwitchController.value,
                      chewValue: _chewController.value,
                      jumpValue: _jumpController.value,
                      squishValue: _squishController.value,
                      tailWagValue: _tailWagController.value,
                      lookTarget: _lookTarget,
                      isDragHovering: _isDragHovering,
                      isCrownUnlocked: widget.isCrownUnlocked,
                      themeColor: _themeColor,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 🎨 純 Flutter 向量骨骼繪製引擎 (Procedural Vector Skeletal Painter)
// ══════════════════════════════════════════════════════════════════════
class _ProceduralPigletPainter extends CustomPainter {
  final ProceduralMood mood;
  final double breatheValue;
  final double blinkValue;
  final double earTwitchValue;
  final double chewValue;
  final double jumpValue;
  final double squishValue;
  final double tailWagValue;
  final Offset lookTarget;
  final bool isDragHovering;
  final bool isCrownUnlocked;
  final Color themeColor;

  _ProceduralPigletPainter({
    required this.mood,
    required this.breatheValue,
    required this.blinkValue,
    required this.earTwitchValue,
    required this.chewValue,
    required this.jumpValue,
    required this.squishValue,
    required this.tailWagValue,
    required this.lookTarget,
    required this.isDragHovering,
    required this.isCrownUnlocked,
    required this.themeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    // ── 物理參數計算 ──
    final double jumpY = -math.sin(jumpValue * math.pi) * 38.0;
    final double shadowFactor = 1.0 - (math.sin(jumpValue * math.pi) * 0.5);
    final double breatheScaleY = 1.0 + (breatheValue * 0.028);
    final double breatheScaleX = 1.0 - (breatheValue * 0.016);

    // Q 彈壓扁形變
    final double squishScaleX = 1.0 + (math.sin(squishValue * math.pi) * 0.14);
    final double squishScaleY = 1.0 - (math.sin(squishValue * math.pi) * 0.14);

    // 咀嚼形變
    final double chewScaleX = 1.0 + (chewValue * 0.07);
    final double chewScaleY = 1.0 - (chewValue * 0.05);

    // ─────────────────────────────────────────────
    // 1. 地面接觸陰影 (Dynamic Soft Ambient Shadow)
    // ─────────────────────────────────────────────
    final Paint shadowPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.18 * shadowFactor)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 + (math.sin(jumpValue * math.pi) * 16.0));

    final Rect shadowRect = Rect.fromCenter(
      center: Offset(cx, cy + (size.height * 0.36)),
      width: (size.width * 0.58) * shadowFactor,
      height: (size.height * 0.14) * shadowFactor,
    );
    canvas.drawOval(shadowRect, shadowPaint);

    // ─────────────────────────────────────────────
    // 2. 居室編織軟地毯 (Cozy Rug)
    // ─────────────────────────────────────────────
    final Paint rugBgPaint = Paint()
      ..color = const Color(0xFFF8FAF5)
      ..style = PaintingStyle.fill;
    final Paint rugBorderPaint = Paint()
      ..color = isDragHovering ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDragHovering ? 3.0 : 1.5;

    final Rect rugRect = Rect.fromCenter(
      center: Offset(cx, cy + (size.height * 0.35)),
      width: size.width * 0.88,
      height: size.height * 0.32,
    );
    canvas.drawOval(rugRect, rugBgPaint);
    canvas.drawOval(rugRect, rugBorderPaint);

    // ─────────────────────────────────────────────
    // 3. 小豬本體座標系 (Piglet Skeletal Node)
    // ─────────────────────────────────────────────
    canvas.save();
    // 移動到小豬基準點（底部腳部中心）
    canvas.translate(cx, cy + (size.height * 0.32) + jumpY);
    canvas.scale(
      breatheScaleX * squishScaleX * chewScaleX * (isDragHovering ? 1.05 : 1.0),
      breatheScaleY * squishScaleY * chewScaleY * (isDragHovering ? 1.05 : 1.0),
    );

    // ─────────────────────────────────────────────
    // A. 捲捲小尾巴 (Curled Spring Tail)
    // ─────────────────────────────────────────────
    final Paint tailPaint = Paint()
      ..color = const Color(0xFFF48FB1)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    final double tailWiggle = math.sin(tailWagValue * math.pi * 2) * 8.0;
    final Path tailPath = Path();
    tailPath.moveTo(65, -30);
    tailPath.cubicTo(85 + tailWiggle, -35, 95 + tailWiggle, -55, 80 + tailWiggle, -60);
    tailPath.cubicTo(70 + tailWiggle, -65, 65 + tailWiggle, -45, 85 + tailWiggle, -45);
    canvas.drawPath(tailPath, tailPaint);

    // ─────────────────────────────────────────────
    // B. 小豬麻糬圓圓身體 (Chubby Mochi Body)
    // ─────────────────────────────────────────────
    final Paint bodyPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.2),
        radius: 0.85,
        colors: [
          Color(0xFFFFE4E6), // 亮粉白
          Color(0xFFFECDD3), // 嫩粉紅
          Color(0xFFFDA4AF), // 陰影漸層粉
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, -60), radius: 85));

    final Paint bodyBorderPaint = Paint()
      ..color = const Color(0xFFF472B6).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // 繪製水滴流線形麻糬身軀 (Bézier Body Outline)
    final Path bodyPath = Path();
    bodyPath.moveTo(-60, 0);
    // 左側腹部曲線
    bodyPath.cubicTo(-80, -30, -75, -80, -55, -110);
    // 頭部上方圓弧
    bodyPath.cubicTo(-35, -135, 35, -135, 55, -110);
    // 右側腹部曲線
    bodyPath.cubicTo(75, -80, 80, -30, 60, 0);
    // 底部接地曲線
    bodyPath.cubicTo(40, 10, -40, 10, -60, 0);
    bodyPath.close();

    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, bodyBorderPaint);

    // ─────────────────────────────────────────────
    // C. 肚子溫暖漸層軟毛 (Cozy Belly Patch)
    // ─────────────────────────────────────────────
    final Paint bellyPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, -30), radius: 45));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -30), width: 70, height: 50),
      bellyPaint,
    );

    // ─────────────────────────────────────────────
    // D. 圓滾滾小短腿與小蹄子 (Little Hooves)
    // ─────────────────────────────────────────────
    final Paint hoofPaint = Paint()
      ..color = const Color(0xFFFB7185)
      ..style = PaintingStyle.fill;

    // 左腳、右腳
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-32, 2), width: 22, height: 16),
        const Radius.circular(8),
      ),
      hoofPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(32, 2), width: 22, height: 16),
        const Radius.circular(8),
      ),
      hoofPaint,
    );

    // ─────────────────────────────────────────────
    // E. 兩隻靈動小耳朵 (Dynamic Expressive Ears)
    // ─────────────────────────────────────────────
    final double earWiggle = math.sin(earTwitchValue * math.pi * 3) * 6.0;
    final double droopAngle = (mood == ProceduralMood.sleeping) ? 0.25 : 0.0;

    // 左耳
    canvas.save();
    canvas.translate(-48, -108);
    canvas.rotate(-0.25 + droopAngle + (earWiggle * 0.02));
    final Path leftEar = Path()
      ..moveTo(0, 0)
      ..cubicTo(-25, -15, -30, 20, -8, 26)
      ..close();
    canvas.drawPath(leftEar, Paint()..color = const Color(0xFFFDA4AF));
    canvas.drawPath(
      leftEar,
      Paint()
        ..color = const Color(0xFFF43F5E).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // 耳內粉色內襯
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-12, 8), width: 14, height: 18),
      Paint()..color = const Color(0xFFFB7185).withValues(alpha: 0.65),
    );
    canvas.restore();

    // 右耳
    canvas.save();
    canvas.translate(48, -108);
    canvas.rotate(0.25 - droopAngle - (earWiggle * 0.02));
    final Path rightEar = Path()
      ..moveTo(0, 0)
      ..cubicTo(25, -15, 30, 20, 8, 26)
      ..close();
    canvas.drawPath(rightEar, Paint()..color = const Color(0xFFFDA4AF));
    canvas.drawPath(
      rightEar,
      Paint()
        ..color = const Color(0xFFF43F5E).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(12, 8), width: 14, height: 18),
      Paint()..color = const Color(0xFFFB7185).withValues(alpha: 0.65),
    );
    canvas.restore();

    // ─────────────────────────────────────────────
    // F. 軟萌粉嫩小豬鼻 (Cute Pig Snout)
    // ─────────────────────────────────────────────
    final double snoutY = -62.0;
    final Paint snoutPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDA4AF), Color(0xFFFB7185)],
      ).createShader(Rect.fromCenter(center: Offset(0, snoutY), width: 44, height: 32));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, snoutY), width: 44, height: 32),
        const Radius.circular(16),
      ),
      snoutPaint,
    );

    // 豬鼻高光
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-6, snoutY - 6), width: 14, height: 6),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );

    // 兩個圓圓小鼻孔 (Nostrils)
    final Paint nostrilPaint = Paint()..color = const Color(0xFFBE123C);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-9, snoutY + 2), width: 7, height: 10),
      nostrilPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(9, snoutY + 2), width: 7, height: 10),
      nostrilPaint,
    );

    // ─────────────────────────────────────────────
    // G. 兩側粉紅腮紅 (Rosy Blushing Cheeks)
    // ─────────────────────────────────────────────
    final Paint blushPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFB7185), Color(0x00FB7185)],
      ).createShader(Rect.fromCircle(center: const Offset(-45, -60), radius: 18));
    canvas.drawCircle(const Offset(-46, -60), 16, blushPaint);

    final Paint rightBlushPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFB7185), Color(0x00FB7185)],
      ).createShader(Rect.fromCircle(center: const Offset(45, -60), radius: 18));
    canvas.drawCircle(const Offset(46, -60), 16, rightBlushPaint);

    // ─────────────────────────────────────────────
    // H. 靈動大眼睛（即時視線追蹤 + 自然眨眼 + 開心瞇瞇眼）
    // ─────────────────────────────────────────────
    final double eyeLookX = lookTarget.dx * 3.5;
    final double eyeLookY = lookTarget.dy * 3.5;

    if (mood == ProceduralMood.sleeping) {
      // 閉眼睡覺弧線 (Sleeping Curves)
      final Paint sleepEyePaint = Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5;

      final Path leftSleep = Path()
        ..moveTo(-38, -82)
        ..quadraticBezierTo(-30, -74, -22, -82);
      final Path rightSleep = Path()
        ..moveTo(22, -82)
        ..quadraticBezierTo(30, -74, 38, -82);
      canvas.drawPath(leftSleep, sleepEyePaint);
      canvas.drawPath(rightSleep, sleepEyePaint);
    } else if (mood == ProceduralMood.superHappy ||
        mood == ProceduralMood.celebratingGoal ||
        chewValue > 0.4) {
      // 幸福開懷瞇瞇眼 (Happy Arcs ^^)
      final Paint happyEyePaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.0;

      final Path leftHappy = Path()
        ..moveTo(-38, -80)
        ..quadraticBezierTo(-30, -90, -22, -80);
      final Path rightHappy = Path()
        ..moveTo(22, -80)
        ..quadraticBezierTo(30, -90, 38, -80);
      canvas.drawPath(leftHappy, happyEyePaint);
      canvas.drawPath(rightHappy, happyEyePaint);
    } else {
      // 靈動黑曜石大眼珠（附雙高光 + 眨眼內插）
      final double eyeOpenRatio = (1.0 - blinkValue).clamp(0.08, 1.0);
      final double eyeRadiusX = 8.5;
      final double eyeRadiusY = 11.0 * eyeOpenRatio;

      final Paint eyeWhite = Paint()..color = const Color(0xFF1E293B);

      // 左眼
      final Offset leftEyeCenter = Offset(-30 + eyeLookX, -82 + eyeLookY);
      canvas.drawOval(
        Rect.fromCenter(center: leftEyeCenter, width: eyeRadiusX * 2, height: eyeRadiusY * 2),
        eyeWhite,
      );
      if (eyeOpenRatio > 0.4) {
        // 主高光
        canvas.drawCircle(Offset(leftEyeCenter.dx - 2.5, leftEyeCenter.dy - 3), 3.2, Paint()..color = Colors.white);
        // 副高光
        canvas.drawCircle(Offset(leftEyeCenter.dx + 2.5, leftEyeCenter.dy + 2.5), 1.6, Paint()..color = Colors.white);
      }

      // 右眼
      final Offset rightEyeCenter = Offset(30 + eyeLookX, -82 + eyeLookY);
      canvas.drawOval(
        Rect.fromCenter(center: rightEyeCenter, width: eyeRadiusX * 2, height: eyeRadiusY * 2),
        eyeWhite,
      );
      if (eyeOpenRatio > 0.4) {
        // 主高光
        canvas.drawCircle(Offset(rightEyeCenter.dx - 2.5, rightEyeCenter.dy - 3), 3.2, Paint()..color = Colors.white);
        // 副高光
        canvas.drawCircle(Offset(rightEyeCenter.dx + 2.5, rightEyeCenter.dy + 2.5), 1.6, Paint()..color = Colors.white);
      }
    }

    // ─────────────────────────────────────────────
    // I. 靈活嘴巴（張大嘴等吃 / 微微微笑 / 嚼嚼）
    // ─────────────────────────────────────────────
    if (isDragHovering || mood == ProceduralMood.anticipating) {
      // 張大嘴巴 (Wide Open Mouth waiting for food)
      final Paint mouthInside = Paint()..color = const Color(0xFFBE123C);
      final Path openMouth = Path()
        ..moveTo(-12, -42)
        ..quadraticBezierTo(0, -46, 12, -42)
        ..quadraticBezierTo(0, -22, -12, -42);
      canvas.drawPath(openMouth, mouthInside);

      // 小舌頭
      final Paint tonguePaint = Paint()..color = const Color(0xFFFDA4AF);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -28), width: 14, height: 10),
        tonguePaint,
      );
    } else if (mood == ProceduralMood.chewing) {
      // 咀嚼中嘴巴微動
      final Paint chewMouth = Paint()
        ..color = const Color(0xFF881337)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.0;
      final Path chewPath = Path()
        ..moveTo(-8, -42)
        ..quadraticBezierTo(0, -40 + (chewValue * 6), 8, -42);
      canvas.drawPath(chewPath, chewMouth);
    } else {
      // 溫柔微笑曲線 (Gentle Smile)
      final Paint smilePaint = Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.0;
      final Path smilePath = Path()
        ..moveTo(-8, -42)
        ..quadraticBezierTo(0, -36, 8, -42);
      canvas.drawPath(smilePath, smilePaint);
    }

    // ─────────────────────────────────────────────
    // J. 招牌小橡實帽子 / 8000步金色皇冠 (Acorn Hat / Crown)
    // ─────────────────────────────────────────────
    if (isCrownUnlocked || mood == ProceduralMood.celebratingGoal) {
      // 👑 達標金色皇冠
      final Paint crownPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
        ).createShader(Rect.fromCenter(center: const Offset(0, -145), width: 50, height: 35));

      final Path crownPath = Path()
        ..moveTo(-22, -135)
        ..lineTo(-26, -155)
        ..lineTo(-12, -144)
        ..lineTo(0, -162)
        ..lineTo(12, -144)
        ..lineTo(26, -155)
        ..lineTo(22, -135)
        ..close();
      canvas.drawPath(crownPath, crownPaint);
    } else {
      // 🌰 軟萌編織橡實帽 (Knitted Acorn Cap)
      final Paint acornNut = Paint()..color = const Color(0xFF8D5B4C);
      final Paint acornCap = Paint()..color = const Color(0xFF5C3A21);

      // 帽頂小樹枝 (Stem)
      final Paint stemPaint = Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.0;
      final Path stemPath = Path()
        ..moveTo(0, -146)
        ..quadraticBezierTo(4, -158, 8, -160);
      canvas.drawPath(stemPath, stemPaint);

      // 橡實頂蓋 (Knitted Cap)
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -136), width: 48, height: 26),
        acornCap,
      );
      // 編織網格紋理
      final Paint texturePaint = Paint()
        ..color = const Color(0xFF3E2723).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (double i = -16; i <= 16; i += 8) {
        canvas.drawLine(Offset(i, -146), Offset(i + 4, -126), texturePaint);
        canvas.drawLine(Offset(i + 4, -146), Offset(i, -126), texturePaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProceduralPigletPainter oldDelegate) {
    return true;
  }
}
