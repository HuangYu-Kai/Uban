import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/desktop_pet.dart';
import '../services/game_service.dart';
import 'pet_interaction_screen.dart';

class PetProfileScreen extends StatefulWidget {
  final int userId;
  final int steps;
  final int level;
  final PetMood mood;
  final String assetPath;

  const PetProfileScreen({
    super.key,
    required this.userId,
    required this.steps,
    required this.level,
    required this.mood,
    required this.assetPath,
  });

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _HeartParticle {
  Offset position;
  Offset velocity;
  double scale;
  double opacity;
  Color color;

  _HeartParticle({
    required this.position,
    required this.velocity,
    required this.scale,
    required this.opacity,
    required this.color,
  });
}

class _PetProfileScreenState extends State<PetProfileScreen> with TickerProviderStateMixin {
  final GameService _gameService = GameService();
  
  // 養成狀態
  int _hunger = 50;
  int _intimacy = 50;
  int _steps = 0;
  int _level = 1;
  bool _isLoadingStatus = true;

  // 蘋果投餵狀態
  Offset _applePos = Offset.zero;
  bool _isDragging = false;
  bool _isFlying = false;
  
  // 物理與動畫控制器
  late AnimationController _flightController;
  Offset _flightStartPos = Offset.zero;
  Offset _flightVelocity = Offset.zero;
  final double _gravity = 2000.0; // px/s^2

  // 元件中心位置
  Offset _pigCenter = Offset.zero;
  bool _initializedPos = false;

  // 粒子特效
  List<_HeartParticle> _particles = [];
  late AnimationController _particleController;

  // 菲比語對話
  String? _dialogText;
  Timer? _dialogTimer;
  bool _isHappyState = false;

  final List<String> _feedSuccessDialogs = [
    '好吃！肚肚飽飽嚕嚕～啾比！😋',
    '甜甜蘋果，小豬最愛，啵啵！🍎',
    '好幸福喔！嘎挖啾比！💖',
    '阿公阿嬤餵的蘋果最好吃了！嚕嚕～✨',
  ];

  final List<String> _normalDialogs = [
    '記得多喝水水，嚕嚕啵啵！🐷',
    '貼貼阿公阿嬤，啾比啾比！💖',
    '今天走了好多步，阿公阿嬤超棒嚕嚕！🐾',
    '嘎挖！皮皮一直陪伴在您身邊喔～🌸',
  ];

  @override
  void initState() {
    super.initState();
    _steps = widget.steps;
    _level = widget.level;

    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onFlightTick);
    
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onParticleTick);

