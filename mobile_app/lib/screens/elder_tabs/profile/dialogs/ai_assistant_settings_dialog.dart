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

  // 🚨 第五十二輪一次性遷移：第五十一輪之前的版本會在「每次載入首頁」時
  // 強制把 kWakeWordEnabledKey 寫成 true（不是使用者自己的選擇），所以
  // 既有裝置上這把鍵大多已經被寫成 true——光是把下面的預設值改成 false
  // 救不了這些裝置（`?? false` 只在鍵「不存在」時才生效，鍵一旦有值就
  // 不會走預設值那條路）。用一把版本化旗標鍵確保只重設這一次：旗標不
  // 存在 → 這是第一次套用本次遷移，把喚醒詞強制拉回 false 並寫入旗標；
  // 旗標一旦存在，代表使用者之後自己的開關選擇（不論開或關）都不會再
  // 被本遷移覆蓋。
  const migrationFlagKey = 'wake_word_pref_reset_v52';
  if (!(prefs.getBool(migrationFlagKey) ?? false)) {
    await prefs.setBool(kWakeWordEnabledKey, false);
    wakeWordEnabledNotifier.value = false;
    await prefs.setBool(migrationFlagKey, true);
  }

  final currentAiName = prefs.getString('ai_assistant_name') ??
      prefs.getString('ai_name') ??
      '嘎蛙';
  final currentUserName = prefs.getString('caregiver_name') ??
      prefs.getString('user_name') ??
      prefs.getString('elder_name') ??
      (userName.isNotEmpty ? userName : '宇璿');
  bool isPortableMode = prefs.getBool('is_portable_mode') ?? true;
  // ★ 語音喚醒總開關。單一預設值真相在 globals.dart 的
  // wakeWordEnabledNotifier（第五十一輪起預設關閉，護欄 G59）——這裡的
  // `?? false` 必須跟那邊一致，否則長輩一打開這個設定頁存檔，就會把
  // 喚醒詞寫回「開啟」（第五十二輪修正前就是這裡的 `?? true` 造成的）。
  bool wakeWordEnabled = prefs.getBool(kWakeWordEnabledKey) ?? false;

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
