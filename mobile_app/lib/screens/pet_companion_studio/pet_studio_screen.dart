import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/pet_food_item.dart';
import 'models/pet_growth_state.dart';
import '../../services/friend_service.dart';
import '../elder_home_screen.dart';
import 'services/garden_ambient_audio_service.dart';
import 'services/pet_leaderboard_service.dart';
import 'widgets/animated_piglet_actor.dart';
import 'widgets/food_milestone_tray.dart';
import 'widgets/garden_feeding_sheet.dart';
import 'widgets/hand_drawn_piglet_actor.dart';
import 'widgets/pet_evolution_dialog.dart';
import 'widgets/pet_growth_scale_card.dart';
import 'widgets/pet_leaderboard_card.dart';
import 'widgets/pet_particle_canvas.dart';

class PetStudioScreen extends StatefulWidget {
  final int initialSteps;
  final String userName;

  /// 登入使用者的資料庫整數 PK（`user_account_data.user_id`）。
  ///
  /// ⚠️ 這不是好友排行榜要用的 `elder_id`——兩者是資料庫中兩個獨立欄位
  /// （見 `FriendService.resolveMyElderId` 的說明），本畫面內部一律用這個
  /// userId 再呼叫 `FriendService.resolveMyElderId` 換出權威的 4 碼 elder_id，
  /// 不可用 userId 補零臆測。
  final int userId;

  const PetStudioScreen({
    super.key,
    this.initialSteps = 3500,
    this.userName = '宇璿',
    required this.userId,
  });

  @override
  State<PetStudioScreen> createState() => _PetStudioScreenState();
}

