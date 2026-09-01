import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';
import '../models/pet_growth_state.dart';
import 'animated_piglet_actor.dart';

/// 🐷 手繪油畫正面小豬角色本體組件
/// 直接載入組員提供的五階段正面手繪小豬圖，並搭配生動的物理交互動效
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
  late AnimationController _breatheController;
  late AnimationController _chewController;
  late AnimationController _jumpController;
  late AnimationController _squishController;
  late AnimationController _auraController;

  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();

    // 1. 溫柔呼吸與浮動動畫 (2.4 秒循環)
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 2. 咀嚼進食動畫 (450ms 循環)
    _chewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    // 3. 開心跳躍動畫 (600ms)
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 4. 摸摸/戳戳彈性形變動畫 (400ms)
    _squishController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 5. 祥瑞金光光環旋轉 (4.0 秒循環)
    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _syncMoodControllers();
  }

  @override
  void didUpdateWidget(covariant HandDrawnPigletActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood != oldWidget.mood) {
      _syncMoodControllers();
    }
  }

  void _syncMoodControllers() {
    if (widget.mood == ActorMood.chewing) {
      _chewController.repeat(reverse: true);
    } else {
      _chewController.stop();
      _chewController.reset();
    }

    if (widget.mood == ActorMood.superHappy ||
        widget.mood == ActorMood.celebratingGoal) {
      _jumpController.repeat(reverse: true);
    } else {
      _jumpController.stop();
      _jumpController.reset();
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _chewController.dispose();
    _jumpController.dispose();
    _squishController.dispose();
    _auraController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _squishController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    _squishController.forward(from: 0.0);
    widget.onPokeBelly?.call();
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
    final stage = widget.stage;

    return DragTarget<PetFoodItem>(
      onWillAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = true;
        });
        HapticFeedback.selectionClick();
        return true;
      },
      onLeave: (data) {
        setState(() {
          _isDragHovering = false;
        });
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = false;
        });
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
                // A. 溫馨編織軟毛地毯
                Positioned(
                  bottom: 16,
                  child: Container(
                    width: actorSize * 1.18,
                    height: actorSize * 0.46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF5),
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(actorSize * 1.18, actorSize * 0.46),
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
                        height: actorSize * 0.34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(actorSize * 0.95, actorSize * 0.34),
                          ),
                          border: Border.all(
                            color: _themeColor.withValues(alpha: 0.15),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // B. 擬真地面接觸動態投影
                Positioned(
                  bottom: 28,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_breatheController, _jumpController]),
                    builder: (context, child) {
                      double jumpOffset = 0.0;
                      if (widget.mood == ActorMood.superHappy ||
                          widget.mood == ActorMood.celebratingGoal) {
                        jumpOffset = math.sin(_jumpController.value * math.pi);
                      }
                      final double shadowScale = 1.0 - jumpOffset * 0.35;
                      final double shadowOpacity = (0.22 - jumpOffset * 0.12).clamp(0.05, 0.25);

                      return Container(
                        width: (actorSize * 0.68) * shadowScale,
                        height: (actorSize * 0.18) * shadowScale,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(
                              (actorSize * 0.68) * shadowScale,
                              (actorSize * 0.18) * shadowScale,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF334155).withValues(alpha: shadowOpacity),
                              blurRadius: 12 + jumpOffset * 10,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // C. 神獸階段或慶祝時的溫暖金光光環 (Golden Shimmer Aura)
                if (stage == PetGrowthStage.goldenFortunePig ||
                    widget.mood == ActorMood.celebratingGoal)
                  Positioned(
                    bottom: 30,
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
                                  const Color(0xFFFBBF24).withValues(alpha: 0.35),
                                  const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                                stops: const [0.2, 0.6, 1.0],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // D. 核心手繪油畫正面小豬本體 (Physical Sprite with Multi-Sensory Motion)
                Positioned(
                  bottom: 24,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _breatheController,
                      _chewController,
                      _jumpController,
                      _squishController,
                    ]),
                    builder: (context, child) {
                      // 1. 呼吸浮動
                      final double breathSin = math.sin(_breatheController.value * 2 * math.pi);
                      double translateY = breathSin * -3.5;
                      double scaleX = 1.0 - breathSin * 0.015;
                      double scaleY = 1.0 + breathSin * 0.025;
                      double rotation = 0.0;

                      // 2. 咀嚼動效 (大口吃東西)
                      if (widget.mood == ActorMood.chewing) {
                        final double chewSin = math.sin(_chewController.value * 2 * math.pi);
                        scaleX += chewSin * 0.06;
                        scaleY -= chewSin * 0.05;
                        translateY += chewSin * -2.0;
                      }

                      // 3. 跳躍動效 (開心與慶祝)
                      if (widget.mood == ActorMood.superHappy ||
                          widget.mood == ActorMood.celebratingGoal) {
                        final double jumpVal = math.sin(_jumpController.value * math.pi);
                        translateY -= jumpVal * 20.0;
                        rotation = math.sin(_jumpController.value * 2 * math.pi) * 0.06;
                        scaleY += jumpVal * 0.05;
                      }

                      // 4. 期待投餵 (拖拽食物經過時)
                      if (_isDragHovering || widget.mood == ActorMood.anticipating) {
                        scaleX *= 1.06;
                        scaleY *= 1.06;
                        translateY -= 6.0;
                      }

                      // 5. 睡覺放鬆狀態
                      if (widget.mood == ActorMood.sleeping) {
                        rotation = -0.06;
                        translateY += 4.0;
                        scaleY = 0.95 + breathSin * 0.015;
                      }

                      // 6. 點擊/長按彈性質感形變
                      if (_squishController.isAnimating) {
                        final double squishVal = math.sin(_squishController.value * math.pi);
                        scaleX += squishVal * 0.12;
                        scaleY -= squishVal * 0.10;
                      }

                      return Transform.translate(
                        offset: Offset(0, translateY),
                        child: Transform.rotate(
                          angle: rotation,
                          child: Transform.scale(
                            scaleX: scaleX,
                            scaleY: scaleY,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: actorSize,
                      height: actorSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // 🐷 正面油畫手繪小豬圖檔（根據 stage 精準切換）
                          Image.asset(
                            stage.imageAssetPath,
                            width: actorSize,
                            height: actorSize,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                          ),

                          // 💤 睡覺浮動 Zzz 氣泡
                          if (widget.mood == ActorMood.sleeping)
                            Positioned(
                              top: 10,
                              right: 20,
                              child: AnimatedBuilder(
                                animation: _breatheController,
                                builder: (context, _) {
                                  final double floatVal = _breatheController.value;
                                  return Opacity(
                                    opacity: (0.3 + floatVal * 0.7).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(floatVal * 6, -floatVal * 12),
                                      child: const Text(
                                        '💤',
                                        style: TextStyle(fontSize: 26),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                          // 👑 達標專屬金色榮譽皇冠
                          if (widget.isCrownUnlocked || widget.mood == ActorMood.celebratingGoal)
                            Positioned(
                              top: -12,
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
            // 頂部繪本對話氣泡
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _themeColor.withValues(alpha: 0.5),
                  width: 2.2,
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
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _themeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.mood == ActorMood.celebratingGoal ? '👑' : '💬',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.speechText,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                        height: 1.45,
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
