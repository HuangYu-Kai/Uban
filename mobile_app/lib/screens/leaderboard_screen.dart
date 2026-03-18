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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final data = await _gameService.getLeaderboard(widget.elderId);
      setState(() {
        _leaderboard = data;
        _isLoading = false;
      });
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
        title: const Text('好友排行榜', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('排名', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                            Text('長輩名稱', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                            Text('累積步數', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: isMe ? Border.all(color: Colors.teal, width: 2) : null,
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _getRankColor(index),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            title: Text(
                              '長輩 ${entry['elder_id']}',
                              style: TextStyle(
                                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                color: isMe ? Colors.teal : Colors.black87,
                              ),
                            ),
                            subtitle: Text(entry['persona'] ?? '溫暖孫子'),
                            trailing: Text(
                              '${entry['step_total']}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orangeAccent,
                              ),
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

  Color _getRankColor(int index) {
    if (index == 0) return Colors.amber;
    if (index == 1) return Colors.grey;
    if (index == 2) return Colors.brown;
    return Colors.teal.shade200;
  }
}
