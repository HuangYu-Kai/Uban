import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../pet_companion_studio/models/pet_growth_state.dart';
import '../../../pet_companion_studio/widgets/animated_piglet_actor.dart';
import '../../../pet_companion_studio/widgets/hand_drawn_piglet_actor.dart';
import '../../../pet_companion_studio/widgets/pet_particle_canvas.dart';

/// 🏡🐷 小豬之家「主視覺舞台」──版面借用 Pokémon GO 寶可夢詳情頁的結構：
/// 滿版主視覺 ＋ 置中大隻角色 ＋ 柔光粒子，但**只借版面、不借配色**。
///
/// ⚠️ 背景刻意沿用專案既有的手繪油畫花園圖（不新增任何美術資產），用高斯
/// 模糊 ＋ 米白薄紗淡化來讓小豬本體從背景中跳出來——`docs/general/
/// ART_STYLE_GUIDE_PIGLET.md` 的負向提示詞明文禁止
/// `modern digital gradient / neon saturated colors / flat vector art` 等
/// 現代扁平風格，所以這裡不做任何漸層卡片式的寶可夢 UI 配色，只借版面骨架。
class PetHeroStage extends StatefulWidget {
  /// 小豬目前的成長狀態（決定造型階段與皇冠解鎖與否）。
  final PetGrowthState growthState;

  /// 小豬的對話氣泡文字，交給 [HandDrawnPigletActor] 顯示；可為空字串。
  final String speechText;

  /// 頂部問候語，例如「早安，王大明」——刻意併入主視覺，不再獨立成一張卡片。
  final String greetingLine;

  /// 右上角懸浮膠囊群（季節／排行榜／音樂），由呼叫端組裝傳入；null 則不顯示。
  final Widget? topRightActions;

  /// 這個主視覺舞台佔螢幕高度的比例（0~1）。
  final double heightFactor;

  const PetHeroStage({
    super.key,
    required this.growthState,
    this.speechText = '',
    this.greetingLine = '',
    this.topRightActions,
    this.heightFactor = 0.42,
  });

  @override
  State<PetHeroStage> createState() => _PetHeroStageState();
}

