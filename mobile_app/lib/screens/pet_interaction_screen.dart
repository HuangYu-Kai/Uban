import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'dart:async';
import '../widgets/flying_food.dart';
import '../widgets/desktop_pet.dart';

class PetInteractionScreen extends StatefulWidget {
  final int userId;
  final int steps;
  final int level;
  final PetMood mood;
  final String assetPath;

  const PetInteractionScreen({
    super.key,
    required this.userId,
    required this.steps,
    required this.level,
    required this.mood,
    required this.assetPath,
  });

  @override
  State<PetInteractionScreen> createState() => _PetInteractionScreenState();
}

class _PetInteractionScreenState extends State<PetInteractionScreen> {
  final List<Widget> _foodAnimations = [];
  final GlobalKey _pigKey = GlobalKey();
  final Random _random = Random();
  
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _userAccelSubscription;
  
  final ValueNotifier<Offset> _viewOffset = ValueNotifier(Offset.zero);

  String _currentDialog = "嘎挖！我在這裡！快轉動手機找找我～🐷";
  PetState _interactionState = PetState.idle;
  DateTime _lastShakeTime = DateTime.now();

  // 小豬在房間內的座標 (相對於 3200x2400 的畫布)
  Offset _petRoomPos = const Offset(1600, 1500); // 初始在地毯中心
  final Offset _sofaPos = const Offset(600, 1400);
  final Offset _tablePos = const Offset(2600, 1500);
  final Offset _rugPos = const Offset(1600, 1500);

  @override
  void initState() {
    super.initState();
    
    // 設定感應器頻率為 UI 等級 (約 60Hz)
    // 注意：sensors_plus 7.0+ 建議設定間隔

    // 1. 搖一搖 (設定 50Hz 頻率)
    _userAccelSubscription = userAccelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).listen((UserAccelerometerEvent event) {
      if (!mounted) return;
      double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (acceleration > 15 && DateTime.now().difference(_lastShakeTime).inMilliseconds > 1000) {
        _lastShakeTime = DateTime.now();
        _onShake();
      }
    });

