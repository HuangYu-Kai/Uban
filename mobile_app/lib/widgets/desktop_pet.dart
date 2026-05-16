import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/game_service.dart';
import '../screens/pet_interaction_screen.dart';

enum PetState { idle, walking, sleeping, happy, pickedUp }

enum PetMood { normal, energetic, lazy, tired }

class DesktopPet extends StatefulWidget {
  final int userId;
  final double bottomBarHeight;
  final Function(int)? onStepsChanged;

  const DesktopPet({
    super.key,
    required this.userId,
    this.bottomBarHeight = 100,
    this.onStepsChanged,
  });

  @override
  State<DesktopPet> createState() => DesktopPetState();
}

class DesktopPetState extends State<DesktopPet> {
  final Random _random = Random();
  final GameService _gameService = GameService();

  // States
  int _steps = 0;
  int _level = 1;
  bool _isLoading = true;

  // Timers
  Timer? _fetchTimer;
  Timer? _stateTimer;
  Timer? _dialogTimer;
  Timer? _walkFrameTimer;

  // Pet Animation & State
  PetState _currentState = PetState.idle;
  PetMood _currentMood = PetMood.normal;
  int _walkFrame = 1;
  bool _isFacingLeft = true;
  late double _positionX;
  late double _positionY;
  Duration _walkDuration = const Duration(seconds: 4);

  String? _currentDialog;

