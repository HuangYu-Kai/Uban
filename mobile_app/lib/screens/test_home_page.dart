import 'package:flutter/material.dart';
import '../services/game_service.dart';
import 'leaderboard_screen.dart';

class TestHomePage extends StatefulWidget {
  const TestHomePage({super.key});

  @override
  State<TestHomePage> createState() => _TestHomePageState();
}

class _TestHomePageState extends State<TestHomePage> {
  final GameService _gameService = GameService();
  final TextEditingController _idController = TextEditingController(text: 'E001');
  String _status = '等待操作...';

  Future<void> _handleDistribute() async {
    final elderId = _idController.text.trim();
    setState(() => _status = '正在為 $elderId 分配造型...');
    try {
      final result = await _gameService.distributeAppearances(elderId: elderId);
      setState(() => _status = '成功: ${result['message']}');
    } catch (e) {
      setState(() => _status = '失敗: $e');
    }
  }

  Future<void> _handleDistributeAll() async {
    setState(() => _status = '正在為所有長輩分配造型...');
    try {
      final result = await _gameService.distributeAppearances();
      setState(() => _status = '成功: ${result['message']}');
    } catch (e) {
      setState(() => _status = '失敗: $e');
    }
  }

  Future<void> _handleCheckReset() async {
    setState(() => _status = '正在檢查重置...');
    try {
      final result = await _gameService.checkResetStepTotal();
      setState(() => _status = '結果: ${result['message']}');
    } catch (e) {
      setState(() => _status = '失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('遊戲功能測試主頁'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF59B294), Color(0xFF338A70)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('測試設置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: '當前長輩 ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 24),
            const Text('功能操作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _handleDistribute,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('分配隨機造型給 ID: ${_idController.text}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _handleDistributeAll,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('分配隨機造型給所有長輩'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => LeaderboardScreen(elderId: _idController.text),
                  ),
                );
              },
              icon: const Icon(Icons.leaderboard),
              label: const Text('查看專屬排行榜'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _handleCheckReset,
              icon: const Icon(Icons.refresh),
              label: const Text('手動觸發過期步數重置'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('系統狀態:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_status, style: TextStyle(color: _status.contains('失敗') ? Colors.red : Colors.blue)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
