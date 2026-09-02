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
  // 互動單次彈跳控制器 (450ms 單次靈動彈跳)
  late AnimationController _interactiveBounceController;
  // 進食單次歡喜控制器 (650ms 餵食後靈動開飯動態)
  late AnimationController _feedActionController;
  // 祥瑞光環控制器 (8.0秒極柔和旋轉)
  late AnimationController _auraController;

  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();

    _interactiveBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _feedActionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
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
      _feedActionController.forward(from: 0.0);
    }
    if (widget.mood == ActorMood.superHappy ||
        widget.mood == ActorMood.celebratingGoal) {
      _interactiveBounceController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _interactiveBounceController.dispose();
    _feedActionController.dispose();
    _auraController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _interactiveBounceController.forward(from: 0.0);
    widget.onPetHead?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    _interactiveBounceController.forward(from: 0.0);
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
        _feedActionController.forward(from: 0.0);
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
                // ── A. 溫暖編織羊毛地毯（手作繪本基座）──
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
                          blurRadius: 18,
                          offset: const Offset(0, 6),
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

                // ── B. 貼地柔和接觸陰影（隨跳躍自然縮放）──
                Positioned(
                  bottom: 24,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _interactiveBounceController,
                      _feedActionController,
                    ]),
                    builder: (context, child) {
                      double jump = 0.0;
                      if (_interactiveBounceController.isAnimating) {
                        jump = math.sin(_interactiveBounceController.value * math.pi);
                      } else if (_feedActionController.isAnimating) {
                        jump = math.sin(_feedActionController.value * math.pi * 2).abs() * 0.5;
                      }

                      final double shadowScale = (1.0 - jump * 0.25).clamp(0.7, 1.0);
                      final double shadowOpacity = (0.18 - jump * 0.08).clamp(0.06, 0.20);

                      return Container(
                        width: (actorSize * 0.68) * shadowScale,
                        height: (actorSize * 0.16) * shadowScale,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(
                              (actorSize * 0.68) * shadowScale,
                              (actorSize * 0.16) * shadowScale,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4A3E3D).withValues(alpha: shadowOpacity),
                              blurRadius: 10 + jump * 8,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── C. 祥瑞金光光暈（第 5 階專屬）──
                if (stage == PetGrowthStage.goldenFortunePig)
                  Positioned(
                    bottom: 26,
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
                                  const Color(0xFFFDE68A).withValues(alpha: 0.32),
                                  const Color(0xFFF59E0B).withValues(alpha: 0.08),
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

                // ── D. 核心油畫手繪小豬（保留 100% 原始純美畫作，無拉扯變形）──
                Positioned(
                  bottom: 22,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _interactiveBounceController,
                      _feedActionController,
                    ]),
                    builder: (context, child) {
                      double translateY = 0.0;

                      // 1. 點擊摸摸時：愉悅的單次輕快小跳躍 (Curves.easeOutCubic)
                      if (_interactiveBounceController.isAnimating) {
                        final double t = _interactiveBounceController.value;
                        translateY = -math.sin(t * math.pi) * 16.0;
                      }

                      // 2. 餵食投餵時：開心的雙次歡樂輕躍
                      if (_feedActionController.isAnimating) {
                        final double t = _feedActionController.value;
                        translateY = -math.sin(t * math.pi * 2).abs() * 10.0;
                      }

                      return Transform.translate(
                        offset: Offset(0.0, translateY),
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
                          // 🐷 正面油畫手繪小豬（原生最高清畫質呈現，不變形）
                          Image.asset(
                            stage.imageAssetPath,
                            width: actorSize,
                            height: actorSize,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                          ),

                          // ✨ 餵食時飄起的美味香氣標籤
                          if (widget.mood == ActorMood.chewing)
                            Positioned(
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFDF8),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFEADBCE), width: 1.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF78350F).withValues(alpha: 0.08),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  '😋 大口吃好料～',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF78350F),
                                  ),
                                ),
                              ),
                            ),

                          // 💤 睡覺時安靜的夢鄉標籤
                          if (widget.mood == ActorMood.sleeping)
                            Positioned(
                              top: 8,
                              right: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
                                ),
                                child: const Text(
                                  '💤 呼呼大睡中',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6D28D9),
                                  ),
                                ),
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
