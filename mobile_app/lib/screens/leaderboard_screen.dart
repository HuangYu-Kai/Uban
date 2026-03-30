import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/game_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String elderId;
  const LeaderboardScreen({super.key, required this.elderId});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final GameService _gameService = GameService();
  List<Map<String, dynamic>> _leaderboard = [];
  Map<String, dynamic>? _elderStatus;
  bool _isLoading = true;

  // Pedometer logic
  int _unsyncedSteps = 0; // Persistent buffer for backend sync
  int _hardwareBaseSteps = -1; // Ground truth from physical pedometer
  
  bool _isFlushing = false; // Lock for database sync
  Timer? _syncTimer;
  String _pedestrianStatus = '靜止';
  late Stream<StepCount> _stepCountStream;
  
  // Timer for walking status inference
  Timer? _walkingTimer;

  @override
  void initState() {
    super.initState();
    _loadUnsyncedSteps(); // async non-blocking
    _fetchInitialData();
    _initPedometer();
    _startSyncTimer();
  }

  Future<void> _loadUnsyncedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _unsyncedSteps = prefs.getInt('unsynced_steps_${widget.elderId}') ?? 0;
    });
    if (_unsyncedSteps > 0) _flushSteps();
  }

  Future<void> _saveUnsyncedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unsynced_steps_${widget.elderId}', _unsyncedSteps);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _walkingTimer?.cancel();
    _flushSteps();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _flushSteps();
    });
  }

  Future<void> _flushSteps() async {
    if (_unsyncedSteps > 0 && !_isFlushing) {
      _isFlushing = true;
      final stepsToSync = _unsyncedSteps;
      try {
        await _gameService.updateSteps(widget.elderId, stepsToSync);
        debugPrint('Successfully synced $stepsToSync steps');
        _unsyncedSteps -= stepsToSync;
        await _saveUnsyncedSteps();
      } catch (e) {
        debugPrint('Failed to sync steps: $e');
      } finally {
        _isFlushing = false;
      }
    }
  }

  Future<void> _fetchInitialData() async {
    try {
      final leaderboardData = await _gameService.getLeaderboard(widget.elderId);
      final statusData = await _gameService.getElderStatus(widget.elderId);
      
      if (mounted) {
        setState(() {
          _leaderboard = leaderboardData;
          
          if (_elderStatus == null) {
            _elderStatus = statusData;
          } else {
            // 關鍵修正：避免步數倒退。伺服器步數加上尚未同步的步數，確保介面不倒退
            final int serverSteps = statusData['step_total'] ?? 0;
            final int localSteps = _elderStatus!['step_total'] ?? 0;
            
            // 更新非步數相關欄位
            _elderStatus!['elder_name'] = statusData['elder_name'];
            _elderStatus!['feed_starttime'] = statusData['feed_starttime'];
            
            // 由於 backend 尚未包含在 unsynced 內的步數，我們把伺服器真實步數 + 未同步的本地步數 作為真正總數
            final int computeSteps = serverSteps + _unsyncedSteps;
            
            if (computeSteps >= localSteps) {
              _elderStatus!['step_total'] = computeSteps;
              _elderStatus!['level'] = getLevelFromSteps(computeSteps);
            }
          }
          
          _syncWithLeaderboard();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Fetch Error: $e');
      }
    }
  }

  void _syncWithLeaderboard() {
    if (_leaderboard.isEmpty || _elderStatus == null) return;
    
    // 找出自己在排行榜中的資料
    final int meIndex = _leaderboard.indexWhere((e) => e['elder_id'] == widget.elderId);
    
    if (meIndex != -1) {
      final int leaderboardSteps = _leaderboard[meIndex]['step_total'] ?? 0;
      final int currentSteps = _elderStatus!['step_total'] ?? 0;
      
      // Bi-directional sync: 取較大值，確保兩邊都是最新
      final int maxSteps = leaderboardSteps > currentSteps ? leaderboardSteps : currentSteps;
      
      _elderStatus!['step_total'] = maxSteps;
      _elderStatus!['level'] = getLevelFromSteps(maxSteps);
      
      _leaderboard[meIndex]['step_total'] = maxSteps;
      _leaderboard[meIndex]['level'] = getLevelFromSteps(maxSteps);
      
      // 確保同步後，排行榜順序正確
      _leaderboard.sort((a, b) => (b['step_total'] ?? 0).compareTo(a['step_total'] ?? 0));
    }
  }

  void _initPedometer() async {
    try {
      if (await Permission.activityRecognition.request().isGranted) {
        _stepCountStream = Pedometer.stepCountStream;
        _stepCountStream.listen((event) {
          if (mounted) {
            // 初始化邏輯：如果是第一次收到數據，先記錄起始值，但不計入本次增加
            if (_hardwareBaseSteps == -1) {
              _hardwareBaseSteps = event.steps;
              debugPrint('Initial hardware steps: $_hardwareBaseSteps');
              return;
            }

            int hwDelta = event.steps - _hardwareBaseSteps;
            if (hwDelta > 0) {
              _unsyncedSteps += hwDelta;
              _saveUnsyncedSteps();
              
              setState(() {
                _pedestrianStatus = '行走中';
                if (_elderStatus != null) {
                   _elderStatus!['step_total'] = (_elderStatus!['step_total'] ?? 0) + hwDelta;
                   _elderStatus!['level'] = getLevelFromSteps(_elderStatus!['step_total']);
                }
              });

              _hardwareBaseSteps = event.steps;
              
              // 每次收到步數，重置判定為靜止的計時器 (3秒)
              _walkingTimer?.cancel();
              _walkingTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() => _pedestrianStatus = '靜止');
                  _updateUIFromSession();
                }
              });

              // 背景靜默同步 (每滿 50 步)
              if (_unsyncedSteps >= 50 && !_isFlushing) {
                _flushSteps();
              }
            }
          }
        }).onError((error) {
          debugPrint('Step Count error: $error');
          if (mounted) setState(() => _pedestrianStatus = '計步器受限');
        });
      }
    } catch (e) {
      debugPrint('Pedometer init error: $e');
    }
  }

  Future<void> _updateUIFromSession() async {
    // 當狀態變成靜止時，立刻同步更新本地排行榜數字 (樂觀更新)
    if (mounted) {
      setState(() {
        if (_elderStatus != null) {
          int currentTotal = _elderStatus!['step_total'] ?? 0;
          for (var i = 0; i < _leaderboard.length; i++) {
            if (_leaderboard[i]['elder_id'] == widget.elderId) {
              _leaderboard[i]['step_total'] = currentTotal;
              break;
            }
          }
          // 重新排序排行榜
          _leaderboard.sort((a, b) => (b['step_total'] ?? 0).compareTo(a['step_total'] ?? 0));
        }
      });
    }

    // 當狀態變成靜止時，同步更新排行榜內容
    await _flushSteps();  // 務必等待上傳完成
    await _fetchInitialData(); // 重新抓取資料，由於我們實作了 bi-directional 取最大值同步，不再可能倒退
  }

  // 模擬走路功能 (僅用於測試或感測器不支援時)
  void _simulateSteps(int amount) {
    setState(() {
      _unsyncedSteps += amount;
      _saveUnsyncedSteps();
      if (_elderStatus != null) {
        _elderStatus!['step_total'] = (_elderStatus!['step_total'] ?? 0) + amount;
        _elderStatus!['level'] = getLevelFromSteps(_elderStatus!['step_total']);
      }
    });
    if (_unsyncedSteps >= 50 && !_isFlushing) _flushSteps();
  }

  // Level Logic (Sync with Backend)
  int getLevelFromSteps(int steps) {
    if (steps <= 1000) return 1;
    if (steps <= 20000) return 2;
    if (steps <= 50000) return 3;
    if (steps <= 150000) return 4;
    if (steps <= 300000) return 5;
    if (steps <= 700000) return 6;
    if (steps <= 1000000) return 7;
    return 8;
  }

  int getLevelSteps(int level) {
    switch (level) {
      case 1: return 1000;
      case 2: return 20000;
      case 3: return 50000;
      case 4: return 150000;
      case 5: return 300000;
      case 6: return 700000;
      case 7: return 1000000;
      default: return 1000000;
    }
  }

  double getLevelScale(int level) {
    return 0.8 + (level * 0.2); // Lv1: 1.0, Lv8: 2.4
  }

  @override
  Widget build(BuildContext context) {
    // 使用 step_total 作為成長指標
    final int totalSteps = (_elderStatus?['step_total'] ?? 0);
    final int level = getLevelFromSteps(totalSteps);
    final int nextSteps = getLevelSteps(level);
    final double progress = (totalSteps / nextSteps).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('走路養小豬排行榜', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE0F2F1), Colors.white],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: kToolbarHeight + 10),
                  
                  // --- 養小豬重點區域 ---
                  _buildPigFeedingArea(level, totalSteps, nextSteps, progress),
                  
                  // --- 排行榜部分 ---
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('好友排行榜 (依等級排序)', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                  
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _leaderboard.length,
                      itemBuilder: (context, index) {
                        final entry = _leaderboard[index];
                        final isMe = entry['elder_id'] == widget.elderId;
                        return _buildLeaderboardTile(entry, index, isMe);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPigFeedingArea(int level, int xp, int nextXp, double progress) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.pinkAccent.withOpacity(0.15), blurRadius: 25, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('等級 ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('$level', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.pinkAccent)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _pedestrianStatus == '行走中' ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _pedestrianStatus == '行走中' ? Colors.green.shade200 : Colors.grey.shade300)
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _pedestrianStatus == '行走中' ? Icons.directions_walk : Icons.accessibility_new, 
                          size: 16, 
                          color: _pedestrianStatus == '行走中' ? Colors.green : Colors.grey.shade600
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '狀態: $_pedestrianStatus', 
                          style: TextStyle(
                            color: _pedestrianStatus == '行走中' ? Colors.green.shade700 : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 13
                          )
                        ),
                      ],
                    ),
                  ),
                  if (_pedestrianStatus == '感測器不支援' || _pedestrianStatus == '初始化失敗') 
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () => _simulateSteps(100),
                        icon: const Icon(Icons.add_circle, size: 18),
                        label: const Text('點擊模擬 100 步', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                          backgroundColor: Colors.pink.shade50,
                          foregroundColor: Colors.pinkAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                        ),
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 48),
              ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scaleXY(begin: 0.95, end: 1.05, duration: 1.seconds),
            ],
          ),
          const SizedBox(height: 30),
          
          // 小豬圖片 (根據等級縮放)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: getLevelScale(level)),
            duration: const Duration(seconds: 2),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Image.asset(
                  'assets/images/pig_mascot.png',
                  height: 120,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120, width: 120,
                    decoration: BoxDecoration(color: Colors.pink.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.pets, size: 60, color: Colors.pinkAccent),
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 35),
          
          // 經驗條
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('成長進度', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Row(
                    children: [
                      Text('$xp', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.pinkAccent, fontSize: 18)),
                      Text(' / $nextXp 步', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 16, // Increase height
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                  ),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.pinkAccent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().scale(duration: 400.milliseconds, curve: Curves.easeOutBack);
  }

  Widget _buildLeaderboardTile(Map<String, dynamic> entry, int index, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isMe ? Colors.pink.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isMe ? Border.all(color: Colors.pinkAccent.shade200, width: 2) : Border.all(color: Colors.transparent, width: 2),
        boxShadow: [
          BoxShadow(
            color: isMe ? Colors.pink.withOpacity(0.2) : Colors.black.withOpacity(0.04), 
            blurRadius: 15, 
            offset: const Offset(0, 5)
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: _buildRankBadge(index + 1),
        title: Text(entry['elder_name'] ?? '神秘使用者', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Row(
          children: [
            const Icon(Icons.directions_walk, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text('${entry['step_total'] ?? 0} 步', style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Lv.${getLevelFromSteps(entry['step_total'] ?? 0)}', 
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.deepOrange)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX(begin: 0.1, end: 0);
  }

  Widget _buildRankBadge(int rank) {
    Color color;
    Color iconColor = Colors.white;
    if (rank == 1) { color = Colors.amber; }
    else if (rank == 2) { color = Colors.blueGrey.shade300; }
    else if (rank == 3) { color = Colors.brown.shade300; }
    else { color = Colors.grey.shade200; iconColor = Colors.grey.shade700; }

    return Container(
      width: 45, height: 45,
      decoration: BoxDecoration(
        color: color, 
        shape: BoxShape.circle,
        boxShadow: rank <= 3 ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))] : null,
      ),
      child: Center(child: Text('$rank', style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 18))),
    );
  }
}

