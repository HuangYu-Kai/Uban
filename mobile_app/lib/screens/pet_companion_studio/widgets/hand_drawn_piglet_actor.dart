import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_food_item.dart';
import '../models/piglet_sequence_manifest.dart';
import 'animated_piglet_actor.dart';

class HandDrawnPigletActor extends StatefulWidget {
  final ActorMood mood;
  final Function(PetFoodItem food)? onFoodAccepted;
  final VoidCallback? onPetHead;
  final VoidCallback? onPokeBelly;
  final double size;
  final String speechText;
  final bool isCrownUnlocked;

  const HandDrawnPigletActor({
    super.key,
    this.mood = ActorMood.idle,
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
    with SingleTickerProviderStateMixin {
  late AnimationController _sequenceController;
  late PigletSequenceInfo _currentSequence;
  int _currentFrameIndex = 0;
  bool _isDragHovering = false;
  bool _hasPrecached = false;

  @override
  void initState() {
    super.initState();
    _currentSequence = _mapMoodToSequence(widget.mood);

    _sequenceController = AnimationController(
      vsync: this,
      duration: _currentSequence.frameDuration,
    );

    _sequenceController.addListener(_onFrameTick);

    if (_currentSequence.isLooping) {
      _sequenceController.repeat();
    } else {
      _sequenceController.forward(from: 0.0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasPrecached) {
      _hasPrecached = true;
      _precacheAllFrames();
    }
  }

  void _precacheAllFrames() {
    for (final seq in [
      PigletSequenceManifest.idle,
      PigletSequenceManifest.anticipate,
      PigletSequenceManifest.chewing,
      PigletSequenceManifest.celebration,
      PigletSequenceManifest.sleep,
    ]) {
      for (final path in seq.framePaths) {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  void _onFrameTick() {
    final double progress = _sequenceController.value;
    final int nextFrame = (progress * _currentSequence.frameCount).floor().clamp(0, _currentSequence.frameCount - 1);
    if (nextFrame != _currentFrameIndex) {
      setState(() {
        _currentFrameIndex = nextFrame;
      });
    }
  }

  PigletSequenceInfo _mapMoodToSequence(ActorMood mood) {
    if (_isDragHovering || mood == ActorMood.anticipating) {
      return PigletSequenceManifest.anticipate;
    }
    switch (mood) {
      case ActorMood.chewing:
        return PigletSequenceManifest.chewing;
      case ActorMood.superHappy:
      case ActorMood.celebratingGoal:
        return PigletSequenceManifest.celebration;
      case ActorMood.sleeping:
        return PigletSequenceManifest.sleep;
      case ActorMood.idle:
      default:
        return PigletSequenceManifest.idle;
    }
  }

  @override
  void didUpdateWidget(covariant HandDrawnPigletActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood != oldWidget.mood) {
      _updateSequence();
    }
  }

  void _updateSequence() {
    final newSequence = _mapMoodToSequence(widget.mood);
    if (newSequence.type != _currentSequence.type) {
      _currentSequence = newSequence;
      _currentFrameIndex = 0;
      _sequenceController.duration = _currentSequence.frameDuration;

      if (_currentSequence.isLooping) {
        _sequenceController.repeat();
      } else {
        _sequenceController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _sequenceController.removeListener(_onFrameTick);
    _sequenceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onPetHead?.call();
  }

  void _handleLongPress() {
    HapticFeedback.mediumImpact();
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

    final String frameAssetPath = _currentSequence.framePaths[_currentFrameIndex.clamp(0, _currentSequence.frameCount - 1)];

    // 依據慶祝跳躍幀計算地面陰影大小（第 3, 4 幀為跳躍最高點）
    double shadowScale = 1.0;
    double shadowBlur = 12.0;
    double shadowOpacity = 0.22;

    if (_currentSequence.type == PigletSequenceType.celebration) {
      if (_currentFrameIndex == 3 || _currentFrameIndex == 4) {
        shadowScale = 0.55;
        shadowBlur = 24.0;
        shadowOpacity = 0.08;
      } else if (_currentFrameIndex == 2 || _currentFrameIndex == 5) {
        shadowScale = 0.75;
        shadowBlur = 18.0;
        shadowOpacity = 0.14;
      } else if (_currentFrameIndex == 7) {
        shadowScale = 1.15;
        shadowBlur = 8.0;
        shadowOpacity = 0.28;
      }
    }

    return DragTarget<PetFoodItem>(
      onWillAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = true;
          _updateSequence();
        });
        HapticFeedback.selectionClick();
        return true;
      },
      onLeave: (data) {
        setState(() {
          _isDragHovering = false;
          _updateSequence();
        });
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _isDragHovering = false;
          _updateSequence();
        });
        widget.onFoodAccepted?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. 頂部繪本對話氣泡 ──
            if (widget.speechText.isNotEmpty)
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

            // ── 2. 日系手繪逐格舞台 ──
            GestureDetector(
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
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // B. 擬真地面接觸投影 (Frame-linked Dynamic Ground Shadow)
                    Positioned(
                      bottom: 32,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
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
                              blurRadius: shadowBlur,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // C. 核心手繪逐格小豬本體 (Hand-Crafted Frame Sprite)
                    Positioned(
                      bottom: 28,
                      child: SizedBox(
                        width: actorSize,
                        height: actorSize,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // 逐格高畫質手繪影像（使用 IndexedStack 確保硬體層零閃爍、極致絲滑）
                            IndexedStack(
                              index: _currentFrameIndex.clamp(0, _currentSequence.frameCount - 1),
                              alignment: Alignment.center,
                              children: [
                                for (final path in _currentSequence.framePaths)
                                  Image.asset(
                                    path,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true,
                                  ),
                              ],
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
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
