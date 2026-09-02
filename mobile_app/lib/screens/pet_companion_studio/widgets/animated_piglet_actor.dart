import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';

enum ActorMood {
  idle,
  anticipating,
  chewing,
  superHappy,
  celebratingGoal,
  sleeping,
}

class AnimatedPigletActor extends StatefulWidget {
  final ActorMood mood;
  final Function(PetFoodItem food)? onFoodAccepted;
  final VoidCallback? onPetHead;
  final VoidCallback? onPokeBelly;
  final double size;
  final String speechText;
  final bool isCrownUnlocked;

  const AnimatedPigletActor({
    super.key,
    this.mood = ActorMood.idle,
    this.onFoodAccepted,
    this.onPetHead,
    this.onPokeBelly,
    this.size = 280,
    this.speechText = '',
    this.isCrownUnlocked = false,
  });

  @override
  State<AnimatedPigletActor> createState() => _AnimatedPigletActorState();
}

class _AnimatedPigletActorState extends State<AnimatedPigletActor>
    with TickerProviderStateMixin {
  late AnimationController _breatheController;
  late AnimationController _chewController;
  late AnimationController _jumpController;
  late AnimationController _petSquishController;
  late AnimationController _wiggleController;
  late AnimationController _tailWagController;

  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();

    // 1. 溫柔呼吸動態 (Organic slow breathing)
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // 2. 咀嚼動態 (Chewing rhythm)
    _chewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    // 3. 開心跳躍動態 (Joyful bounce)
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // 4. 觸摸壓扁彈性物理 (Elastic Squash & Stretch)
    _petSquishController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    // 5. 戳肚子搖擺 (Poke Wiggle)
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 6. 尾巴/微浮動態
    _tailWagController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedPigletActor oldWidget) {
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

      if (widget.mood == ActorMood.superHappy || widget.mood == ActorMood.celebratingGoal) {
        _jumpController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _chewController.dispose();
    _jumpController.dispose();
    _petSquishController.dispose();
    _wiggleController.dispose();
    _tailWagController.dispose();
    super.dispose();
  }

  void _triggerPetInteraction() {
    HapticFeedback.lightImpact();
    _petSquishController.forward(from: 0.0);
    _jumpController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  void _triggerBellyPoke() {
    HapticFeedback.mediumImpact();
    _wiggleController.forward(from: 0.0);
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
    final double stageWidth = widget.size * 1.35;
    final double stageHeight = widget.size * 1.35;

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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. 頂部對話氣泡（立體圓角、帶小尾巴的繪本感對話框） ──
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

            // ── 2. 自然居室生活舞台（地毯 + 擬真動態投影 + 小豬本體） ──
            GestureDetector(
              onTap: _triggerPetInteraction,
              onLongPress: _triggerBellyPoke,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _breatheController,
                  _chewController,
                  _jumpController,
                  _petSquishController,
                  _wiggleController,
                  _tailWagController,
                ]),
                builder: (context, child) {
                  // 呼吸縮放 (Natural breathing scale)
                  final double breatheScaleY = 1.0 + (_breatheController.value * 0.025);
                  final double breatheScaleX = 1.0 - (_breatheController.value * 0.015);

                  // 咀嚼物理形變 (Chew Squash & Stretch)
                  final double chewSquashX = 1.0 + (_chewController.value * 0.06);
                  final double chewSquashY = 1.0 - (_chewController.value * 0.05);

                  // 觸摸彈性壓扁
                  final double petSquishX = 1.0 + (math.sin(_petSquishController.value * math.pi) * 0.12);
                  final double petSquishY = 1.0 - (math.sin(_petSquishController.value * math.pi) * 0.12);

                  // 戳肚子擺動
                  final double wiggleAngle = math.sin(_wiggleController.value * math.pi * 3) * 0.06;

                  // 跳躍高度
                  final double jumpProgress = _jumpController.value;
                  final double jumpY = -math.sin(jumpProgress * math.pi) * 36.0;

                  // 動態陰影物理參數：跳得越高，地面陰影越小、越模糊、越淡
                  final double shadowFactor = 1.0 - (math.sin(jumpProgress * math.pi) * 0.45);
                  final double shadowBlur = 12.0 + (math.sin(jumpProgress * math.pi) * 16.0);
                  final double shadowOpacity = (0.22 * shadowFactor).clamp(0.05, 0.28);

                  return SizedBox(
                    width: stageWidth,
                    height: stageHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // A. 溫馨編織軟毛地毯 (Cozy Rug Base)
                        Positioned(
                          bottom: 20,
                          child: Container(
                            width: widget.size * 1.18,
                            height: widget.size * 0.48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAF5),
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(widget.size * 1.18, widget.size * 0.48),
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
                                width: widget.size * 0.95,
                                height: widget.size * 0.36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.elliptical(widget.size * 0.95, widget.size * 0.36),
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
                            width: (widget.size * 0.68) * shadowFactor,
                            height: (widget.size * 0.18) * shadowFactor,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(
                                  (widget.size * 0.68) * shadowFactor,
                                  (widget.size * 0.18) * shadowFactor,
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

                        // C. 核心去背小豬本體 (Transparent Organic Sprite with Smooth Morphing)
                        Positioned(
                          bottom: 28,
                          child: Transform.translate(
                            offset: Offset(0, jumpY),
                            child: Transform.rotate(
                              angle: wiggleAngle,
                              child: Transform.scale(
                                scaleX: breatheScaleX * chewSquashX * petSquishX * (_isDragHovering ? 1.06 : 1.0),
                                scaleY: breatheScaleY * chewSquashY * petSquishY * (_isDragHovering ? 1.06 : 1.0),
                                alignment: Alignment.bottomCenter,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    // 絲滑過渡切換器 (Smooth Cross-fade Animated Switcher)
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 320),
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
                                      child: SizedBox(
                                        key: ValueKey<String>(_currentAsset),
                                        width: widget.size,
                                        height: widget.size,
                                        child: Image.asset(
                                          _currentAsset,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(Icons.pets_rounded, size: 80, color: Color(0xFF59B294)),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 👑 達標專屬金色榮譽皇冠
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
