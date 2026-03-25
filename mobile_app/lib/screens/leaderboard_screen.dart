import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _collectionData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final leaderboardData = await _gameService.getLeaderboard(widget.elderId);
      final collectionData = await _gameService.getElderCollection(widget.elderId);
      
      if (mounted) {
        setState(() {
          _leaderboard = leaderboardData;
          _collectionData = collectionData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的排行榜與收集', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: kToolbarHeight + 20),
                  // --- 收集進度與加成 ---
                  _buildCollectionSection(),
                  
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('好友排行榜', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                  
                  // --- 排行榜 ---
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _leaderboard.length,
                      itemBuilder: (context, index) {
                        final entry = _leaderboard[index];
                        final isMe = entry['elder_id'] == widget.elderId;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.teal.withOpacity(0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                            border: isMe ? Border.all(color: Colors.teal, width: 2) : null,
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: _getRankColor(entry['rank'] ?? index + 1), shape: BoxShape.circle),
                              child: Center(
                                child: Text('${entry['rank'] ?? index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            title: Text(
                              entry['elder_name'] ?? '長輩 ${entry['elder_id']}', // 💡 使用長輩名稱
                              style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal, color: isMe ? Colors.teal : Colors.black87),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID: ${entry['elder_id']}'),
                                Text(
                                  'Gawa 經驗: ${entry['gawa_xp'] ?? 0} XP',
                                  style: const TextStyle(fontSize: 12, color: Colors.teal),
                                ),
                                Text(
                                  '成長倍率: x${(1.0 + ((entry['gawa_xp'] ?? 0) / 1000.0) * 0.05).toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${entry['step_total']} 步',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                                ),
                                const Icon(Icons.pets, size: 16, color: Colors.teal),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
  
  Widget _buildCollectionSection() {
    if (_collectionData == null) return const SizedBox.shrink();
    final double totalBonus = _collectionData!['total_bonus'] ?? 0.0;
    final List collection = _collectionData!['collection'] ?? [];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('目前造型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              Text('目前加成: ${(totalBonus * 100).toStringAsFixed(1)}%', 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 12),
          if (collection.isEmpty)
            const Text('尚未擁有任何造型。', style: TextStyle(color: Colors.grey))
          else
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: collection.length,
                itemBuilder: (context, index) {
                  final app = collection[index];
                  return Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.pets, color: Colors.teal, size: 30),
                        const SizedBox(height: 8),
                        Text(app['gawa_name'] ?? '造型', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        Text('+${((app['bonus'] ?? 0) * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.green)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return Colors.amber;
    if (rank == 2) return Colors.grey;
    if (rank == 3) return Colors.brown;
    return Colors.teal.shade200;
  }
}
