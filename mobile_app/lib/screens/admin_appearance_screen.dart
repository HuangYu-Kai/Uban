import 'package:flutter/material.dart';
import '../services/game_service.dart';

class AdminAppearanceScreen extends StatefulWidget {
  const AdminAppearanceScreen({super.key});

  @override
  State<AdminAppearanceScreen> createState() => _AdminAppearanceScreenState();
}

class _AdminAppearanceScreenState extends State<AdminAppearanceScreen> {
  final GameService _gameService = GameService();
  
  // --- Schedule State ---
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _scheduleStatus = '';

  // --- Assign State ---
  final TextEditingController _assignElderIdController = TextEditingController();
  final TextEditingController _assignGawaIdController = TextEditingController();
  String _assignStatus = '';

  // --- Info Query State ---
  final TextEditingController _infoElderIdController = TextEditingController();
  Map<String, dynamic>? _elderInfo;
  String _infoStatus = '';

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedDate = pickedDate;
          _selectedTime = pickedTime;
        });
      }
    }
  }

  Future<void> _setDistributionTime() async {
    if (_selectedDate == null || _selectedTime == null) {
      setState(() => _scheduleStatus = '請先選擇日期與時間');
      return;
    }
    setState(() => _scheduleStatus = '設定中...');
    
    final finalDateTime = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedTime!.hour, _selectedTime!.minute,
    ).toUtc(); // 伺服器通常使用 UTC
    
    try {
      final res = await _gameService.setDistributionTime(finalDateTime.toIso8601String());
      setState(() => _scheduleStatus = '設定成功: ${res['message']}');
    } catch (e) {
      setState(() => _scheduleStatus = '錯誤: $e');
    }
  }

  Future<void> _assignAppearance() async {
    final elderId = _assignElderIdController.text.trim();
    final gawaIdText = _assignGawaIdController.text.trim();
    
    if (elderId.isEmpty || gawaIdText.isEmpty) {
      setState(() => _assignStatus = '請輸入長輩 ID 與造型 ID');
      return;
    }
    
    final gawaId = int.tryParse(gawaIdText);
    if (gawaId == null) {
      setState(() => _assignStatus = '造型 ID 必須為數字');
      return;
    }
    
    setState(() => _assignStatus = '分配中...');
    try {
      final res = await _gameService.assignAppearance(elderId, gawaId);
      setState(() => _assignStatus = '成功: ${res['message']}');
    } catch (e) {
      setState(() => _assignStatus = '錯誤: $e');
    }
  }

  Future<void> _fetchElderInfo() async {
    final elderId = _infoElderIdController.text.trim();
    if (elderId.isEmpty) {
      setState(() {
        _infoStatus = '請輸入長輩 ID';
        _elderInfo = null;
      });
      return;
    }
    
    setState(() {
      _infoStatus = '查詢中...';
      _elderInfo = null;
    });
    
    try {
      final res = await _gameService.getAdminElderInfo(elderId);
      setState(() {
        _infoStatus = '查詢成功';
        _elderInfo = res;
      });
    } catch (e) {
      setState(() => _infoStatus = '錯誤: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('造型管理員介面'), backgroundColor: Colors.indigo),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 自動派發時間設定
          _buildSectionCard(
            title: '設定自動派發造型時間',
            children: [
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _selectDateTime,
                    child: const Text('選擇日期與時間'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _selectedDate == null || _selectedTime == null 
                          ? '未選擇' 
                          : '${_selectedDate!.toLocal().toString().split(' ')[0]} ${_selectedTime!.format(context)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _setDistributionTime,
                icon: const Icon(Icons.schedule),
                label: const Text('儲存並啟用排程'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
              if (_scheduleStatus.isNotEmpty) 
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_scheduleStatus, style: TextStyle(color: _scheduleStatus.contains('錯誤') ? Colors.red : Colors.green)),
                ),
            ]
          ),

          const SizedBox(height: 16),

          // 2. 單獨分配造型
          _buildSectionCard(
            title: '單獨分配指定造型',
            children: [
              TextField(
                controller: _assignElderIdController,
                decoration: const InputDecoration(labelText: '長輩 ID (例如: AAAA)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _assignGawaIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '造型 ID (gawa_id)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _assignAppearance,
                icon: const Icon(Icons.person_add),
                label: const Text('立即分配'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              ),
              if (_assignStatus.isNotEmpty) 
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_assignStatus, style: TextStyle(color: _assignStatus.contains('錯誤') ? Colors.red : Colors.green)),
                ),
            ]
          ),

          const SizedBox(height: 16),

          // 3. 查詢長輩資訊
          _buildSectionCard(
            title: '查詢長輩收集資訊',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _infoElderIdController,
                      decoration: const InputDecoration(labelText: '長輩 ID (例如: AAAA)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _fetchElderInfo,
                    child: const Text('查詢'),
                  ),
                ],
              ),
              if (_infoStatus.isNotEmpty && _elderInfo == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_infoStatus, style: TextStyle(color: _infoStatus.contains('錯誤') ? Colors.red : Colors.grey)),
                ),
              if (_elderInfo != null) ...[
                const Divider(height: 24),
                Text('長輩名稱: ${_elderInfo!['elder_name'] ?? '無'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('累計步數: ${_elderInfo!['step_total']} 步'),
                Text('擁有造型數量: ${_elderInfo!['owned_count']}'),
                Text('總加成比例: ${((_elderInfo!['total_bonus'] ?? 0) * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('擁有的造型清單:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (_elderInfo!['collection'] as List).map((app) {
                    return Chip(
                      label: Text('${app['gawa_name']} (+${(app['bonus'] * 100).toStringAsFixed(0)}%)'),
                      backgroundColor: Colors.teal.shade50,
                    );
                  }).toList(),
                )
              ]
            ]
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const Divider(),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
