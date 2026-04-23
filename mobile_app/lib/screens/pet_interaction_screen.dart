import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'dart:async';
import '../widgets/flying_food.dart';
import '../widgets/desktop_pet.dart';
import '../services/api_service.dart';

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
  bool _isAILoading = false;

  // 小豬在房間內的座標 (相對於 3200x2400 的畫布)
  Offset _petRoomPos = const Offset(1600, 1600); 
  final Offset _sofaPos = const Offset(1100, 1550);   // 沙發中心
  final Offset _tablePos = const Offset(2600, 1600);  // 右側餐桌/窗邊
  final Offset _rugPos = const Offset(1600, 1900);    // 沙發前的地毯
  final Offset _radioPos = const Offset(500, 1500);   // 左側收音機/新聞

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

  Future<void> _fetchAIGreeting() async {
    if (_isAILoading) return;
    
    setState(() {
      _isAILoading = true;
      _currentDialog = "嘎挖... (思考中...)";
      _interactionState = PetState.idle;
    });

    try {
      final contextStr = "現在時間是 ${DateTime.now().hour}:${DateTime.now().minute}，長輩今天走了 ${widget.steps} 步。";
      final res = await ApiService.petGreeting(widget.userId, contextStr);

      if (res['status'] == 'success') {
        String aiText = res['data']['reply'].toString().trim();
        if (mounted) {
          setState(() {
            _currentDialog = aiText; // 後端已帶有「嘎挖！」
            _interactionState = PetState.happy;
            _isAILoading = false;
          });
        }
      } else {
        throw Exception("Backend error");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentDialog = "嘎挖！看到你真開心！🐷";
          _interactionState = PetState.happy;
          _isAILoading = false;
        });
      }
    }
  }

  Future<void> _playNews() async {
    setState(() {
      _currentDialog = "嘎挖！正在幫你找最新的新聞喔... 📻";
      _isAILoading = true;
    });
    
    try {
      final res = await ApiService.getNews(limit: 1);
      if (res['status'] == 'success' && res['data'] != null && (res['data'] as List).isNotEmpty) {
        final newsTitle = res['data'][0]['title'];
        if (mounted) {
          setState(() {
            _currentDialog = "嘎挖！今天的新聞是：$newsTitle";
            _isAILoading = false;
            _interactionState = PetState.happy;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentDialog = "嘎挖！收音機好像訊號不太好，晚點再試試吧～😅";
            _isAILoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentDialog = "嘎挖！網路斷掉了，聽不到新聞。";
          _isAILoading = false;
        });
      }
    }
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

                                // 家具互動區域 (完全透明，擴大範圍)
                                Positioned(
                                  left: 200, top: 1200,
                                  child: _buildHotspot("新聞", _radioPos, width: 600, height: 600),
                                ),
                                Positioned(
                                  left: 600, top: 1200,
                                  child: _buildHotspot("沙發", _sofaPos, width: 800, height: 600),
                                ),
                                Positioned(
                                  left: 2200, top: 1300,
                                  child: _buildHotspot("餐桌", _tablePos, width: 800, height: 600),
                                ),
                                Positioned(
                                  left: 1000, top: 1800,
                                  child: _buildHotspot("地毯", _rugPos, width: 1200, height: 400),
                                ),

                                // 會跟著背景移動的小豬
                                AnimatedPositioned(
                                  duration: 1500.ms,
                                  curve: Curves.easeInOutCubic,
                                  left: _petRoomPos.dx - 110,
                                  top: _petRoomPos.dy - 110,
                                  child: GestureDetector(
                                    onTap: _fetchAIGreeting,
                                    child: Container(
                                      key: _pigKey,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Image.asset(
                                            _getPetAsset(),
                                            width: 220,
                                            height: 220,
                                          ),
                                          if (_isAILoading)
                                            Positioned(
                                              top: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                                                child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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

  Widget _buildHotspot(String label, Offset target, {double width = 200, double height = 200}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _petRoomPos = target;
          _interactionState = PetState.happy;
          
          // 根據目標位置給予不同對話
          if (label == "沙發") {
            _currentDialog = "嘎挖！這沙發好軟喔，我想在這裡睡午覺～😴";
          } else if (label == "餐桌") {
            _currentDialog = "嘎挖！這裡可以看到風景耶！是不是要開飯了？😋";
          } else if (label == "新聞") {
            _playNews();
          } else {
            _currentDialog = "嘎挖！在寬敞的地毯上滾來滾去最開心了！🌀";
          }
        });
        HapticFeedback.mediumImpact();
        
        // 5秒後恢復閒置狀態
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) setState(() => _interactionState = PetState.idle);
        });
      },
      child: Container(
        width: width,
        height: height,
        color: Colors.transparent, // 完全透明但可點擊
        alignment: Alignment.center,
        // 開發調試時可以取消註釋下面這行來查看感應區
        // child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.red.withOpacity(0.3)))),
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
