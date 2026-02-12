// 路徑: lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart'; // 引入 API Service
import 'camera_screen.dart'; // 雙向視訊頁
import 'elder_screen.dart';  // 長輩端頁
import 'family_screen.dart'; // 家屬監控頁

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  _RoleSelectionScreenState createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  // 輸入控制器：輸入 User ID (INT)
  final TextEditingController _userIdController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  // 處理導航邏輯：查詢 ID -> 跳轉
  Future<void> _handleNavigation(String role) async {
    String userIdText = _userIdController.text.trim();

    if (userIdText.isEmpty) {
      _showErrorSnackBar('請輸入 User ID (數字)');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 1. 呼叫後端 API 查詢 elder_id
    final data = await _apiService.getElderData(userIdText);

    setState(() {
      _isLoading = false;
    });

    if (data != null && data['status'] == 'success') {
      // 2. 獲取資料庫回傳的 4 碼 elder_id
      String elderId = data['elder_id'];
      String elderName = data['elder_name'] ?? 'Unknown';

      print("✅ 成功獲取通道 ID: $elderId ($elderName)");

      // 3. 根據選擇的角色跳轉頁面，並傳入 elderId 作為 Room ID
      Widget nextScreen;
      switch (role) {
        case 'camera': // 雙向視訊
          nextScreen = CameraScreen(roomId: elderId);
          break;
        case 'elder': // 長輩端 (被監控)
          nextScreen = ElderScreen(roomId: elderId);
          break;
        case 'family': // 家屬端 (監控)
          nextScreen = FamilyScreen(roomId: elderId);
          break;
        default:
          return;
      }

      // 跳轉頁面
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => nextScreen),
        );
      }
    } else {
      // 錯誤處理
      _showErrorSnackBar('找不到此 User ID 對應的長輩設定檔，請確認資料庫');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1), // 暖色系背景
      appBar: AppBar(
        title: const Text('UniFlow - 自動通道分配'),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_sync, size: 80, color: Colors.orangeAccent),
            const SizedBox(height: 20),
            const Text(
              "模擬登入與通道分配",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.brown),
            ),
            const SizedBox(height: 10),
            const Text(
              "輸入 User ID 後，系統將自動從 MySQL 讀取對應的 Elder ID (4碼) 並建立連線。",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),

            // User ID 輸入框
            TextField(
              controller: _userIdController,
              keyboardType: TextInputType.number, // 限制數字輸入
              decoration: InputDecoration(
                labelText: 'User ID (INT)',
                hintText: '請輸入資料庫中的 user_id (例如: 1)',
                prefixIcon: const Icon(Icons.person_search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 40),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // 功能區塊 A: 雙向視訊
              ElevatedButton.icon(
                icon: const Icon(Icons.video_call),
                label: const Text('雙向視訊 (Two-way Call)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _handleNavigation('camera'),
              ),

              const SizedBox(height: 20),
              
              // 功能區塊 B: 監控模式
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.elderly),
                      label: const Text('長輩端\n(被監控)', textAlign: TextAlign.center),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _handleNavigation('elder'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('家屬端\n(監控)', textAlign: TextAlign.center),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _handleNavigation('family'),
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 20),
            const Text(
              "測試提示：請確保 MySQL 的 elder_user_data 表中已有該 User ID 的資料。",
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}