    // 2. 陀螺儀 (設定 50Hz 頻率)
    _gyroSubscription = gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 20)).listen((GyroscopeEvent event) {
      if (!mounted) return;
      
      // 解封 Y 軸 (上下) 移動範圍
      double newX = (_viewOffset.value.dx - event.y * 20).clamp(-1500.0, 1500.0);
      double newY = (_viewOffset.value.dy - event.x * 15).clamp(-1000.0, 1000.0);
      
      _viewOffset.value = Offset(newX, newY);
    });
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
    _userAccelSubscription?.cancel();
    _viewOffset.dispose();
    super.dispose();
  }

  void _onShake() {
    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () => _spawnFood(isShower: true));
    }
    setState(() {
      _currentDialog = "嘎挖！搖一搖好多好吃的！🤩";
      _interactionState = PetState.happy;
    });
  }

  void _onFlick(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
      _spawnFood();
    }
  }

  void _spawnFood({bool isShower = false}) {
    HapticFeedback.mediumImpact();
    final RenderBox? renderBox = _pigKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final pigSize = renderBox.size;
    final pigPos = renderBox.localToGlobal(Offset.zero);
    final targetPos = Offset(pigPos.dx + pigSize.width / 2, pigPos.dy + pigSize.height / 2);

    final startPos = isShower 
      ? Offset(_random.nextDouble() * MediaQuery.of(context).size.width, -50)
      : Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height - 100);
    
    final animationId = DateTime.now().millisecondsSinceEpoch + _random.nextInt(1000);
    final foods = ['🍎', '🍌', '🍙', '🍪', '🍵', '🍊'];
    final selectedFood = foods[_random.nextInt(foods.length)];

    setState(() {
      _foodAnimations.add(
        FlyingFood(
          key: ValueKey(animationId),
          startPos: startPos,
          endPos: targetPos,
          foodEmoji: selectedFood,
          onComplete: () {
            setState(() {
              _foodAnimations.removeWhere((w) => w.key == ValueKey(animationId));
              _interactionState = PetState.happy;
              _currentDialog = isShower ? "嘎挖！接到了！😋" : "嘎挖！謝謝招待！🐷";
            });
            HapticFeedback.lightImpact();
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _interactionState = PetState.idle);
            });
          },
        ),
      );
    });
  }

  String _getPetAsset() {
    switch (_interactionState) {
      case PetState.happy: return 'assets/images/pig_2d_happy_v4.png';
      case PetState.pickedUp: return 'assets/images/pig_2d_picked_v5.png';
      default: return 'assets/images/pig_2d_idle_v4.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ValueListenableBuilder<Offset>(
            valueListenable: _viewOffset,
            builder: (context, offset, child) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenW = constraints.maxWidth;
                        final screenH = constraints.maxHeight;
                        
                        // 設定更大比例的畫布 (3200x2400) 以支援更多上下位移
                        const canvasW = 3200.0;
                        const canvasH = 2400.0;
                        
                        final maxDx = (canvasW - screenW) / 2;
                        final maxDy = (canvasH - screenH) / 2;
                        
                        return Transform.translate(
                          offset: Offset(
                            -maxDx - offset.dx.clamp(-maxDx, maxDx), 
                            -maxDy - offset.dy.clamp(-maxDy, maxDy)
                          ),
                          child: OverflowBox(
                            minWidth: canvasW,
                            maxWidth: canvasW,
                            minHeight: canvasH,
                            maxHeight: canvasH,
                            alignment: Alignment.topLeft,
                            child: Stack(
                              children: [
                                // 背景圖
                                Image.asset(
                                  'assets/images/pet_room_panorama.png',
                                  width: canvasW,
                                  height: canvasH,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                ),

                                // 家具互動區域 (修正座標)
                                Positioned(
                                  left: 400, top: 1300,
                                  child: _buildHotspot("沙發", _sofaPos),
                                ),
                                Positioned(
                                  left: 2400, top: 1400,
                                  child: _buildHotspot("餐桌", _tablePos),
                                ),
                                Positioned(
                                  left: 1500, top: 1600,
                                  child: _buildHotspot("地毯", _rugPos),
                                ),

                                // 會跟著背景移動的小豬
                                AnimatedPositioned(
                                  duration: 1500.ms,
                                  curve: Curves.easeInOutCubic,
                                  left: _petRoomPos.dx - 110,
                                  top: _petRoomPos.dy - 110,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _interactionState = PetState.happy;
                                        _currentDialog = "嘎挖！找到我了！好舒服～🐷";
                                      });
                                    },
                                    child: Container(
                                      key: _pigKey,
                                      child: Image.asset(
                                        _getPetAsset(),
                                        width: 220,
                                        height: 220,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                  ),
                ],
              );
            },
          ),

          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.white54,
                child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
                ),
                child: Text(
                  _currentDialog,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ).animate().fadeIn().scale(),
            ),
          ),

          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: _onFlick,
            ),
          ),

          ..._foodAnimations,

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatCard("等級", "Lv.${widget.level}"),
                    const SizedBox(width: 20),
                    _buildStatCard("今日步數", "${widget.steps}"),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  "📱 轉動手機觀察房間 | 📳 搖晃降美食",
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15, 
                    color: Colors.white, 
                    shadows: [const Shadow(blurRadius: 10, color: Colors.black)]
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeOut(duration: 2.seconds),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotspot(String label, Offset target) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _petRoomPos = target;
          _interactionState = PetState.happy;
          _currentDialog = "嘎挖！我要去$label那邊玩！💨";
        });
        HapticFeedback.heavyImpact();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Column(
          children: [
            const Icon(Icons.touch_app, color: Colors.white, size: 30),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey[700])),
          Text(value, style: GoogleFonts.notoSansTc(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
        ],
      ),
    );
  }
}