  final List<String> _idleDialogs = [
    '阿公阿嬤，\n今天天氣真好！嘎挖！',
    '要不要出去走走呀？嘎挖嘎挖～',
    '多走路我才會變強壯喔！嘎挖！',
    '點我可以看我的收藏！嘎挖～',
    '記得多喝水喔！嘎挖嘎挖！',
    '我是小豬，\n我們一起變健康！嘎挖！',
    '肚子有點餓了...嘎挖！',
  ];


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(
        const AssetImage('assets/images/pig_2d_idle_v4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pig_2d_walk_1_v4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pig_2d_walk_2_v4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pig_2d_happy_v4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pig_2d_sleep_v4.png'), context);
    precacheImage(
        const AssetImage('assets/images/pig_2d_picked_v5.png'), context);
  }

  @override
  void initState() {
    super.initState();
    // 初始位置隨機化 (全螢幕範圍)
    _positionX = 20.0 + _random.nextDouble() * 250.0;
    _positionY = 50.0 + _random.nextDouble() * 300.0;
    _isFacingLeft = _random.nextBool();

    _fetchPetStatus();
    _fetchTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetchPetStatus());
    _startStateMachine();
  }

  void _startStateMachine() {
    final duration = Duration(seconds: 8 + _random.nextInt(10));
    _stateTimer = Timer(duration, () {
      if (!mounted ||
          _currentState == PetState.happy ||
          _currentState == PetState.pickedUp) {
        return;
      }

      final r = _random.nextDouble();

      // 根據心情調整狀態機率
      if (_currentMood == PetMood.lazy || _currentMood == PetMood.tired) {
        if (r < 0.2) {
          _changeState(PetState.walking);
        } else if (r < 0.7) {
          _changeState(PetState.sleeping);
        } else {
          _changeState(PetState.idle);
        }
      } else if (_currentMood == PetMood.energetic) {
        if (r < 0.6) {
          _changeState(PetState.walking);
        } else if (r < 0.8) {
          _changeState(PetState.idle);
        } else {
          _changeState(PetState.sleeping);
        }
      } else {
        if (r < 0.4) {
          _changeState(PetState.walking);
        } else if (r < 0.6) {
          _changeState(PetState.sleeping);
        } else {
          _changeState(PetState.idle);
        }
      }
      _startStateMachine();
    });
  }

  void _changeState(PetState newState) {
    if (!mounted) return;

    if (_currentState == PetState.walking && newState != PetState.walking) {
      _walkFrameTimer?.cancel();
    }

    setState(() {
      _currentState = newState;

      if (newState == PetState.walking) {
        // 全螢幕隨機走位
        double targetX = 10.0 + _random.nextDouble() * 280.0;
        double targetY = 20.0 + _random.nextDouble() * 450.0;

        double distance =
            sqrt(pow(targetX - _positionX, 2) + pow(targetY - _positionY, 2));

        // 根據心情調整步速
        double speed = 45.0; // 預設 45px/s
        if (_currentMood == PetMood.energetic) speed = 65.0;
        if (_currentMood == PetMood.lazy) speed = 25.0;
        if (_currentMood == PetMood.tired) speed = 35.0;

        _walkDuration =
            Duration(milliseconds: (distance / speed * 1000).toInt());

        _isFacingLeft = targetX < _positionX;
        _positionX = targetX;
        _positionY = targetY;
        _currentDialog = null;

        _walkFrameTimer?.cancel();
        _walkFrameTimer =
            Timer.periodic(const Duration(milliseconds: 250), (timer) {
          if (mounted) setState(() => _walkFrame = _walkFrame == 1 ? 2 : 1);
        });
      } else if (newState == PetState.sleeping) {
        _isFacingLeft = true;
        _currentDialog = "Zzz...";
      } else if (newState == PetState.idle) {
        if (_random.nextBool()) {
          _showRandomDialog();
        } else {
          _currentDialog = null;
        }
      }
    });
  }

  void _showRandomDialog() {
    if (!mounted) return;
    setState(() {
      _currentDialog = _idleDialogs[_random.nextInt(_idleDialogs.length)];
    });
    _dialogTimer?.cancel();
    _dialogTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _currentState != PetState.sleeping) {
        setState(() => _currentDialog = null);
      }
    });
  }

  void say(String text, {PetState state = PetState.happy}) {
    if (!mounted) return;
    _stateTimer?.cancel();
    _dialogTimer?.cancel();
    _walkFrameTimer?.cancel();

    setState(() {
      _currentState = state;
      _currentDialog = text;
    });

    _dialogTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _currentDialog = null);
        _changeState(PetState.idle);
        _startStateMachine();
      }
    });
  }

  Future<void> _fetchPetStatus() async {
    try {
      final statusData =
          await _gameService.getElderStatus(widget.userId.toString());
      if (mounted) {
        setState(() {
          _steps = statusData['step_total'] ?? 0;
          _level = _getLevelFromSteps(_steps);
          widget.onStepsChanged?.call(_steps);

          // 計算心情
          final hour = DateTime.now().hour;
          if (_steps > 8000) {
            _currentMood = PetMood.tired;
          } else if (_steps > 3000) {
            _currentMood = PetMood.energetic;
          } else if (hour >= 14 && _steps < 500) {
            _currentMood = PetMood.lazy;
          } else {
            _currentMood = PetMood.normal;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _getLevelFromSteps(int steps) {
    if (steps <= 1000) return 1;
    if (steps <= 20000) return 2;
    if (steps <= 50000) return 3;
    if (steps <= 150000) return 4;
    if (steps <= 300000) return 5;
    if (steps <= 700000) return 6;
    if (steps <= 1000000) return 7;
    return 8;
  }

  double _getLevelScale(int level) => 0.8 + (level * 0.1);

  Offset getPetCenter() {
    // 獲取 RenderBox 來精確定位中心點
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final size = renderBox.size;
      final position = renderBox.localToGlobal(Offset.zero);
      return Offset(position.dx + size.width / 2, position.dy + size.height / 2);
    }
    return Offset.zero;
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _stateTimer?.cancel();
    _dialogTimer?.cancel();
    _walkFrameTimer?.cancel();
    super.dispose();
  }

  double _dragStartX = 0;
  double _dragStartY = 0;

  void _onPetTap() {
    if (_currentState == PetState.pickedUp) return;
    HapticFeedback.lightImpact();
    _stateTimer?.cancel();
    _walkFrameTimer?.cancel();

    setState(() {
      _currentState = PetState.happy;
      _currentDialog = "嘎挖！嘎挖嘎挖！😆";
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PetInteractionScreen(
            userId: widget.userId,
            steps: _steps,
            level: _level,
            mood: _currentMood,
            assetPath: _getPetAsset(),
          ),
        ),
      ).then((_) {
        _fetchPetStatus();
        _changeState(PetState.idle);
        _startStateMachine();
      });
    });
  }

  String _getPetAsset() {
    switch (_currentState) {
      case PetState.walking:
        return 'assets/images/pig_2d_walk_${_walkFrame}_v4.png';
      case PetState.sleeping:
        return 'assets/images/pig_2d_sleep_v4.png';
      case PetState.happy:
        return 'assets/images/pig_2d_happy_v4.png';
      case PetState.pickedUp:
        return 'assets/images/pig_2d_picked_v5.png';
      case PetState.idle:
        return 'assets/images/pig_2d_idle_v4.png';
    }
  }

  Widget _buildMoodBadge(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.pink.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSansTc(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.pinkAccent,
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.5, end: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    return AnimatedPositioned(
      duration: (_currentState == PetState.walking)
          ? _walkDuration
          : (_currentState == PetState.pickedUp
              ? Duration.zero
              : const Duration(milliseconds: 600)),
      curve: _currentState == PetState.walking
          ? Curves.linear
          : Curves.easeOutBack,
      right: _positionX,
      bottom: widget.bottomBarHeight + _positionY,
      child: GestureDetector(
        onLongPressStart: (details) {
          HapticFeedback.mediumImpact();
          _stateTimer?.cancel();
          _walkFrameTimer?.cancel();
          _dragStartX = _positionX;
          _dragStartY = _positionY;
          setState(() {
            _currentState = PetState.pickedUp;
            _currentDialog = "哎呀！被抓住了！";
          });
        },
        onLongPressMoveUpdate: (details) {
          setState(() {
            // 修正：使用起始位置加上位移量，並限制邊界 (0 ~ 300 邏輯像素)
            // 因為是 right，手指往左走 (dx < 0)，right 應該要增加
            _positionX =
                (_dragStartX - details.offsetFromOrigin.dx).clamp(0.0, 280.0);
            // 因為是 bottom，手指往上走 (dy < 0)，bottom 應該要增加
            _positionY =
                (_dragStartY - details.offsetFromOrigin.dy).clamp(0.0, 500.0);
          });
        },
        onLongPressEnd: (details) {
          HapticFeedback.heavyImpact();
          setState(() {
            _currentState = PetState.idle;
            _currentDialog = "呼... 嚇我一跳！";
          });
          _startStateMachine();
        },
        onTap: _onPetTap,
        child: Column(
          crossAxisAlignment:
              _isFacingLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentMood == PetMood.energetic) _buildMoodBadge("活力百倍 ✨"),
            if (_currentMood == PetMood.lazy) _buildMoodBadge("想去散步 👣"),
            if (_currentMood == PetMood.tired) _buildMoodBadge("休息時間 💤"),
            if (_currentDialog != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(24),
                    topRight: const Radius.circular(24),
                    bottomLeft: _isFacingLeft
                        ? const Radius.circular(24)
                        : const Radius.circular(4),
                    bottomRight: _isFacingLeft
                        ? const Radius.circular(4)
                        : const Radius.circular(24),
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 4)),
                  ],
                  border: Border.all(
                      color: Colors.pink.withValues(alpha: 0.3), width: 2),
                ),
                child: Text(
                  _currentDialog!,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF334155),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 250.ms)
                  .scaleXY(begin: 0.6, end: 1.0, curve: Curves.easeOutBack),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scaleByDouble(
                    _getLevelScale(_level) *
                        (_currentState == PetState.pickedUp ? 1.2 : 1.0),
                    _getLevelScale(_level) *
                        (_currentState == PetState.pickedUp ? 1.2 : 1.0),
                    1.0,
                    1.0)
                ..rotateY(_isFacingLeft ? 0 : pi)
                ..rotateZ(_currentState == PetState.pickedUp ? 0.15 : 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 活力模式的金色光圈
                  if (_currentMood == PetMood.energetic)
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                    ).animate(onPlay: (c) => c.repeat()).scaleXY(
                        begin: 0.8,
                        end: 1.2,
                        duration: 1.seconds,
                        curve: Curves.easeInOut),

                  Hero(
                    tag: 'desktop_pet',
                    child: Image.asset(
                      _getPetAsset(),
                      height: 90,
                      errorBuilder: (c, e, s) => const Icon(Icons.pets,
                          size: 50, color: Colors.pinkAccent),
                    ),
                  ),
                ],
              ),
            )
                .animate(
                    target: (_currentState == PetState.idle ||
                            _currentState == PetState.happy)
                        ? 1
                        : 0,
                    onPlay: (c) => c.repeat(reverse: true))
                .moveY(
                    begin: -3,
                    end: 3,
                    duration: 1500.ms,
                    curve: Curves.easeInOutSine)
                // 拎起時的掙扎動畫
                .animate(target: _currentState == PetState.pickedUp ? 1 : 0)
                .shake(hz: 8, curve: Curves.easeInOut, rotation: 0.05)
                .scaleXY(
                    begin: 1.0,
                    end: 1.1,
                    duration: 250.ms,
                    curve: Curves.elasticOut),
          ],
        ),
      ),
    );
  }
}
