import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../identification_screen.dart';
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
        title: const Text('登出'),
        content: const Text('確定要登出並回到身分選擇頁面嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');
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
        const SnackBar(content: Text('正在上傳大頭照...'), duration: Duration(seconds: 1)),
      );
      final result = await ApiService.uploadAvatar(targetUserId, image.path);

      if (!mounted) return;
      if (result.containsKey('avatar_url')) {
        setState(() {}); 
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
                Navigator.pop(context); 
                _showUnbindConfirmDialog(elder);
              },
            ),
          ),
        ).then((_) {
          _fetchPairedElders(); 
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
                  const SnackBar(
                    content: Text('已刪除並解除綁定'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } else {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('刪除失敗: ${result['error']}'),
                    backgroundColor: Colors.redAccent,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          '設定',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileSection(),
            const SizedBox(height: 12),
            _buildSettingsGroup('健康與安全', [
              _buildSwitchItem(
                Icons.emergency_rounded,
                '緊急廣播通知',
                _isEmergencyOn,
                (val) => setState(() => _isEmergencyOn = val),
              ),
              _buildSwitchItem(
                Icons.summarize_rounded,
                '每日健康摘要',
                _isDailySummaryOn,
                (val) => setState(() => _isDailySummaryOn = val),
              ),
              _buildSwitchItem(
                Icons.psychology_rounded,
                'AI 平安洞察',
                _isAiInsightOn,
                (val) => setState(() => _isAiInsightOn = val),
              ),
            ]),
            const SizedBox(height: 12),
            _buildSettingsGroup('已配對長輩', [
              if (_isLoadingElders)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_pairedElders.isEmpty)
                ListTile(
                  title: const Text('尚未配對任何長輩'),
                  trailing: const Icon(Icons.add_link),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: _userName,
                        ),
                      ),
                    ).then((_) => _fetchPairedElders());
                  },
                )
              else
                ..._pairedElders.map((elder) => _buildElderTile(elder)),
              if (_pairedElders.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                  title: const Text('配對新設備', style: TextStyle(color: Colors.blueAccent)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaregiverPairingScreen(
                          familyId: widget.userId,
                          familyName: _userName,
                        ),
                      ),
                    ).then((_) => _fetchPairedElders());
                  },
                ),
            ]),
            const SizedBox(height: 12),
            _buildSettingsGroup('系統', [
              _buildSettingItem(
                Icons.help_outline_rounded,
                '幫助與支援',
                '常見問題、聯繫客服',
                onTap: () {},
              ),
              _buildSettingItem(
                Icons.info_outline_rounded,
                '關於 Uban',
                '版本 1.0.0 (Build 20240320)',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('登出帳號'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 120), 
          ],
        ),
      ),
    );
  }
}
