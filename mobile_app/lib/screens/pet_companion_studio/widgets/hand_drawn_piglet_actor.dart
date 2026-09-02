import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';
import '../models/pet_growth_state.dart';
import '../models/piglet_sequence_manifest.dart';
import 'animated_piglet_actor.dart';

/// 🐷 手繪油畫正面小豬逐格幀動畫組件（逐格幀播放 ✕ 100% 組員水彩油畫手作風）
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
  // 逐格幀控制器
  int _currentFrameIndex = 0;
  Timer? _sequenceTimer;
  PigletSequenceType _currentSeqType = PigletSequenceType.idle;

  // 互動單次彈跳控制器 (450ms)
  late AnimationController _interactiveBounceController;
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

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _startSequenceForMood(widget.mood);
  }

  @override
  void reassemble() {
    super.reassemble();
    _startSequenceForMood(widget.mood);
  }

  @override
  void didUpdateWidget(covariant HandDrawnPigletActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood != oldWidget.mood) {
      _startSequenceForMood(widget.mood);
    }
  }

  void _startSequenceForMood(ActorMood mood) {
    _sequenceTimer?.cancel();

    PigletSequenceType newSeq;
    switch (mood) {
      case ActorMood.chewing:
        newSeq = PigletSequenceType.chewing;
        break;
      case ActorMood.anticipating:
        newSeq = PigletSequenceType.anticipate;
        break;
      case ActorMood.superHappy:
      case ActorMood.celebratingGoal:
        newSeq = PigletSequenceType.celebration;
        _interactiveBounceController.forward(from: 0.0);
        break;
      case ActorMood.sleeping:
        newSeq = PigletSequenceType.sleep;
        break;
      case ActorMood.idle:
      default:
        newSeq = PigletSequenceType.idle;
        break;
    }

    _currentSeqType = newSeq;
    _currentFrameIndex = 0;

    final info = PigletSequenceManifest.getInfo(newSeq);
    final int frameIntervalMs = (info.frameDuration.inMilliseconds / info.frameCount).round();

    _sequenceTimer = Timer.periodic(Duration(milliseconds: frameIntervalMs), (timer) {
      if (!mounted) return;
      setState(() {
        if (info.isLooping) {
          _currentFrameIndex = (_currentFrameIndex + 1) % info.frameCount;
        } else {
          if (_currentFrameIndex < info.frameCount - 1) {
            _currentFrameIndex++;
          } else {
            _sequenceTimer?.cancel();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    _interactiveBounceController.dispose();
    _auraController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _interactiveBounceController.forward(from: 0.0);
    _startSequenceForMood(ActorMood.superHappy);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && widget.mood == ActorMood.idle) {
        _startSequenceForMood(ActorMood.idle);
      }
    });
    widget.onPetHead?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
    _interactiveBounceController.forward(from: 0.0);
    _startSequenceForMood(ActorMood.anticipating);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && widget.mood == ActorMood.idle) {
        _startSequenceForMood(ActorMood.idle);
      }
    });
    widget.onPokeBelly?.call();
  }

  String get _currentFramePath {
    final info = PigletSequenceManifest.getInfo(_currentSeqType);
    final paths = info.framePaths;
    if (_currentFrameIndex >= 0 && _currentFrameIndex < paths.length) {
      return paths[_currentFrameIndex];
    }
    return widget.stage.imageAssetPath;
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
        _startSequenceForMood(ActorMood.anticipating);
        HapticFeedback.selectionClick();
        return true;
      },
      onLeave: (data) {
        setState(() => _isDragHovering = false);
        _startSequenceForMood(widget.mood);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isDragHovering = false);
        _startSequenceForMood(ActorMood.chewing);
        Timer(const Duration(milliseconds: 2500), () {
          if (mounted && widget.mood == ActorMood.idle) {
            _startSequenceForMood(ActorMood.idle);
          }
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
                // ── A. 貼地柔和接觸陰影（自然融入草地）──
                Positioned(
                  bottom: 24,
                  child: AnimatedBuilder(
                    animation: _interactiveBounceController,
                    builder: (context, child) {
                      double jump = 0.0;
                      if (_interactiveBounceController.isAnimating) {
                        jump = math.sin(_interactiveBounceController.value * math.pi);
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

                // ── D. 核心油畫手繪小豬（逐格幀動畫 + 觸發時輕躍）──
                Positioned(
                  bottom: 22,
                  child: AnimatedBuilder(
                    animation: _interactiveBounceController,
                    builder: (context, child) {
                      double translateY = 0.0;

                      // 點擊摸摸時：愉悅的單次輕快小跳躍
                      if (_interactiveBounceController.isAnimating) {
                        final double t = _interactiveBounceController.value;
                        translateY = -math.sin(t * math.pi) * 16.0;
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
                          // 🐷 正面油畫手繪小豬（逐格幀高清透明呈現，不變形）
                          Image.asset(
                            _currentFramePath,
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
