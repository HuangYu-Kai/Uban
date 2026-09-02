import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';
import 'animated_piglet_actor.dart';

class Style4SkeletalActor extends StatefulWidget {
  final ActorMood mood;
  final Function(PetFoodItem food)? onFoodAccepted;
  final VoidCallback? onPetHead;
  final VoidCallback? onPokeBelly;
  final double size;
  final String speechText;
  final bool isCrownUnlocked;

  const Style4SkeletalActor({
    super.key,
    this.mood = ActorMood.idle,
    this.onFoodAccepted,
    this.onPetHead,
    this.onPokeBelly,
    this.size = 310,
    this.speechText = '',
    this.isCrownUnlocked = false,
  });

  @override
  State<Style4SkeletalActor> createState() => _Style4SkeletalActorState();
}

class _Style4SkeletalActorState extends State<Style4SkeletalActor>
    with TickerProviderStateMixin {
  // ── 骨骼與物理動畫控制器 ──
  late AnimationController _breatheController;
  late AnimationController _blinkController;
  late AnimationController _chewController;
  late AnimationController _jumpController;
  late AnimationController _squishController;
  late AnimationController _wiggleController;
  late AnimationController _floatController;

  Timer? _blinkTimer;
  Offset _lookTarget = Offset.zero; // 眼睛追蹤手指與食物 (-1.0 ~ 1.0)
  bool _isDragHovering = false;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // 1. 溫柔呼吸起伏 (2.4s 有機循環)
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 2. 懸浮微動效 (有機微浮動)
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    // 3. 自律眨眼 (Autonomic Blinking)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scheduleNextBlink();

    // 4. 咀嚼動態
    _chewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // 5. 開心跳躍 (Joyful Jump)
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    // 6. 觸摸果凍 Q 彈壓扁物理回彈 (Elastic Squish & Stretch)
    _squishController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    // 7. 戳肚子搖擺 (Wiggle)
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final delayMs = 2800 + _random.nextInt(3200);
    _blinkTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted && widget.mood != ActorMood.sleeping && widget.mood != ActorMood.superHappy) {
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

  @override
  void didUpdateWidget(covariant Style4SkeletalActor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.mood != oldWidget.mood) {
      if (widget.mood == ActorMood.chewing) {
        _chewController.repeat(reverse: true);
        Timer(const Duration(milliseconds: 1800), () {
          if (mounted && widget.mood != ActorMood.chewing) {
            _chewController.stop();
          }
        });
      } else {
        _chewController.stop();
      }

      if (widget.mood == ActorMood.superHappy ||
          widget.mood == ActorMood.celebratingGoal) {
        _jumpController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _breatheController.dispose();
    _floatController.dispose();
    _blinkController.dispose();
    _chewController.dispose();
    _jumpController.dispose();
    _squishController.dispose();
    _wiggleController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
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
    setState(() {
      _lookTarget = Offset.zero;
    });
  }

  void _triggerPetInteraction() {
    HapticFeedback.mediumImpact();
    _squishController.forward(from: 0.0);
    _jumpController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  void _triggerBellyPoke() {
    HapticFeedback.mediumImpact();
    _wiggleController.forward(from: 0.0);
    _squishController.forward(from: 0.0);
    widget.onPokeBelly?.call();
  }

  String get _currentAsset {
    if (widget.mood == ActorMood.sleeping) {
      return 'assets/images/sumikko_sleep.png';
    }
    if (widget.mood == ActorMood.chewing) {
      return 'assets/images/sumikko_eating.png';
    }
    if (widget.mood == ActorMood.superHappy || widget.mood == ActorMood.celebratingGoal) {
      return 'assets/images/sumikko_happy.png';
    }
    if (_isDragHovering || widget.mood == ActorMood.anticipating) {
      return 'assets/images/sumikko_mouth_open.png';
    }
    return 'assets/images/sumikko_idle.png';
  }

  Color get _themeColor {
    if (widget.mood == ActorMood.celebratingGoal) return const Color(0xFFF59E0B);
    if (widget.mood == ActorMood.chewing) return const Color(0xFF10B981);
    if (widget.mood == ActorMood.superHappy) return const Color(0xFFEC4899);
    if (widget.mood == ActorMood.sleeping) return const Color(0xFF8B5CF6);
    return const Color(0xFF59B294);
  }

  @override
  Widget build(BuildContext context) {
    final double actorSize = widget.size;
    final double stageWidth = actorSize * 1.35;
    final double stageHeight = actorSize * 1.35;

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
            // ── 1. 溫馨繪本對話氣泡 ──
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
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                        widget.mood == ActorMood.celebratingGoal ? '👑' : '💬',
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

            // ── 2. 風格 4 ✕ 方案 A 融合骨骼舞台 ──
            GestureDetector(
              onTap: _triggerPetInteraction,
              onLongPress: _triggerBellyPoke,
              onPanUpdate: (d) => _onPanUpdate(d, Size(stageWidth, stageHeight)),
              onPanEnd: _onPanEnd,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _breatheController,
                  _floatController,
                  _blinkController,
                  _chewController,
                  _jumpController,
                  _squishController,
                  _wiggleController,
                ]),
                builder: (context, child) {
                  // 呼吸縮放 (Natural breathing scale)
                  final double breatheScaleY = 1.0 + (_breatheController.value * 0.025);
                  final double breatheScaleX = 1.0 - (_breatheController.value * 0.015);

                  // 咀嚼物理形變 (Chewing squash & stretch)
                  final double chewSquashX = 1.0 + (_chewController.value * 0.06);
                  final double chewSquashY = 1.0 - (_chewController.value * 0.05);

                  // 觸摸彈性壓扁形變 (Jelly spring squish)
                  final double petSquishX = 1.0 + (math.sin(_squishController.value * math.pi) * 0.12);
                  final double petSquishY = 1.0 - (math.sin(_squishController.value * math.pi) * 0.12);

                  // 戳肚子擺動
                  final double wiggleAngle = math.sin(_wiggleController.value * math.pi * 3) * 0.06;

                  // 跳躍高度與微浮動
                  final double jumpProgress = _jumpController.value;
                  final double jumpY = -math.sin(jumpProgress * math.pi) * 36.0;
                  final double floatY = math.sin(_floatController.value * math.pi * 2) * 2.5;

                  // 擬真地面陰影物理
                  final double shadowFactor = 1.0 - (math.sin(jumpProgress * math.pi) * 0.45);
                  final double shadowBlur = 12.0 + (math.sin(jumpProgress * math.pi) * 16.0);
                  final double shadowOpacity = (0.22 * shadowFactor).clamp(0.05, 0.28);

                  return SizedBox(
                    width: stageWidth,
                    height: stageHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // A. 溫馨編織軟毛地毯
                        Positioned(
                          bottom: 20,
                          child: Container(
                            width: actorSize * 1.18,
                            height: actorSize * 0.48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAF5),
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(actorSize * 1.18, actorSize * 0.48),
                              ),
                              border: Border.all(
                                color: _isDragHovering
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFFE2E8F0),
                                width: _isDragHovering ? 3.0 : 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _themeColor.withValues(alpha: _isDragHovering ? 0.25 : 0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: actorSize * 0.95,
                                height: actorSize * 0.36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.elliptical(actorSize * 0.95, actorSize * 0.36),
                                  ),
                                  border: Border.all(
                                    color: _themeColor.withValues(alpha: 0.15),
                                    style: BorderStyle.solid,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // B. 擬真地面接觸投影 (Dynamic Ground Contact Shadow)
                        Positioned(
                          bottom: 32,
                          child: Container(
                            width: (actorSize * 0.68) * shadowFactor,
                            height: (actorSize * 0.18) * shadowFactor,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(
                                  (actorSize * 0.68) * shadowFactor,
                                  (actorSize * 0.18) * shadowFactor,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF334155).withValues(alpha: shadowOpacity),
                                  blurRadius: shadowBlur,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // C. 風格 4 手繪小豬本體 ＋ 骨骼動態層疊
                        Positioned(
                          bottom: 28,
                          child: Transform.translate(
                            offset: Offset(0, jumpY + floatY),
                            child: Transform.rotate(
                              angle: wiggleAngle,
                              child: Transform.scale(
                                scaleX: breatheScaleX * chewSquashX * petSquishX * (_isDragHovering ? 1.06 : 1.0),
                                scaleY: breatheScaleY * chewSquashY * petSquishY * (_isDragHovering ? 1.06 : 1.0),
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: actorSize,
                                  height: actorSize,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      // 1. 風格 4 絲滑手繪本體 (Smooth Cross-fade Sprite)
                                      AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(begin: 0.94, end: 1.0).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Image.asset(
                                          _currentAsset,
                                          key: ValueKey<String>(_currentAsset),
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),

                                      // 2. 方案 A 實時眼球注視追蹤與眨眼骨骼層 (Live Eye Tracking & Blinking Rig)
                                      if (widget.mood == ActorMood.idle || _isDragHovering)
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _Style4EyeRigPainter(
                                              lookTarget: _lookTarget,
                                              blinkValue: _blinkController.value,
                                              isHovering: _isDragHovering,
                                            ),
                                          ),
                                        ),

                                      // 3. 👑 達標金色榮譽皇冠
                                      if (widget.isCrownUnlocked || widget.mood == ActorMood.celebratingGoal)
                                        Positioned(
                                          top: -16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
                                              ),
                                              borderRadius: BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text('👑', style: TextStyle(fontSize: 15)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '8000步榮耀',
                                                  style: GoogleFonts.notoSansTc(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
// 👁️ 風格 4 專屬手繪眼球骨骼繪製器 (Style 4 Realistic Eye Rig Painter)
// ══════════════════════════════════════════════════════════════════════
class _Style4EyeRigPainter extends CustomPainter {
  final Offset lookTarget;
  final double blinkValue;
  final bool isHovering;

  _Style4EyeRigPainter({
    required this.lookTarget,
    required this.blinkValue,
    required this.isHovering,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 依據 sumikko_idle.png 臉部五官比例定位
    // 左眼座標: (0.395 * w, 0.480 * h)
    // 右眼座標: (0.540 * w, 0.466 * h)
    final double w = size.width;
    final double h = size.height;

    final Offset leftEyeCenter = Offset(w * 0.395, h * 0.480);
    final Offset rightEyeCenter = Offset(w * 0.540, h * 0.466);

    final double eyeLookX = lookTarget.dx * (w * 0.008);
    final double eyeLookY = lookTarget.dy * (h * 0.008);

    final double eyeRadius = w * 0.024;
    final double blinkScaleY = (1.0 - blinkValue).clamp(0.05, 1.0);

    // 1. 溫柔眼眶底色（平滑融合色鉛筆底色）
    final Paint socketPaint = Paint()
      ..color = const Color(0xFFFDE2E4)
      ..style = PaintingStyle.fill;

    // 2. 眨眼遮罩與眼球
    if (blinkValue > 0.1) {
      // 眨眼時繪製自然手繪肉粉色眼皮覆蓋
      final Paint lidPaint = Paint()
        ..color = const Color(0xFFF9CBD2)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(center: leftEyeCenter, width: eyeRadius * 2.3, height: eyeRadius * 2.3 * blinkValue),
        lidPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: rightEyeCenter, width: eyeRadius * 2.3, height: eyeRadius * 2.3 * blinkValue),
        lidPaint,
      );
      return;
    }

    // 3. 靈動黑曜石大眼珠（隨視線移動）
    final Paint pupilPaint = Paint()..color = const Color(0xFF2C2424);

    // 左眼眼球
    final Offset dynamicLeft = Offset(leftEyeCenter.dx + eyeLookX, leftEyeCenter.dy + eyeLookY);
    canvas.drawOval(
      Rect.fromCenter(center: dynamicLeft, width: eyeRadius * 2.0, height: eyeRadius * 2.1 * blinkScaleY),
      pupilPaint,
    );

    // 右眼眼球
    final Offset dynamicRight = Offset(rightEyeCenter.dx + eyeLookX, rightEyeCenter.dy + eyeLookY);
    canvas.drawOval(
      Rect.fromCenter(center: dynamicRight, width: eyeRadius * 2.0, height: eyeRadius * 2.1 * blinkScaleY),
      pupilPaint,
    );

    // 4. 水汪汪雙高光點（Specular Highlights）
    final Paint sparkPaint = Paint()..color = Colors.white;
    // 左眼高光
    canvas.drawCircle(Offset(dynamicLeft.dx - (eyeRadius * 0.35), dynamicLeft.dy - (eyeRadius * 0.35)), eyeRadius * 0.38, sparkPaint);
    canvas.drawCircle(Offset(dynamicLeft.dx + (eyeRadius * 0.35), dynamicLeft.dy + (eyeRadius * 0.35)), eyeRadius * 0.18, sparkPaint);
    // 右眼高光
    canvas.drawCircle(Offset(dynamicRight.dx - (eyeRadius * 0.35), dynamicRight.dy - (eyeRadius * 0.35)), eyeRadius * 0.38, sparkPaint);
    canvas.drawCircle(Offset(dynamicRight.dx + (eyeRadius * 0.35), dynamicRight.dy + (eyeRadius * 0.35)), eyeRadius * 0.18, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _Style4EyeRigPainter oldDelegate) {
    return oldDelegate.lookTarget != lookTarget ||
        oldDelegate.blinkValue != blinkValue ||
        oldDelegate.isHovering != isHovering;
  }
}
