import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../identification_screen.dart';
import 'family_subscription_screen.dart';
import '../caregiver_pairing_screen.dart';
import '../elder_profile_edit_screen.dart';

class FamilySettingsView extends StatefulWidget {
  final int userId;
  final String userName;

  const FamilySettingsView({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FamilySettingsView> createState() => _FamilySettingsViewState();
}

class _FamilySettingsViewState extends State<FamilySettingsView> {
  late String _userName;
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = false;
  List<dynamic> _pairedElders = [];
  bool _isLoadingElders = true;

  @override
  void initState() {
    super.initState();
    _userName = widget.userName;
    _fetchPairedElders();
  }

  Future<void> _fetchPairedElders() async {
    try {
      final elders = await ApiService.getPairedElders(widget.userId);
      if (mounted) {
        setState(() {
          _pairedElders = elders;
          _isLoadingElders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingElders = false);
      }
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Rename to avoid shadowing
        title: const Text('登出'),
        content: const Text('確定要登出並回到身分選擇頁面嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              // 1. 先關閉對話框 (同步操作)
              Navigator.pop(dialogContext);

              // 2. 執行異步清除
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');

              // 3. 確保組件仍掛載，然後執行跳轉
              if (!mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: const Text('登出', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(int targetUserId) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在上傳大頭照...'), duration: Duration(seconds: 1)),
      );
      final result = await ApiService.uploadAvatar(targetUserId, image.path);

      if (!mounted) return;
      if (result.containsKey('avatar_url')) {
        setState(() {}); // Trigger rebuild to refresh image with new timestamp
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('大頭照更新成功！'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失敗: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAvatar(int userId, String defaultName, double radius) {
    return GestureDetector(
      onTap: () => _pickAndUploadAvatar(userId),
      child: Stack(
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange[100],
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.network(
              '${ApiService.baseUrl}/user/$userId/avatar?v=${DateTime.now().millisecondsSinceEpoch}',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    defaultName.isNotEmpty ? defaultName[0] : 'U',
                    style: GoogleFonts.notoSansTc(
                      fontSize: radius * 0.7,
                      color: Colors.orange[800],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[200]!, width: 1),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 14,
                color: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleEditProfile() {
    final TextEditingController controller = TextEditingController(
      text: _userName,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯個人資料'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '顯示名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _userName = controller.text;
              });
              Navigator.pop(context);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '設定',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildProfileSection(),
            const SizedBox(height: 24),
            _buildSettingsGroup('訂閱與方案', [
              _buildSettingItem(
                Icons.card_membership_outlined,
                '當前方案：免費版',
                '點擊查看更多方案與功能',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FamilySubscriptionScreen(),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 24),
            _buildSettingsGroup('設備與配對', [
              _buildSettingItem(
                Icons.qr_code_scanner,
                '管理配對碼',
                '新增長輩端設備',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CaregiverPairingScreen(
                        familyId: widget.userId,
                        familyName: widget.userName,
                      ),
                    ),
                  );
                  _fetchPairedElders(); // Refresh list after potential new pairing
                },
              ),
              if (_isLoadingElders)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_pairedElders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('目前尚未綁定任何長輩'),
                )
              else
                ..._pairedElders.map((elder) => _buildElderTile(elder)),
              _buildSettingItem(
                Icons.people_outline,
                '聯絡人權限',
                '管理共同照顧者',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 24),
            _buildSettingsGroup('通知與提醒', [
              _buildSwitchItem(
                Icons.notifications_active_outlined,
                '緊急狀況警報',
                _isEmergencyOn,
                (val) => setState(() => _isEmergencyOn = val),
              ),
              _buildSwitchItem(
                Icons.summarize_outlined,
                '每日摘要通知',
                _isDailySummaryOn,
                (val) => setState(() => _isDailySummaryOn = val),
              ),
              _buildSwitchItem(
                Icons.auto_awesome,
                'AI 洞察提醒',
                _isAiInsightOn,
                (val) => setState(() => _isAiInsightOn = val),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSettingsGroup('系統與介面', [
              _buildSettingItem(
                Icons.color_lens_outlined,
                '介面主題',
                '溫暖淺色',
                onTap: () {},
              ),
              _buildSettingItem(
                Icons.language_outlined,
                '語文',
                '繁體中文',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),
            TextButton(
              onPressed: _handleLogout,
              child: Text(
                '登出帳號',
                style: GoogleFonts.notoSansTc(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(
              height: 140,
            ), // Ensure content is not hidden by the bottom dock
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          _buildAvatar(widget.userId, _userName, 36),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: user_${widget.userId}',
                  style: GoogleFonts.inter(color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleEditProfile,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            title,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
        Container(
          color: Colors.white,
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingItem(
    IconData icon,
    String title,
    String subtitle, {
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: GoogleFonts.notoSansTc()),
      subtitle: Text(subtitle, style: GoogleFonts.notoSansTc(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchItem(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: GoogleFonts.notoSansTc()),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFFFF9800).withValues(alpha: 0.5),
        activeThumbColor: const Color(0xFFFF9800),
      ),
    );
  }

  Widget _buildElderTile(dynamic elder) {
    return ListTile(
      leading: _buildAvatar(elder['id'], elder['user_name'] ?? '長', 20),
      title: Text(elder['user_name'] ?? '未知長輩'),
      subtitle: Text(
        'ID: ${elder['id']} | 年齡: ${elder['age']} | 性別: ${elder['gender'] == 'M' ? '男' : '女'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '已連線',
              style: TextStyle(color: Colors.green[700], fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_note, color: Colors.blueAccent, size: 20),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ElderProfileEditScreen(
              elderData: elder,
              familyId: widget.userId,
              onUnbind: () {
                Navigator.pop(context); // Close profile edit screen
                _showUnbindConfirmDialog(elder);
              },
            ),
          ),
        ).then((_) {
          _fetchPairedElders(); // Refresh on return
        });
      },
    );
  }

  void _showUnbindConfirmDialog(dynamic elder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '解除綁定',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '確定要解除與「${elder['user_name']}」的綁定嗎？\n\n警告：這將會永久刪除該長輩的所有資料與對話紀錄，無法復原。',
          style: GoogleFonts.notoSansTc(color: Colors.redAccent, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              final result = await ApiService.unbindElder(
                widget.userId,
                elder['id'],
              );

              if (!mounted) return;

              if (result.containsKey('message')) {
                navigator.pop();
                _fetchPairedElders();
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('已刪除並解除綁定'),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('刪除失敗: ${result['error']}'),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(
              '確定刪除',
              style: GoogleFonts.notoSansTc(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
