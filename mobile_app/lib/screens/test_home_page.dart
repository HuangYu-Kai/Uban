import 'package:flutter/material.dart';
import '../services/game_service.dart';
import 'leaderboard_screen.dart';
import 'admin_appearance_screen.dart';

class TestHomePage extends StatefulWidget {
  const TestHomePage({super.key});

  @override
  State<TestHomePage> createState() => _TestHomePageState();
}

class _TestHomePageState extends State<TestHomePage> {
  final GameService _gameService = GameService();
  final TextEditingController _idController = TextEditingController(text: 'AAAA');
  String _status = '等待操作...';
  Map<String, dynamic>? _elderStatus;

  Future<void> _fetchElderStatus() async {
    final elderId = _idController.text.trim();
    if (elderId.isEmpty) return;
    try {
      final status = await _gameService.getElderStatus(elderId);
      setState(() => _elderStatus = status);
    } catch (e) {
      debugPrint('Fetch Status Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('遊戲測試介面'),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('管理者功能 (資料維護)'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AdminAppearanceScreen()),
                );
              },
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('開啟造型管理員介面'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('使用者測試 (依 ID 查詢)'),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              decoration: InputDecoration(
                labelText: '輸入長輩 ID',
                hintText: '例如: AAAA',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _fetchElderStatus,
                ),
              ),
              onSubmitted: (_) => _fetchElderStatus(),
            ),
            const SizedBox(height: 16),
            if (_elderStatus != null) _buildElderStatusCard(),
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
              label: const Text('查看該長輩的專屬排行榜'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 40),
            _buildStatusConsole(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey));
  }

  Widget _buildElderStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white)),
              title: Text('長輩: ${_elderStatus!['elder_name']}'),
              subtitle: Text('ID: ${_idController.text}'),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem('當前步數', '${_elderStatus!['step_total']}'),
                _buildInfoItem('當前造型', '${_elderStatus!['gawa_name']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
      ],
    );
  }

  Widget _buildStatusConsole() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('系統狀態: $_status', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
    );
  }
}
