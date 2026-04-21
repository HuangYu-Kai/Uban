import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/game_service.dart';
import '../screens/leaderboard_screen.dart';

enum PetState { idle, walking, happy, sleeping }

class DesktopPet extends StatefulWidget {
  final int userId;
  final double bottomBarHeight;

  const DesktopPet({super.key, required this.userId, required this.bottomBarHeight});

  @override
  DesktopPetState createState() => DesktopPetState();
}

class DesktopPetState extends State<DesktopPet> {
  final GameService _gameService = GameService();
  final Random _random = Random();
  
  // Game Status
  int _level = 1;
  int _steps = 0;
  bool _isLoading = true;

  // Timers
  Timer? _fetchTimer;
  Timer? _stateTimer;
  Timer? _dialogTimer;
  Timer? _walkFrameTimer;

  // Pet Animation & State
  PetState _currentState = PetState.idle;
  int _walkFrame = 1;
  bool _isFacingLeft = true; 
  double _positionX = 20.0;
  double _positionY = 0.0;
  
  String? _currentDialog;

  final List<String> _idleDialogs = [
    '阿公阿嬤，\n今天天氣真好！',
    '要不要出去走走呀？',
    '多走路我才會長大喔！',
    '點我可以看目前等級！',
    '記得多喝水喔！',
    '我是小豬，\n我們一起變健康！',
  ];

  @override
  void initState() {
    super.initState();
    _fetchPetStatus();
    _fetchTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchPetStatus());
    _startStateMachine();
  }

  void _startStateMachine() {
    final duration = Duration(seconds: 8 + _random.nextInt(10));
    _stateTimer = Timer(duration, () {
      if (!mounted || _currentState == PetState.happy) return;
      
      final r = _random.nextDouble();
      if (r < 0.3) {
        _changeState(PetState.walking);
      } else if (r < 0.5) {
        _changeState(PetState.sleeping);
      } else {
        _changeState(PetState.idle);
      }
      _startStateMachine();
    });
  }

  void _changeState(PetState newState) {
    if (!mounted) return;
    
    // Stop walk frame timer if switching FROM walking
    if (_currentState == PetState.walking && newState != PetState.walking) {
      _walkFrameTimer?.cancel();
    }

    setState(() {
      _currentState = newState;
      
      if (newState == PetState.walking) {
        double targetX = 10.0 + _random.nextDouble() * 200.0; 
        _isFacingLeft = targetX > _positionX;
        _positionX = targetX;
        _positionY = 0.0;
        _currentDialog = null;
        
        // Start walk frame animation
        _walkFrameTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
          if (mounted) {
            setState(() {
              _walkFrame = _walkFrame == 1 ? 2 : 1;
            });
          }
        });
      } else if (newState == PetState.sleeping) {
        _isFacingLeft = true;
        _positionY = -5.0;
        _currentDialog = "Zzz...";
      } else if (newState == PetState.idle) {
        _positionY = 0.0;
        if (_random.nextBool()) _showRandomDialog();
        else _currentDialog = null;
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
      if (mounted && _currentState != PetState.sleeping) setState(() => _currentDialog = null);
    });
  }

  /// ★ 新增：讓外部（如 Heartbeat）控制小豬說話
  void say(String text, {PetState state = PetState.happy}) {
    if (!mounted) return;
    _stateTimer?.cancel();
    _dialogTimer?.cancel();
    _walkFrameTimer?.cancel();

    setState(() {
      _currentState = state;
      _currentDialog = text;
      _positionY = (state == PetState.happy) ? 20.0 : 0.0;
    });

    // 10 秒後恢復閒置
    _dialogTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _currentDialog = null;
          _positionY = 0.0;
        });
        _changeState(PetState.idle);
        _startStateMachine();
      }
    });
  }


  Future<void> _fetchPetStatus() async {
    try {
      final statusData = await _gameService.getElderStatus(widget.userId.toString());
      if (mounted) {
        setState(() {
          _steps = statusData['step_total'] ?? 0;
          _level = _getLevelFromSteps(_steps);
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

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _stateTimer?.cancel();
    _dialogTimer?.cancel();
    _walkFrameTimer?.cancel();
    super.dispose();
  }

  void _onPetTap() {
    HapticFeedback.lightImpact();
    _stateTimer?.cancel();
    _walkFrameTimer?.cancel();
    
    setState(() {
      _currentState = PetState.happy;
      _currentDialog = "噗嚕噗嚕！😆";
      _positionY = 20.0;
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LeaderboardScreen(elderId: widget.userId.toString()),
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
      case PetState.idle:
      default:
        return 'assets/images/pig_2d_idle_v4.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    return AnimatedPositioned(
      duration: _currentState == PetState.walking ? const Duration(seconds: 4) : const Duration(milliseconds: 600),
      curve: _currentState == PetState.walking ? Curves.linear : Curves.easeOutBack,
      right: _positionX,
      bottom: widget.bottomBarHeight + _positionY,
      child: Column(
        crossAxisAlignment: _isFacingLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentDialog != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(245),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: _isFacingLeft ? const Radius.circular(24) : const Radius.circular(4),
                  bottomRight: _isFacingLeft ? const Radius.circular(4) : const Radius.circular(24),
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
                ],
                border: Border.all(color: Colors.pink.withAlpha(80), width: 2),
              ),
              child: Text(
                _currentDialog!,
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF334155),
                ),
              ),
            ).animate().fadeIn(duration: 250.ms).scaleXY(begin: 0.6, end: 1.0, curve: Curves.easeOutBack),
          
          GestureDetector(
            onTap: _onPetTap,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(_getLevelScale(_level))
                ..rotateY(_isFacingLeft ? 0 : pi),
              child: Image.asset(
                _getPetAsset(),
                height: 90,
                errorBuilder: (c, e, s) => const Icon(Icons.pets, size: 60, color: Colors.pinkAccent),
              ),
            ).animate(
              target: _currentState == PetState.idle ? 1 : 0,
              onPlay: (c) => c.repeat(reverse: true)
            ).moveY(begin: -3, end: 3, duration: 1500.ms, curve: Curves.easeInOutSine),
          ),
        ],
      ),
    );
  }
}