    _fetchLatestStatus();
    _showNormalDialog();
  }

  @override
  void dispose() {
    _flightController.dispose();
    _particleController.dispose();
    _dialogTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLatestStatus() async {
    try {
      final status = await _gameService.getElderStatus(widget.userId.toString());
      if (mounted) {
        setState(() {
          _hunger = status['hunger'] ?? 50;
          _intimacy = status['intimacy'] ?? 50;
          _steps = status['step_total'] ?? widget.steps;
          _level = status['level'] ?? widget.level;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
        });
      }
    }
  }

  void _showNormalDialog() {
    _dialogTimer?.cancel();
    setState(() {
      _dialogText = _normalDialogs[Random().nextInt(_normalDialogs.length)];
    });
    // 每 15 秒隨機更新一次常態對話
    _dialogTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isHappyState && !_isFlying) {
        _showNormalDialog();
      }
    });
  }

  void _initPositions(double width, double height) {
    if (_initializedPos) return;
    _initializedPos = true;
    // 預估小豬的中心位置：寬度一半，高度約在螢幕的 28% 處
    _pigCenter = Offset(width / 2, height * 0.28);
    // 蘋果的初始發射位置：寬度一半，高度在螢幕底部的 160 像素上方
    _applePos = Offset(width / 2 - 25, height - 160);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isFlying) return;
    
    final velocity = details.velocity.pixelsPerSecond;
    double vx = velocity.dx.clamp(-1200.0, 1200.0);
    double vy = velocity.dy.clamp(-2500.0, -400.0); // 確保是向上滑動

    if (vy < -500.0) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isDragging = false;
        _isFlying = true;
        _flightStartPos = _applePos;
        _flightVelocity = Offset(vx, vy);
      });
      _flightController.forward(from: 0.0);
    } else {
      // 速度不足，彈回原點
      _resetApplePosition();
    }
  }

  void _onFlightTick() {
    if (!_isFlying) return;
    final t = _flightController.value;
    final dt = t * 0.8; // 我們假設飛行時間上限為 0.8 秒

    // 物理公式計算位置
    final x = _flightStartPos.dx + _flightVelocity.dx * dt;
    final y = _flightStartPos.dy + _flightVelocity.dy * dt + 0.5 * _gravity * dt * dt;

    setState(() {
      _applePos = Offset(x, y);
    });

    // 碰撞檢測 (檢測蘋果中心與小豬中心的距離)
    final appleCenter = _applePos + const Offset(25, 25);
    final distance = (appleCenter - _pigCenter).distance;

    if (distance < 75) {
      _flightController.stop();
      _onFeedSuccess();
    } else if (y > MediaQuery.of(context).size.height || x < -60 || x > MediaQuery.of(context).size.width + 60) {
      _flightController.stop();
      _onFeedMiss();
    }
  }

  void _onFeedSuccess() {
    HapticFeedback.heavyImpact();
    _dialogTimer?.cancel();
    
    setState(() {
      _isFlying = false;
      _isHappyState = true;
      _hunger = min(100, _hunger + 15);
      _intimacy = min(100, _intimacy + 5);
      _dialogText = _feedSuccessDialogs[Random().nextInt(_feedSuccessDialogs.length)];
    });

    _spawnParticles();

    // 發送狀態到後端
    _gameService.updatePetStatus(widget.userId.toString(), _hunger, _intimacy).catchError((err) {
      debugPrint("Failed to update status: $err");
    });

    // 3.5秒後復原
    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _isHappyState = false;
        });
        _resetApplePosition();
        _showNormalDialog();
      }
    });
  }

  void _onFeedMiss() {
    HapticFeedback.vibrate();
    _dialogTimer?.cancel();
    setState(() {
      _dialogText = '哎呀，沒投準！再試一次嘛～啾比！🍎';
    });
    _resetApplePosition();
    _dialogTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _showNormalDialog();
      }
    });
  }

  void _resetApplePosition() {
    final size = MediaQuery.of(context).size;
    setState(() {
      _isDragging = false;
      _isFlying = false;
      _applePos = Offset(size.width / 2 - 25, size.height - 160);
    });
  }

  void _spawnParticles() {
    final rand = Random();
    _particles = List.generate(16, (index) {
      final angle = rand.nextDouble() * 2 * pi;
      final speed = 150.0 + rand.nextDouble() * 200.0;
      return _HeartParticle(
        position: _pigCenter,
        velocity: Offset(cos(angle) * speed, sin(angle) * speed),
        scale: 0.6 + rand.nextDouble() * 0.8,
        opacity: 1.0,
        color: rand.nextBool() ? Colors.pinkAccent : Colors.cyanAccent,
      );
    });
    _particleController.forward(from: 0.0);
  }

  void _onParticleTick() {
    final t = _particleController.value;
    if (t >= 1.0) {
      _particles.clear();
    } else {
      for (var p in _particles) {
        p.position += p.velocity * 0.016; // 假設 60fps 步長
        p.position += const Offset(0, -0.8); // 輕微向上漂浮
        p.opacity = (1.0 - t).clamp(0.0, 1.0);
      }
    }
    setState(() {});
  }

  String _getMoodText(PetMood mood) {
    switch (mood) {
      case PetMood.energetic: return "活力百倍 ✨";
      case PetMood.lazy: return "懶洋洋 👣";
      case PetMood.tired: return "累呼呼 💤";
      case PetMood.normal: return "平靜安穩 😊";
    }
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withOpacity(0.02),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildNeonProgressBar({
    required String label,
    required int value,
    required List<Color> colors,
    required IconData icon,
    required Color glowColor,
  }) {
    final percent = (value / 100.0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: glowColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.notoSansTc(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              "$value / 100",
              style: GoogleFonts.orbitron(
                color: glowColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            return Stack(
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                if (value > 0)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    width: barWidth * percent,
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                if (value > 0)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    width: barWidth * percent,
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: LinearGradient(
                        colors: colors,
                      ),
                    ),
                  ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildNeonStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.03),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.notoSansTc(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _initPositions(size.width, size.height);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                "傳送至 3D 空間",
                style: GoogleFonts.notoSansTc(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
         .shimmer(duration: 2.seconds, color: Colors.cyanAccent.withOpacity(0.3))
         .scaleXY(begin: 1.0, end: 1.03, duration: 1200.ms, curve: Curves.easeInOut),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PetInteractionScreen(
                    userId: widget.userId,
                    steps: _steps,
                    level: _level,
                    mood: widget.mood,
                    assetPath: widget.assetPath,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
              ),
              child: const Icon(Icons.videogame_asset, color: Colors.cyanAccent, size: 20),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 霓虹暗黑底色背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF020617),
                ],
              ),
            ),
          ),

          // 背景環境霓虹光暈
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.pinkAccent.withOpacity(0.08),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.06),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),

          // 拖曳投餵時的霓虹軌跡虛線
          if (_isDragging)
            CustomPaint(
              size: Size.infinite,
              painter: _TrajectoryPainter(
                start: Offset(size.width / 2, size.height - 135),
                end: _applePos + const Offset(25, 25),
              ),
            ),

          // 核心 UI 內容
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                
                // 小豬互動與對話區
                SizedBox(
                  height: size.height * 0.38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 對話框
                      if (_dialogText != null)
                        Positioned(
                          top: 10,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            constraints: BoxConstraints(maxWidth: size.width - 48),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isHappyState ? Colors.pinkAccent : Colors.white.withOpacity(0.15),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _isHappyState ? Colors.pinkAccent.withOpacity(0.2) : Colors.black.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              _dialogText!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ).animate().fadeIn(duration: 200.ms).scaleXY(begin: 0.8, end: 1.0),
                        ),

                      // 金黃色/霓虹光圈 (Happy 狀態下)
                      Positioned(
                        top: size.height * 0.08,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.01),
                            boxShadow: [
                              BoxShadow(
                                color: _isHappyState 
                                    ? Colors.pinkAccent.withOpacity(0.25)
                                    : Colors.cyanAccent.withOpacity(0.05),
                                blurRadius: _isHappyState ? 35 : 20,
                                spreadRadius: _isHappyState ? 8 : 2,
                              ),
                            ],
                          ),
                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                         .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms),
                      ),

                      // 2D 小豬圖片
                      Positioned(
                        top: size.height * 0.09,
                        child: Hero(
                          tag: 'desktop_pet',
                          child: Image.asset(
                            _isHappyState ? 'assets/images/pig_2d_happy_v4.png' : widget.assetPath,
                            height: 160,
                            fit: BoxFit.contain,
                          ),
                        ).animate(
                          target: _isHappyState ? 1.0 : 0.0,
                          onPlay: (c) => c.repeat(reverse: true)
                        ).moveY(
                          begin: 0,
                          end: -8,
                          duration: 1200.ms,
                          curve: Curves.easeInOutSine,
                        ).animate(target: _isHappyState ? 1.0 : 0.0)
                         .shake(hz: 3, rotation: 0.02),
                      ),
                    ],
                  ),
                ),

                // 養成資訊面板卡片 (毛玻璃)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildGlassCard(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "小豬皮皮",
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "今日狀態：${_getMoodText(widget.mood)}",
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.pinkAccent, Colors.purpleAccent],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.pinkAccent.withOpacity(0.4),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    "等級 $_level",
                                    style: GoogleFonts.orbitron(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),

                            // 養成數值進度條
                            _buildNeonProgressBar(
                              label: "飽食度 (肚子值)",
                              value: _hunger,
                              colors: [Colors.cyan, Colors.blueAccent],
                              icon: Icons.restaurant,
                              glowColor: Colors.cyanAccent,
                            ),
                            
                            const SizedBox(height: 18),

                            _buildNeonProgressBar(
                              label: "親密度 (愛心值)",
                              value: _intimacy,
                              colors: [Colors.pinkAccent, Colors.redAccent],
                              icon: Icons.favorite,
                              glowColor: Colors.pinkAccent,
                            ),

                            const SizedBox(height: 24),

                            // 數據展示卡片
                            Row(
                              children: [
                                _buildNeonStatCard(
                                  label: "今日步數",
                                  value: _steps.toString(),
                                  icon: Icons.directions_walk,
                                  color: Colors.cyanAccent,
                                ),
                                const SizedBox(width: 14),
                                _buildNeonStatCard(
                                  label: "契合天數",
                                  value: "15 天",
                                  icon: Icons.bolt,
                                  color: Colors.pinkAccent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 投餵區下方留空以容納發射底座與蘋果
                SizedBox(height: size.height * 0.16),
              ],
            ),
          ),

          // 投餵區底座
          Positioned(
            left: size.width / 2 - 40,
            bottom: 120,
            child: IgnorePointer(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.2), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.cyanAccent.withOpacity(0.03),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.1), width: 1),
                    ),
                    child: const Icon(Icons.arrow_upward, color: Colors.cyanAccent, size: 24),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .moveY(begin: 3, end: -3, duration: 1.seconds),
                ),
              ),
            ),
          ),

          // 滑動投餵蘋果提示文字
          if (!_isDragging && !_isFlying)
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    "▲ 向上滑動蘋果投餵小豬 ▲",
                    style: GoogleFonts.notoSansTc(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .fadeIn(duration: 1.seconds)
                   .then()
                   .fadeOut(duration: 1.seconds),
                ),
              ),
            ),

          // 愛心粒子特效繪製
          ..._particles.map((p) => Positioned(
            left: p.position.dx - 12,
            top: p.position.dy - 12,
            child: Opacity(
              opacity: p.opacity,
              child: Transform.scale(
                scale: p.scale,
                child: Icon(
                  Icons.favorite,
                  color: p.color,
                  size: 24,
                ),
              ),
            ),
          )),

          // 投餵蘋果本體 (可拖曳與飛行的元件)
          Positioned(
            left: _applePos.dx,
            top: _applePos.dy,
            child: GestureDetector(
              onPanStart: (details) {
                if (_isFlying) return;
                HapticFeedback.lightImpact();
                setState(() {
                  _isDragging = true;
                });
              },
              onPanUpdate: (details) {
                if (_isFlying) return;
                setState(() {
                  _applePos += details.delta;
                });
              },
              onPanEnd: _onPanEnd,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(_isDragging ? 0.5 : 0.3),
                      blurRadius: _isDragging ? 18 : 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    "🍎",
                    style: TextStyle(fontSize: 28),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _TrajectoryPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    double dashWidth = 5.0;
    double dashSpace = 4.0;
    double distance = (end - start).distance;
    
    if (distance == 0) return;

    Offset direction = (end - start) / distance;
    double currentDist = 0.0;
    
    while (currentDist < distance) {
      canvas.drawLine(
        start + direction * currentDist,
        start + direction * (currentDist + dashWidth),
        paint,
      );
      currentDist += dashWidth + dashSpace;
    }
    
    // 繪製拉力環
    canvas.drawCircle(start, 5, Paint()..color = Colors.cyanAccent.withOpacity(0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