class _PetStudioScreenState extends State<PetStudioScreen>
    with TickerProviderStateMixin {
  late PetGrowthState _growthState;
  bool _isLoading = true;

  // 🏆 好友寵物排行榜：elder_id 解析結果與重新整理觸發鍵。
  String? _myElderId;
  bool _hasSyncedInitialWeight = false;
  int _leaderboardRefreshTick = 0;

  ActorMood _actorMood = ActorMood.idle;
  String _speechText = '';
  Timer? _moodResetTimer;

  final GardenAmbientAudioService _audioService = GardenAmbientAudioService();

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
    _resolveElderId();
    _audioService.initAndStartAmbience();

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
      _maybeSyncInitialWeight();
    }
  }

  /// 解析目前登入長輩的好友排行榜 elder_id（權威來源見 [PetStudioScreen.userId]
  /// 的欄位說明）。與 [_loadSavedData] 是各自獨立的非同步流程，兩者哪個先完成
  /// 都在這裡與 [_maybeSyncInitialWeight] 互相補位，不搶跑、不用臆測值頂替。
  Future<void> _resolveElderId() async {
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (!mounted) return;
    setState(() => _myElderId = id);
    _maybeSyncInitialWeight();
  }

  /// 進入寵物介面時，把體重同步一次到好友排行榜。
  ///
  /// 刻意等本機存檔（[_loadSavedData]）與 elder_id 解析（[_resolveElderId]）
  /// 都完成才觸發——兩者是互相獨立的非同步流程，先完成的一方在這裡會因為
  /// 另一項還沒就緒而先行返回，等兩項都到齊時才由後完成的一方補上這一次同步。
  /// 這樣才不會用還沒套用本機存檔的預設體重（1250g）搶先上傳。
  void _maybeSyncInitialWeight() {
    if (_hasSyncedInitialWeight || _isLoading || _myElderId == null) return;
    _hasSyncedInitialWeight = true;
    _syncWeightToLeaderboard();
  }

  /// 把目前體重同步到後端好友排行榜（`POST /api/pet/state`）。
  ///
  /// 刻意不拋例外、不阻擋既有寵物養成流程——`PetLeaderboardService` 內部已經
  /// try/catch 過一層，這裡只是呼叫端，失敗只記 log，不彈錯誤對話框、不影響
  /// 本機存檔／動畫。同步完成（不論成功失敗）都會遞增 `_leaderboardRefreshTick`
  /// ，讓目前開著或之後開啟的排行榜面板重新讀取一次最新名次。
  Future<void> _syncWeightToLeaderboard() async {
    final eid = _myElderId;
    if (eid == null) return;
    final ok = await PetLeaderboardService.uploadMyState(
      elderId: eid,
      weightGrams: _growthState.weightGrams,
    );
    if (!ok) {
      debugPrint('⚠️ [PetStudioScreen] 寵物體重同步到排行榜失敗，不影響本機養成功能');
    }
    if (mounted) {
      setState(() => _leaderboardRefreshTick++);
    }
  }

  @override
  void dispose() {
    _moodResetTimer?.cancel();
    _particleAnimController.dispose();
    _audioService.dispose();
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
    _syncWeightToLeaderboard();

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
    _syncWeightToLeaderboard();

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
    _syncWeightToLeaderboard();

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

              // 2. 🐷 核心小豬舞台：置中於陽光白三葉草草皮正中央
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

              // 3. 粒子繪製層（投餵時的愛心與星芒光芒）
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PetParticleCanvas(_particles),
                  ),
                ),
              ),

              // 🧺 4. 直接點擊背景右下角手繪蔬果箱（無外加按鈕，純淨隱形互動熱區）
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

              // 5. 頂部簡約懸浮返回按鈕
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

              // 🏆🎵 頂部右側懸浮膠囊：排行榜／音樂控制（直式堆疊，避免與音樂
              // 膠囊並排時橫向擠壓造成溢位——鐵律 #14／護欄 G159）
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildLeaderboardButton(),
                      const SizedBox(height: 10),
                      _buildMusicControlButton(),
                    ],
                  ),
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
                '🏡 小豬的家',
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

  // 🏆 頂部排行榜控制膠囊按鈕（開啟好友寵物排行榜面板）
  Widget _buildLeaderboardButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _showLeaderboardSheet();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 6),
              Text(
                '排行榜',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF92400E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🏆 開啟好友寵物排行榜面板（內容沿用 [PetLeaderboardCard]）。
  //
  // 用 ConstrainedBox 限制最高螢幕高度 82% 再包 SingleChildScrollView──
  // PetLeaderboardCard 展開「看全部」時列數不固定，好友數多或系統字級被
  // 長輩調大時都可能超出可視高度，這裡是最後一道防線（鐵律 #14／護欄 G159）。
  void _showLeaderboardSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              child: PetLeaderboardCard(
                myElderId: _myElderId,
                refreshTick: _leaderboardRefreshTick,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🎵 頂部音樂控制膠囊按鈕
  Widget _buildMusicControlButton() {
    final bool isMuted = _audioService.isMuted;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isMuted ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isMuted
                  ? Colors.black.withValues(alpha: 0.05)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 點擊直接切換開/關
            InkWell(
              onTap: () async {
                HapticFeedback.lightImpact();
                await _audioService.toggleMute();
                setState(() {});
                _showSnackToast(
                  _audioService.isMuted
                      ? '🔇 背景音樂已靜音'
                      : '🎵 背景音樂已開啟（${_audioService.currentTrack.title}）',
                );
              },
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isMuted
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMuted
                            ? Icons.music_off_rounded
                            : Icons.music_note_rounded,
                        color: isMuted
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFFD97706),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isMuted ? '音樂：關' : '音樂：開',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isMuted
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF78350F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 分隔細線
            Container(
              width: 1.2,
              height: 18,
              color: const Color(0xFFEADBCE),
            ),
            // 設定/曲目選擇按鈕
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showMusicSettingsSheet();
              },
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(9, 9, 14, 9),
                child: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎼 背景音樂曲目與音量設定面板
  void _showMusicSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final isMuted = _audioService.isMuted;
          final currentTrackId = _audioService.currentTrackId;
          final volume = _audioService.volume;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF78350F).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 標題與關閉
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🎵', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '背景音樂設定',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF451A03),
                            ),
                          ),
                          Text(
                            '柔和悠揚的田園樂章，陪伴長輩與小豬',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12.5,
                              color: const Color(0xFF8C6D58),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF78350F)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 1. 音樂總開關 Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMuted ? const Color(0xFFF8FAFC) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isMuted ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: isMuted ? const Color(0xFF94A3B8) : const Color(0xFFD97706),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMuted ? '音樂已靜音' : '背景音樂播放中',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isMuted ? const Color(0xFF64748B) : const Color(0xFF78350F),
                              ),
                            ),
                            Text(
                              isMuted ? '點擊右側開關即可開啟音樂' : '保持輕柔舒緩的田園陪伴',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !isMuted,
                        activeThumbColor: const Color(0xFFD97706),
                        activeTrackColor: const Color(0xFFFDE68A),
                        onChanged: (val) async {
                          HapticFeedback.lightImpact();
                          await _audioService.toggleMute();
                          setModalState(() {});
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. 音量拉桿（開啟狀態才顯示）
                if (!isMuted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '音量調節',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '${(volume * 100).round()}%',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFD97706),
                      inactiveTrackColor: const Color(0xFFF1EBE1),
                      thumbColor: const Color(0xFFD97706),
                      overlayColor: const Color(0xFFD97706).withValues(alpha: 0.15),
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: volume,
                      min: 0.05,
                      max: 1.0,
                      onChanged: (val) async {
                        await _audioService.setVolume(val);
                        setModalState(() {});
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 3. 曲目清單選擇
                Text(
                  '選擇柔和曲目',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF78350F),
                  ),
                ),
                const SizedBox(height: 8),

                ...GardenAmbientAudioService.availableTracks.map((track) {
                  final bool isSelected = currentTrackId == track.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        await _audioService.setTrack(track.id);
                        setModalState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFFFBEB) : const Color(0xFFFAF7F2),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFEADBCE),
                            width: isSelected ? 2.0 : 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(track.emoji, style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        track.title,
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? const Color(0xFF78350F)
                                              : const Color(0xFF451A03),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFFEF3C7)
                                              : const Color(0xFFF1EBE1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          track.durationText,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF78350F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.description,
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 12,
                                      color: const Color(0xFF8C6D58),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFFD97706),
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
