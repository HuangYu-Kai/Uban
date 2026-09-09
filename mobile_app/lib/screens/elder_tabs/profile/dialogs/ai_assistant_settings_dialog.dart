import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../globals.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/google_assistant_overlay.dart';

Future<void> showAiAssistantSettingsDialog({
  required BuildContext context,
  required int userId,
  required String userName,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final currentAiName = prefs.getString('ai_assistant_name') ??
      prefs.getString('ai_name') ??
      '嘎蛙';
  final currentUserName = prefs.getString('caregiver_name') ??
      prefs.getString('user_name') ??
      prefs.getString('elder_name') ??
      (userName.isNotEmpty ? userName : '宇璿');
  bool isPortableMode = prefs.getBool('is_portable_mode') ?? true;
  // ★ 語音喚醒總開關，長輩端預設啟用（true）。
  bool wakeWordEnabled = prefs.getBool(kWakeWordEnabledKey) ?? true;

  final aiNameController = TextEditingController(text: currentAiName);
  final userNameController = TextEditingController(text: currentUserName);

  if (!context.mounted) return;

  final parentContext = context;

  showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assistant, color: Color(0xFF38BDF8)),
            const SizedBox(width: 10),
            Text(
              'AI 語音助理設定',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '呼叫喚醒詞：Hey [AI名稱]\n例如："Hey 嘎蛙"',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: aiNameController,
              decoration: const InputDecoration(
                labelText: 'AI 助理名稱',
                hintText: '例如：嘎蛙',
                prefixIcon: Icon(Icons.smart_toy),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: userNameController,
              decoration: const InputDecoration(
                labelText: '長輩(設備主人)稱呼',
                hintText: '例如：宇璿',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // ★ 2026-08-10 第二十輪（需求 6）：語音喚醒總開關。
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '🎙️ 語音喚醒（免持呼叫 AI）',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                wakeWordEnabled
                    ? '已開啟：麥克風全時待命，說出喚醒詞即可呼叫 AI（較耗電）'
                    : '已關閉：麥克風不會自動開啟，改由畫面上的按鈕呼叫 AI',
                style: GoogleFonts.notoSansTc(fontSize: 12),
              ),
              value: wakeWordEnabled,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (val) {
                setDialogState(() {
                  wakeWordEnabled = val;
                });
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '📱 隨身攜帶省電模式',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                isPortableMode
                    ? '已開啟：1秒輪詢間隔（保持全時背景與休眠緊急監聽）'
                    : '已關閉：0.4秒極速回應（保持全時背景與休眠緊急監聽）',
                style: GoogleFonts.notoSansTc(fontSize: 12),
              ),
              value: isPortableMode,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (val) {
                setDialogState(() {
                  isPortableMode = val;
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                GoogleAssistantOverlay.show(
                  parentContext,
                  userName: userNameController.text.trim().isNotEmpty
                      ? userNameController.text.trim()
                      : '宇璿',
                  aiName: aiNameController.text.trim().isNotEmpty
                      ? aiNameController.text.trim()
                      : '嘎蛙',
                  userId: userId,
                );
              },
              icon: const Icon(Icons.volume_up),
              label: const Text('測試呼叫 "Hey 嘎蛙"'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
              final navigator = Navigator.of(dialogCtx);
              final newAi = aiNameController.text.trim();
              final newUser = userNameController.text.trim();
              await prefs.setBool('is_portable_mode', isPortableMode);
              // ★ 2026-08-10 第二十輪（需求 6）：寫入 prefs 後同步更新 notifier
              await prefs.setBool(kWakeWordEnabledKey, wakeWordEnabled);
              wakeWordEnabledNotifier.value = wakeWordEnabled;
              if (newAi.isNotEmpty) {
                await prefs.setString('ai_assistant_name', newAi);
                await prefs.setString('ai_name', newAi);
              }
              if (newUser.isNotEmpty) {
                await prefs.setString('caregiver_name', newUser);
                await prefs.setString('user_name', newUser);
                await prefs.setString('elder_appellation', newUser);
                try {
                  await ApiService.updateElderProfile(
                    userId: userId,
                    appellation: newUser,
                  );
                } catch (_) {}
              }
              navigator.pop();
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('已儲存 AI 語音助理設定！')),
              );
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    ),
  );
}
