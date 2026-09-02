import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';
import '../models/pet_growth_state.dart';
import 'animated_piglet_actor.dart';

/// 🐷 手繪油畫正面小豬角色組件（繪本微動態 ✕ 溫暖手作美學）
class HandDrawnPigletActor extends StatefulWidget {
  final ActorMood mood;
  final PetGrowthStage stage;
  final Function(PetFoodItem food)? onFoodAccepted;
  final VoidCallback? onPetHead;
  final VoidCallback? onPokeBelly;
  final double size;
  final String speechText;
  final bool isCrownUnlocked;

  const HandDrawnPigletActor({
    super.key,
    this.mood = ActorMood.idle,
    this.stage = PetGrowthStage.miniMochi,
    this.onFoodAccepted,
    this.onPetHead,
    this.onPokeBelly,
    this.size = 320,
    this.speechText = '',
    this.isCrownUnlocked = false,
  });

  @override
  State<HandDrawnPigletActor> createState() => _HandDrawnPigletActorState();
}

class _HandDrawnPigletActorState extends State<HandDrawnPigletActor>
    with TickerProviderStateMixin {
  // 自然呼吸控制器 (3.2秒平滑循環)
  late AnimationController _breatheController;
  // 進食歡喜微動態 (600ms 平滑微點頭)
  late AnimationController _eatController;
  // 撫摸彈性回饋控制器 (480ms 彈簧曲線)
  late AnimationController _springTouchController;
  // 達標慶祝跳躍控制器 (800ms)
  late AnimationController _celebrateController;
  // 祥瑞神獸光暈控制器 (6.0秒舒緩旋轉)
  late AnimationController _auraController;

  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _eatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _springTouchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _celebrateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _syncMood();
  }

  void _onFrameTick() {}

  @override
  void reassemble() {
    super.reassemble();
    _syncMood();
  }

  @override
  void didUpdateWidget(covariant HandDrawnPigletActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood != oldWidget.mood) {
      _syncMood();
    }
  }

  void _syncMood() {
    if (widget.mood == ActorMood.chewing) {
      _eatController.repeat();
    } else {
      _eatController.stop();
      _eatController.reset();
    }

    if (widget.mood == ActorMood.superHappy ||
        widget.mood == ActorMood.celebratingGoal) {
      _celebrateController.repeat();
    } else {
      _celebrateController.stop();
      _celebrateController.reset();
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _eatController.dispose();
    _springTouchController.dispose();
    _celebrateController.dispose();
    _auraController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _springTouchController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    _springTouchController.forward(from: 0.0);
    widget.onPokeBelly?.call();
  }

  Color get _themeColor {
    if (widget.mood == ActorMood.celebratingGoal) return const Color(0xFFD97706);
    if (widget.mood == ActorMood.chewing) return const Color(0xFF059669);
    if (widget.mood == ActorMood.superHappy) return const Color(0xFFDB2777);
    if (widget.mood == ActorMood.sleeping) return const Color(0xFF7C3AED);
    return const Color(0xFFB45309);
  }

  @override
  Widget build(BuildContext context) {
    final double actorSize = widget.size;
    final double stageWidth = actorSize * 1.32;
    final double stageHeight = actorSize * 1.32;
    final stage = widget.stage;

    return DragTarget<PetFoodItem>(
      onWillAcceptWithDetails: (details) {
        setState(() => _isDragHovering = true);
        HapticFeedback.selectionClick();
        return true;
      },
      onLeave: (data) {
        setState(() => _isDragHovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isDragHovering = false);
        widget.onFoodAccepted?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final stageWidget = GestureDetector(
          onTap: _handleTap,
          onLongPress: _handleLongPress,
          child: SizedBox(
            width: stageWidth,
            height: stageHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── A. 手作天然棉麻編織地墊（溫暖繪本感）──
                Positioned(
                  bottom: 14,
                  child: Container(
                    width: actorSize * 1.16,
                    height: actorSize * 0.44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F0),
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(actorSize * 1.16, actorSize * 0.44),
                      ),
                      border: Border.all(
                        color: _isDragHovering
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFEADBCE),
                        width: _isDragHovering ? 2.8 : 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF78350F).withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: actorSize * 0.94,
                        height: actorSize * 0.32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(actorSize * 0.94, actorSize * 0.32),
                          ),
                          border: Border.all(
                            color: const Color(0xFFE8DCCA),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── B. 柔和貼地接觸陰影（隨動作自然呼吸放縮）──
                Positioned(
                  bottom: 26,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _breatheController,
                      _celebrateController,
                      _springTouchController,
                    ]),
                    builder: (context, child) {
                      double jumpFactor = 0.0;
                      if (widget.mood == ActorMood.superHappy ||
                          widget.mood == ActorMood.celebratingGoal) {
                        jumpFactor = math.sin(_celebrateController.value * math.pi);
                      }
                      if (_springTouchController.isAnimating) {
                        jumpFactor += (1.0 - _springTouchController.value) * 0.2;
                      }

                      final double shadowScale = (1.0 - jumpFactor * 0.3).clamp(0.65, 1.1);
                      final double shadowOpacity = (0.20 - jumpFactor * 0.10).clamp(0.06, 0.22);

                      return Container(
                        width: (actorSize * 0.66) * shadowScale,
                        height: (actorSize * 0.16) * shadowScale,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(
                              (actorSize * 0.66) * shadowScale,
                              (actorSize * 0.16) * shadowScale,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4A3E3D).withValues(alpha: shadowOpacity),
                              blurRadius: 10 + jumpFactor * 12,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── C. 祥瑞金光光暈（僅在神獸階段或達標慶祝時舒緩飄散）──
                if (stage == PetGrowthStage.goldenFortunePig ||
                    widget.mood == ActorMood.celebratingGoal)
                  Positioned(
                    bottom: 28,
                    child: AnimatedBuilder(
                      animation: _auraController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _auraController.value * 2 * math.pi,
                          child: Container(
                            width: actorSize * 1.15,
                            height: actorSize * 1.15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFFFDE68A).withValues(alpha: 0.38),
                                  const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                                stops: const [0.25, 0.65, 1.0],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // ── D. 核心油畫手繪小豬本體（自然繪本微動態）──
                Positioned(
                  bottom: 22,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _breatheController,
                      _eatController,
                      _celebrateController,
                      _springTouchController,
                    ]),
                    builder: (context, child) {
                      // 1. 自然平滑呼吸（使用底端為錨點，肚肚微幅舒緩起伏）
                      final double breathPhase = _breatheController.value * 2 * math.pi;
                      final double breathSine = math.sin(breathPhase);
                      
                      double translateY = breathSine * -2.2;
                      double scaleY = 1.0 + breathSine * 0.012;
                      double scaleX = 1.0 - breathSine * 0.008;
                      double rotation = 0.0;

                      // 2. 吃東西時的歡喜微點頭
                      if (widget.mood == ActorMood.chewing) {
                        final double eatPhase = _eatController.value * 2 * math.pi;
                        final double eatSine = math.sin(eatPhase);
                        translateY += eatSine * -3.0;
                        rotation += math.sin(eatPhase) * 0.02;
                      }

                      // 3. 達標與超級開心時的輕快小跳躍
                      if (widget.mood == ActorMood.superHappy ||
                          widget.mood == ActorMood.celebratingGoal) {
                        final double hopPhase = _celebrateController.value * math.pi;
                        final double hopSine = math.sin(hopPhase);
                        translateY -= hopSine * 14.0;
                        rotation += math.sin(_celebrateController.value * 2 * math.pi) * 0.04;
                      }

                      // 4. 期待投餵時的微往前傾
                      if (_isDragHovering || widget.mood == ActorMood.anticipating) {
                        translateY -= 4.0;
                        scaleY *= 1.03;
                        scaleX *= 1.03;
                      }

                      // 5. 睡眠時的放鬆微傾與深沉呼吸
                      if (widget.mood == ActorMood.sleeping) {
                        rotation = -0.05;
                        translateY += 3.0;
                        scaleY = 0.98 + breathSine * 0.015;
                      }

                      // 6. 點擊摸摸時的柔軟彈性反饋
                      if (_springTouchController.isAnimating) {
                        final double touchVal = math.sin(_springTouchController.value * math.pi);
                        translateY += touchVal * 3.5;
                        scaleY -= touchVal * 0.03;
                        scaleX += touchVal * 0.03;
                      }

                      return Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..translate(0.0, translateY)
                          ..rotateZ(rotation)
                          ..scale(scaleX, scaleY),
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: actorSize,
                      height: actorSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // 🐷 正面油畫手繪小豬（保留原汁原味筆觸）
                          Image.asset(
                            stage.imageAssetPath,
                            width: actorSize,
                            height: actorSize,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                          ),

                          // 💤 睡眠時飄散的夢鄉手繪氣泡
                          if (widget.mood == ActorMood.sleeping)
                            Positioned(
                              top: 6,
                              right: 22,
                              child: AnimatedBuilder(
                                animation: _breatheController,
                                builder: (context, _) {
                                  final double floatVal = _breatheController.value;
                                  return Opacity(
                                    opacity: (0.4 + floatVal * 0.6).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(floatVal * 6, -floatVal * 14),
                                      child: const Text(
                                        '💤',
                                        style: TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                          // ✨ 吃東西時飄起的美味愛心與香氣
                          if (widget.mood == ActorMood.chewing)
                            Positioned(
                              top: 10,
                              child: AnimatedBuilder(
                                animation: _eatController,
                                builder: (context, _) {
                                  final double chewVal = _eatController.value;
                                  return Opacity(
                                    opacity: (1.0 - chewVal).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(0, -chewVal * 18),
                                      child: const Text(
                                        '😋 ✨',
                                        style: TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                          // 👑 達標專屬金色手作榮譽皇冠
                          if (widget.isCrownUnlocked || widget.mood == ActorMood.celebratingGoal)
                            Positioned(
                              top: -10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFFEF3C7), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB45309).withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('👑', style: TextStyle(fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '健康達標榮耀',
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
              ],
            ),
          ),
        );

        if (widget.speechText.isEmpty) {
          return stageWidget;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 繪本手札對話氣泡 ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF8),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFFEADBCE),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF78350F).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF451A03),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            stageWidget,
          ],
        );
      },
    );
  }
}
