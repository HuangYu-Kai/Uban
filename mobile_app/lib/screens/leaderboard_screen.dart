import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
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
  int _currentSteps = 0;
  int _bufferedSteps = 0; // 用於後端同步的緩存
  int _sessionSteps = 0;  // 用於本次行走期間的緩存 (靜止後才更新介面)
  Timer? _syncTimer;
  String _pedestrianStatus = '靜止';
  late Stream<StepCount> _stepCountStream;
  late Stream<PedestrianStatus> _pedestrianStatusStream;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _initPedometer();
    _startSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _flushSteps();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _flushSteps();
    });
  }

  Future<void> _flushSteps() async {
    if (_bufferedSteps > 0) {
      final stepsToSync = _bufferedSteps;
      _bufferedSteps = 0;
      try {
        await _gameService.updateSteps(widget.elderId, stepsToSync);
        debugPrint('Successfully synced $stepsToSync steps');
      } catch (e) {
        _bufferedSteps += stepsToSync; // Put back if failed
        debugPrint('Failed to sync steps: $e');
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
            // 關鍵修正：避免步數倒退。如果伺服器回傳的步數小於本地已累積的步數，則保留本地數值。
            final int serverSteps = statusData['step_total'] ?? 0;
            final int localSteps = _elderStatus!['step_total'] ?? 0;
            
            // 更新非步數相關欄位
            _elderStatus!['elder_name'] = statusData['elder_name'];
            _elderStatus!['gawa_id'] = statusData['gawa_id'];
            _elderStatus!['gawa_name'] = statusData['gawa_name'];
            _elderStatus!['feed_starttime'] = statusData['feed_starttime'];
            
            if (serverSteps > localSteps) {
              _elderStatus!['step_total'] = serverSteps;
              _elderStatus!['level'] = getLevelFromSteps(serverSteps);
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
    
    // 強制同步：從排行榜中找到自己的資料，輔助校正本地數據 (取較大值)
    final me = _leaderboard.firstWhere(
      (e) => e['elder_id'] == widget.elderId, 
      orElse: () => <String, dynamic>{}
    );
    
    if (me.isNotEmpty) {
      final int leaderboardSteps = me['step_total'] ?? 0;
      final int currentSteps = _elderStatus!['step_total'] ?? 0;
      
      if (leaderboardSteps > currentSteps) {
        _elderStatus!['step_total'] = leaderboardSteps;
        _elderStatus!['level'] = getLevelFromSteps(leaderboardSteps);
      }
    }
  }

  void _initPedometer() async {
    try {
      if (await Permission.activityRecognition.request().isGranted) {
        _pedestrianStatusStream = Pedometer.pedestrianStatusStream;
        _pedestrianStatusStream.listen((event) {
          if (mounted) {
            final newStatus = event.status == 'walking' ? '行走中' : '靜止';
            // 如果從「行走中」變成「靜止」，則把這一段路程的步數更新到介面上
            if (_pedestrianStatus == '行走中' && newStatus == '靜止') {
              _updateUIFromSession();
            }
            setState(() => _pedestrianStatus = newStatus);
          }
        }).onError((error) {
          debugPrint('Pedestrian Status error: $error');
          if (mounted) setState(() => _pedestrianStatus = '感測器不支援');
        });

        _stepCountStream = Pedometer.stepCountStream;
        _stepCountStream.listen((event) {
          if (mounted) {
            int added = event.steps - _currentSteps;
            if (_currentSteps != 0 && added > 0) {
              _bufferedSteps += added;
              _sessionSteps += added;
              
              // 行走時即時更新上方進度條數字 (User Request 1)
              setState(() {
                if (_elderStatus != null) {
                  _elderStatus!['step_total'] = (_elderStatus!['step_total'] ?? 0) + added;
                  _elderStatus!['level'] = getLevelFromSteps(_elderStatus!['step_total']);
                }
              });

              // 依然保持背景同步邏輯 (每 50 步上傳一次)
              if (_bufferedSteps >= 50) {
                _flushSteps();
              }
            }
            _currentSteps = event.steps;
          }
        }).onError((error) {
          debugPrint('Step Count error: $error');
          if (mounted) setState(() => _pedestrianStatus = '感測器不支援');
        });
      }
    } catch (e) {
      debugPrint('Pedometer init error: $e');
      if (mounted) setState(() => _pedestrianStatus = '初始化失敗');
    }
  }

  Future<void> _updateUIFromSession() async {
    // 當狀態變成靜止時，同步更新排行榜內容 (User Request 1)
    await _flushSteps();  // 務必等待上傳完成 (User Request 2 - 解決非同步導致的步數倒退與延遲)
    await _fetchInitialData(); // 重新抓取資料，確保排名是更新後的結果
    _sessionSteps = 0;    // 重置 session 緩存
  }

  // 模擬走路功能 (僅用於測試或感測器不支援時)
  void _simulateSteps(int amount) {
    setState(() {
      _bufferedSteps += amount;
      if (_elderStatus != null) {
        _elderStatus!['step_total'] = (_elderStatus!['step_total'] ?? 0) + amount;
        _elderStatus!['level'] = getLevelFromSteps(_elderStatus!['step_total']);
      }
    });
    if (_bufferedSteps >= 50) _flushSteps();
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lv.$level', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.pinkAccent)),
                  Text('我的狀態: $_pedestrianStatus', style: TextStyle(color: _pedestrianStatus == '行走中' ? Colors.green : Colors.grey)),
                  if (_pedestrianStatus == '感測器不支援' || _pedestrianStatus == '初始化失敗') 
                    TextButton.icon(
                      onPressed: () => _simulateSteps(100),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('點擊模擬 100 步', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), foregroundColor: Colors.pinkAccent),
                    ),
                ],
              ),
              const Icon(Icons.stars, color: Colors.amber, size: 40),
            ],
          ),
          const SizedBox(height: 20),
          
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
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, size: 80, color: Colors.pink),
                ),
              );
            },
          ),
          
          const SizedBox(height: 30),
          
          // 經驗條
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('成長進度', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('$xp / $nextXp 步', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.pinkAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTile(Map<String, dynamic> entry, int index, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isMe ? Colors.pink.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isMe ? Border.all(color: Colors.pinkAccent, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: ListTile(
        leading: _buildRankBadge(index + 1),
        title: Text(entry['elder_name'] ?? '神秘使用者', style: const TextStyle(fontWeight: FontWeight.bold)),
        // 將步數縮小變淡放在 Subtitle
        subtitle: Text('${entry['step_total'] ?? 0} 步', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 將等級換算套用在排行榜列表中
            Text('Lv.${getLevelFromSteps(entry['step_total'] ?? 0)}', 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
            // 造型小圖
            const Icon(Icons.pets, size: 14, color: Colors.pinkAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Color color = Colors.grey;
    if (rank == 1) color = Colors.amber;
    if (rank == 2) color = Colors.blueGrey.shade300;
    if (rank == 3) color = Colors.brown.shade300;

    return Container(
      width: 35, height: 35,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Text('$rank', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
    );
  }
}