class _PetHeroStageState extends State<PetHeroStage>
    with TickerProviderStateMixin {
  // 🌟 小豬正後方的暖色聚光光暈旋轉控制器——複用
  // `hand_drawn_piglet_actor.dart` 祥瑞光環的做法，但不限定第 5 階、
  // 轉速也放得更慢（14 秒一圈），當作「常駐柔光」而非慶祝特效。
  late final AnimationController _auraController;

  // ✨ 柔光粒子系統（花粉／螢火蟲／閃爍星芒），沿用
  // `pet_studio_screen.dart` 的 tick 邏輯，本元件自己持有狀態。
  late final AnimationController _particleAnimController;
  final List<StudioParticle> _particles = [];
  final math.Random _random = math.Random();
  double _spawnAccumulator = 0;

  static const List<ParticleType> _softParticleTypes = [
    ParticleType.pollen,
    ParticleType.firefly,
    ParticleType.sparkle,
  ];

  @override
  void initState() {
    super.initState();

    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14000),
    )..repeat();

    _particleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tickParticles);
    _particleAnimController.repeat();
  }

  @override
  void dispose() {
    _auraController.dispose();
    _particleAnimController.dispose();
    super.dispose();
  }

  void _tickParticles() {
    // 每隔一小段時間補一顆新的柔光微粒，維持畫面上大約 6~8 顆漂浮，
    // 密度低不遮擋小豬本體，也不會顯得空蕩。
    _spawnAccumulator += 1;
    if (_spawnAccumulator > 40 && _particles.length < 8 && mounted) {
      _spawnAccumulator = 0;
      _spawnParticle();
    }

    if (_particles.isEmpty) return;
    setState(() {
      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.position += p.velocity;
        p.rotation += p.rotationSpeed;
        p.life -= 0.006;
        p.opacity = (p.life / p.maxLife).clamp(0.0, 1.0);
        if (p.life <= 0) {
          _particles.removeAt(i);
        }
      }
    });
  }

  void _spawnParticle() {
    final Size size = MediaQuery.sizeOf(context);
    final double heroHeight = size.height * widget.heightFactor;
    final ParticleType type =
        _softParticleTypes[_random.nextInt(_softParticleTypes.length)];
    final double startX = _random.nextDouble() * size.width;
    final double startY = heroHeight * (0.15 + _random.nextDouble() * 0.6);
    _particles.add(
      StudioParticle(
        position: Offset(startX, startY),
        velocity: Offset(
          (_random.nextDouble() - 0.5) * 0.4,
          -0.25 - _random.nextDouble() * 0.35,
        ),
        scale: 0.7 + _random.nextDouble() * 0.6,
        opacity: 1.0,
        color: const Color(0xFFFDE68A),
        type: type,
        maxLife: 1.0,
        life: 1.0,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.05,
      ),
    );
  }

  /// 頂部問候列與右上膠囊群佔用的高度。小豬的可用空間要先扣掉它，
  /// 否則氣泡會被擠到問候列後面，變成穿透 0.82 半透明卡片的鬼影文字。
  /// 精簡圖示橫排（40px 圓鈕）＋ 上下內距；直向手機用這個值。
  /// 先前設 76 是沿用完整文字膠囊的高度，膠囊改精簡後等於白白吃掉
  /// 20px，小豬被壓得比該有的小。
  static const double _topBarReserve = 20.0;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double heroHeight = screenSize.height * widget.heightFactor;

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 滿版手繪花園背景（沿用專案既有素材，加高斯模糊淡化凸顯小豬）
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Image.asset(
                isLandscape
                    ? 'assets/images/piglet_garden_bg_landscape.jpg'
                    : 'assets/images/piglet_garden_bg_portrait.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. 米白薄紗淡化層——讓小豬本體從模糊背景中跳出來
          Positioned.fill(
            child: Container(
              color: const Color(0xFFFAF7F2).withValues(alpha: 0.42),
            ),
          ),

          // 3. 小豬正後方的暖色聚光光暈（任何階段皆有，慢速旋轉、含蓄不搶戲）
          Center(
            child: AnimatedBuilder(
              animation: _auraController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _auraController.value * 2 * math.pi,
                  child: child,
                );
              },
              child: Container(
                width: isLandscape ? 340 : 300,
                height: isLandscape ? 340 : 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFDE68A).withValues(alpha: 0.30),
                      const Color(0xFFF59E0B).withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.25, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 4. 置中大隻手繪小豬（版面核心，依階段與體重升級數據動態縮放體積）
          Padding(
            padding: const EdgeInsets.only(
              top: _topBarReserve,
              bottom: 16,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 依照階段與體重升級數據，建立動態體積縮放比例
                final int stageIdx = widget.growthState.stage.index; // 0 ~ 4
                final double progress = widget.growthState.stageProgress.clamp(0.0, 1.0);
                
                // 階段基底比例（第 1 階約 0.82，隨升級顯著放大到第 5 階 1.25）
                final double stageBaseScale = 0.82 + (stageIdx * 0.08) + (progress * 0.05);

                final double cap = isLandscape ? 360.0 : 310.0;
                final double byHeight = constraints.maxHeight / 1.15;
                final double byWidth = constraints.maxWidth / 1.15;
                final double baseSize = math.min(math.min(byHeight, byWidth), cap);
                final double actorSize = (baseSize * stageBaseScale).clamp(170.0, cap * 1.2);

                return Center(
                  child: HandDrawnPigletActor(
                    size: actorSize,
                    stage: widget.growthState.stage,
                    mood: ActorMood.idle,
                    speechText: '', // 移除上方對話氣泡，騰出空間給放大的小豬
                    isCrownUnlocked: widget.growthState.isCrownUnlocked,
                  ),
                );
              },
            ),
          ),

          // 5. 柔光粒子層（花粉／螢火蟲／閃爍星芒，純裝飾不吃互動事件）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: PetParticleCanvas(_particles)),
            ),
          ),

          // 6. 底部軟邊收尾——羽化銜接下方資訊卡，美術規範要求不可硬裁
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 90,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFFFAF7F2)],
                  ),
                ),
              ),
            ),
          ),

          // 7. 右上角懸浮膠囊群（季節／排行榜／音樂），頂部問候橫幅已移除
          if (widget.topRightActions != null)
            Positioned(
              top: 0,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: widget.topRightActions!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
