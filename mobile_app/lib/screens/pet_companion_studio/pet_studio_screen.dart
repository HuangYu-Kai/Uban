import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/pet_food_item.dart';
import 'models/pet_growth_state.dart';
import '../elder_home_screen.dart';
import 'widgets/animated_piglet_actor.dart';
import 'widgets/food_milestone_tray.dart';
import 'widgets/garden_feeding_sheet.dart';
import 'widgets/hand_drawn_piglet_actor.dart';
import 'widgets/pet_evolution_dialog.dart';
import 'widgets/pet_growth_scale_card.dart';
import 'widgets/pet_particle_canvas.dart';

class PetStudioScreen extends StatefulWidget {
  final int initialSteps;
  final String userName;

  const PetStudioScreen({
    super.key,
    this.initialSteps = 3500,
    this.userName = '宇璿',
  });

  @override
  State<PetStudioScreen> createState() => _PetStudioScreenState();
}

class _PetStudioScreenState extends State<PetStudioScreen>
    with TickerProviderStateMixin {
  late PetGrowthState _growthState;
  bool _isLoading = true;

  ActorMood _actorMood = ActorMood.idle;
  String _speechText = '';
  Timer? _moodResetTimer;

  // 🧺 食物庫存與抽屜開關
  bool _isFeedingSheetOpen = false;
  final Map<String, int> _foodInventory = {
    'carrot': -1, // 常駐無限
    'apple': 3,
    'cabbage': 2,
    'sweet_potato': 2,
    'corn': 1,
    'watermelon': 1,
    'peach_cake': 1,
  };

  // 粒子系統
  final List<StudioParticle> _particles = [];
  late AnimationController _particleAnimController;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _growthState = PetGrowthState(
      weightGrams: 1250,
      vitality: 85,
      todaySteps: widget.initialSteps,
      fedFoodIds: {},
      lastDateStr: '',
      isCrownUnlocked: widget.initialSteps >= 8000,
    );

    _loadSavedData();

    _particleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tickParticles);
    _particleAnimController.repeat();
  }

  Future<void> _loadSavedData() async {
    final state = await PetStorageService.loadState(currentSensorSteps: widget.initialSteps);
    if (mounted) {
      setState(() {
        _growthState = state;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _moodResetTimer?.cancel();
    _particleAnimController.dispose();
    super.dispose();
  }

  void _tickParticles() {
    if (_particles.isEmpty) return;
    setState(() {
      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.position += p.velocity;
        p.velocity += const Offset(0, 0.25);
        p.rotation += p.rotationSpeed;
        p.life -= 0.02;
        p.opacity = (p.life / p.maxLife).clamp(0.0, 1.0);
        if (p.life <= 0) {
          _particles.removeAt(i);
        }
      }
    });
  }

  void _spawnHearts(Offset center, {Color color = const Color(0xFFEC4899), int count = 14}) {
    for (int i = 0; i < count; i++) {
      final double angle = _random.nextDouble() * math.pi * 2;
      final double speed = 2.0 + _random.nextDouble() * 4.5;
      _particles.add(
        StudioParticle(
          position: center,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed - 2.5),
          scale: 0.8 + _random.nextDouble() * 0.6,
          opacity: 1.0,
          color: color,
          type: _random.nextBool() ? ParticleType.heart : ParticleType.star,
          maxLife: 1.0,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.15,
        ),
      );
    }
  }

  void _spawnWeightParticles(Offset center, int grams) {
    _spawnHearts(center, color: const Color(0xFFF59E0B), count: 18);
  }

  // ── 核心餵食邏輯 ──
  void _handleFeedFood(PetFoodItem food) {
    final currentCount = _foodInventory[food.id] ?? food.initialCount;
    if (!food.isUnlimited && currentCount <= 0) {
      _showSnackToast('【${food.name}】已經吃完囉～多散步解鎖新食材吧！🌾');
      return;
    }

    HapticFeedback.heavyImpact();
    final oldStage = _growthState.stage;

    final newFedFoods = Set<String>.from(_growthState.fedFoodIds)..add(food.id);
    final newWeight = _growthState.weightGrams + food.weightGainGrams;
    final newVitality = (_growthState.vitality + food.vitalityGain).clamp(0, 100);

    final newState = _growthState.copyWith(
      fedFoodIds: newFedFoods,
      weightGrams: newWeight,
      vitality: newVitality,
    );

    setState(() {
      _growthState = newState;
      _actorMood = ActorMood.chewing;
      if (!food.isUnlimited && currentCount > 0) {
        _foodInventory[food.id] = currentCount - 1;
      }
    });

    _showSnackToast('小豬大口吃下了【${food.name}】！活力 +${food.vitalityGain} ✨');
    _spawnHearts(const Offset(350, 480), color: food.themeColor, count: 20);
    PetStorageService.saveState(newState);

    _moodResetTimer?.cancel();
    _moodResetTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() {
        _actorMood = ActorMood.superHappy;
      });

      // 檢查是否突破成長階段
      final newStage = newState.stage;
      if (newStage.index > oldStage.index) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            PetEvolutionDialog.show(context, newStage, userName: widget.userName);
          }
        });
      }

      _moodResetTimer = Timer(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _actorMood = ActorMood.idle);
      });
    });
  }

  void _handlePetHead() {
    _spawnHearts(const Offset(350, 420), color: const Color(0xFFEC4899), count: 12);
    setState(() {
      _actorMood = ActorMood.superHappy;
      _speechText = '小豬最喜歡${widget.userName}摸摸頭了～好舒服！🥰✨';
      _growthState = _growthState.copyWith(
        vitality: (_growthState.vitality + 5).clamp(0, 100),
      );
    });
    PetStorageService.saveState(_growthState);

    _moodResetTimer?.cancel();
    _moodResetTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _actorMood = ActorMood.idle);
    });
  }

  void _handlePokeBelly() {
    _spawnHearts(const Offset(350, 500), color: const Color(0xFFF59E0B), count: 10);
    setState(() {
      _actorMood = ActorMood.superHappy;
      _speechText = '咕嚕咕嚕！戳小肚子癢癢的～小豬好開心！😆';
    });

    _moodResetTimer?.cancel();
    _moodResetTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _actorMood = ActorMood.idle);
    });
  }

  void _handleMedicineCheckIn() {
    HapticFeedback.heavyImpact();
    _spawnHearts(const Offset(350, 450), color: const Color(0xFF10B981), count: 16);
    final newState = _growthState.copyWith(
      vitality: (_growthState.vitality + 20).clamp(0, 100),
      weightGrams: _growthState.weightGrams + 500, // +0.5 kg
    );
    setState(() {
      _growthState = newState;
      _actorMood = ActorMood.superHappy;
      _speechText = '太棒了！${widget.userName}準時吃藥照顧身體，小豬陪您健健康康！💊💪 (體重 +0.5 kg ⚖️)';
    });
    PetStorageService.saveState(newState);

    _moodResetTimer?.cancel();
    _moodResetTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _actorMood = ActorMood.idle);
    });
  }

  void _triggerCelebration8000() {
    HapticFeedback.heavyImpact();
    _spawnHearts(const Offset(350, 400), color: const Color(0xFFF59E0B), count: 28);
    final newState = _growthState.copyWith(
      isCrownUnlocked: true,
      vitality: 100,
      weightGrams: _growthState.weightGrams + 1200, // +1.2 kg
    );
    setState(() {
      _growthState = newState;
      _actorMood = ActorMood.celebratingGoal;
      _speechText = '👑 哇！今日 8,000 步全達成！${widget.userName}是全家人的健康冠軍！🏆✨ (體重 +1.2 kg ⚖️)';
    });
    PetStorageService.saveState(newState);

    _moodResetTimer?.cancel();
    _moodResetTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) setState(() => _actorMood = ActorMood.idle);
    });
  }

  void _showSnackToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAF7F2),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFD97706))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final bool isLandscape = orientation == Orientation.landscape;

          return Stack(
            children: [
              // 🌻 1. 全螢幕戶外陽光小菜園油畫手繪背景層
              Positioned.fill(
                child: Image.asset(
                  isLandscape
                      ? 'assets/images/piglet_garden_bg_landscape.jpg'
                      : 'assets/images/piglet_garden_bg_portrait.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              // 2. 粒子繪製層（花瓣與愛心光芒）
              Positioned.fill(
                child: CustomPaint(
                  painter: PetParticleCanvas(_particles),
                ),
              ),

              // 3. 🐷 核心小豬舞台：置中於陽光白三葉草草皮正中央
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isLandscape ? 40 : 80,
                      bottom: isLandscape ? 0 : 20,
                    ),
                    child: HandDrawnPigletActor(
                      mood: _actorMood,
                      stage: _growthState.stage,
                      onFoodAccepted: _handleFeedFood,
                      onPetHead: _handlePetHead,
                      onPokeBelly: _handlePokeBelly,
                      speechText: '',
                      isCrownUnlocked: _growthState.isCrownUnlocked,
                      size: isLandscape ? 380 : 300,
                    ),
                  ),
                ),
              ),

              // 4. 頂部簡約懸浮返回按鈕
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                child: SafeArea(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ElderHomeScreen(
                              userId: 1,
                              userName: widget.userName,
                            ),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8).withValues(alpha: 0.90),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF78350F).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFF451A03),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),

              // 🧺 5. 直接點擊背景右下角手繪蔬果箱（無外加按鈕，純淨隱形互動熱區）
              Positioned(
                right: 0,
                bottom: 0,
                width: isLandscape ? 460 : 260,
                height: isLandscape ? 250 : 180,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isFeedingSheetOpen = true;
                    });
                  },
                ),
              ),

              // 🧺 6. 自適應半透明食匣抽屜（橫螢幕滑自右側、直螢幕升自底部）
              if (_isFeedingSheetOpen)
                Positioned.fill(
                  child: GardenFeedingSheet(
                    isLandscape: isLandscape,
                    foodInventory: _foodInventory,
                    onFeedFood: (food) {
                      _handleFeedFood(food);
                    },
                    onClose: () {
                      setState(() {
                        _isFeedingSheetOpen = false;
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── 頂部資訊欄（三大核心數值膠囊）──
  Widget _buildHeader(bool isLandscape) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 20 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        border: const Border(bottom: BorderSide(color: Color(0xFFEADBCE), width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ElderHomeScreen(
                      userId: 1,
                      userName: widget.userName,
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E7),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5D9C5), width: 1.2),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF451A03),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏡 福氣小豬窩',
                style: GoogleFonts.notoSansTc(
                  fontSize: isLandscape ? 21 : 18.5,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF451A03),
                ),
              ),
              if (isLandscape)
                Text(
                  '散步賺好料，把小豬餵得白白胖胖健康有福氣～',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF854D0E),
                  ),
                ),
            ],
          ),
          const Spacer(),

          // 1. 🐾 今日步數
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🐾', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '${_growthState.todaySteps} 步',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 2. ⚡ 每日活力
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 17, color: Color(0xFF059669)),
                const SizedBox(width: 2),
                Text(
                  '${_growthState.vitality}%',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 3. 🐷 圓潤成長度 (體重)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFDE047), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_growthState.stage.icon, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 5),
                Text(
                  '${_growthState.stage.title} · ${_growthState.weightFormatted}',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF78350F),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 🖥️ 橫螢幕佈局（左右 50/50 雙欄並排）──
  Widget _buildLandscapeLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 👈 左側 50%：小豬生活舞台 ＋ 體重秤卡片
          Expanded(
            flex: 1,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HandDrawnPigletActor(
                      mood: _actorMood,
                      stage: _growthState.stage,
                      onFoodAccepted: _handleFeedFood,
                      onPetHead: _handlePetHead,
                      onPokeBelly: _handlePokeBelly,
                      speechText: _speechText,
                      isCrownUnlocked: _growthState.isCrownUnlocked,
                      size: 300,
                    ),
                    const SizedBox(height: 10),
                    PetGrowthScaleCard(
                      growthState: _growthState,
                      onTap: () => PetEvolutionDialog.show(context, _growthState.stage, userName: widget.userName),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 分隔線
          Container(
            width: 1.5,
            height: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            color: const Color(0xFFE2E8F0),
          ),

          // 👉 右側 50%：8階步數能量盤 ＋ 互動控制面板
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FoodMilestoneTray(
                    currentSteps: _growthState.todaySteps,
                    onSelectFood: _handleFeedFood,
                    fedFoodIds: _growthState.fedFoodIds,
                  ),
                  const SizedBox(height: 14),
                  _buildActionControlPanel(),
                  const SizedBox(height: 14),
                  _buildStepSimulatorCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 📱 直螢幕佈局（上下垂直流暢滑動）──
  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // 上半部舞台
          HandDrawnPigletActor(
            mood: _actorMood,
            stage: _growthState.stage,
            onFoodAccepted: _handleFeedFood,
            onPetHead: _handlePetHead,
            onPokeBelly: _handlePokeBelly,
            speechText: _speechText,
            isCrownUnlocked: _growthState.isCrownUnlocked,
            size: 240,
          ),
          const SizedBox(height: 8),

          PetGrowthScaleCard(
            growthState: _growthState,
            isCompact: false,
            onTap: () => PetEvolutionDialog.show(context, _growthState.stage, userName: widget.userName),
          ),

          const SizedBox(height: 16),

          // 下半部能量盤與互動
          FoodMilestoneTray(
            currentSteps: _growthState.todaySteps,
            onSelectFood: _handleFeedFood,
            fedFoodIds: _growthState.fedFoodIds,
          ),

          const SizedBox(height: 14),
          _buildActionControlPanel(),
          const SizedBox(height: 14),
          _buildStepSimulatorCard(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── 即時生活互動面板 ──
  Widget _buildActionControlPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌟', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                '即時生活互動',
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF451A03),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildActionButton(
                label: '摸摸小豬頭',
                icon: Icons.touch_app_rounded,
                color: const Color(0xFFDB2777),
                bgColor: const Color(0xFFFDF2F8),
                onTap: _handlePetHead,
              ),
              _buildActionButton(
                label: '戳戳圓肚子',
                icon: Icons.sentiment_very_satisfied_rounded,
                color: const Color(0xFFD97706),
                bgColor: const Color(0xFFFFFBEB),
                onTap: _handlePokeBelly,
              ),
              _buildActionButton(
                label: '按時吃藥打卡',
                icon: Icons.medication_rounded,
                color: const Color(0xFF059669),
                bgColor: const Color(0xFFF0FDF4),
                onTap: _handleMedicineCheckIn,
              ),
              _buildActionButton(
                label: '8000步達標慶典',
                icon: Icons.emoji_events_rounded,
                color: const Color(0xFF7C3AED),
                bgColor: const Color(0xFFF5F3FF),
                onTap: _triggerCelebration8000,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 步數模擬拉桿 ──
  Widget _buildStepSimulatorCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_walk_rounded, color: Color(0xFF0369A1), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '步數模擬器 (拖曳滑桿解鎖對應美食)',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF451A03),
                    ),
                  ),
                ],
              ),
              Text(
                '${_growthState.todaySteps} 步',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0369A1),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF0284C7),
              inactiveTrackColor: const Color(0xFFE5D9C5),
              thumbColor: const Color(0xFF0284C7),
              overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
              trackHeight: 6,
            ),
            child: Slider(
              value: _growthState.todaySteps.toDouble(),
              min: 0,
              max: 10000,
              divisions: 20,
              onChanged: (val) {
                final steps = val.round();
                setState(() {
                  _growthState = _growthState.copyWith(
                    todaySteps: steps,
                    isCrownUnlocked: _growthState.isCrownUnlocked || steps >= 8000,
                  );
                });
                PetStorageService.saveState(_growthState);
              },
            ),
          ),
        ],
      ),
    );
  }
}
