import 'package:flutter/material.dart';
import 'camera_screen.dart'; // 雙向視訊
import 'elder_screen.dart'; // 監控端-長輩
import 'family_screen.dart'; // 監控端-家屬

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final TextEditingController _roomController = TextEditingController();

  void _navigateTo(Widget page) {
    if (_roomController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入裝置編號/房號')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('功能選擇')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _roomController,
              decoration: const InputDecoration(
                labelText: '請輸入裝置編號 (Room ID)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 30),

            const Divider(thickness: 2, height: 40),
            const Text(
              "功能 A: 雙向視訊通話",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.video_call),
              label: const Text('進入雙向視訊 (Camera Screen)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () => _navigateTo(
                CameraScreen(roomId: _roomController.text.trim()),
              ),
            ),

            const SizedBox(height: 30),
            const Divider(thickness: 2, height: 40),
            const Text(
              "功能 B: 遠端居家監控",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: const Text('長輩端 (被監控)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _navigateTo(
                      ElderScreen(roomId: _roomController.text.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('家屬端 (監控者)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _navigateTo(
                      FamilyScreen(roomId: _roomController.text.trim()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
