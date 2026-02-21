import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../identification_screen.dart';
import 'family_subscription_screen.dart';
import '../caregiver_pairing_screen.dart';

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
              // 1. 在 await 之前捕獲狀態
              final navigator = Navigator.of(context);
              final prefs = await SharedPreferences.getInstance();

              await prefs.remove('caregiver_id');
              await prefs.remove('caregiver_name');

              // 2. 檢查是否仍掛載於 Widget Tree
              if (!mounted) return;

              // 3. 使用捕獲的狀態而非 Context
              Navigator.pop(dialogContext);
              navigator.pushAndRemoveUntil(
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
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.orange[100],
            child: Text(
              _userName.isNotEmpty ? _userName[0] : '家',
              style: GoogleFonts.notoSansTc(
                fontSize: 24,
                color: Colors.orange[800],
              ),
            ),
          ),
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
      leading: const CircleAvatar(
        backgroundColor: Colors.blueAccent,
        child: Icon(Icons.person, color: Colors.white),
      ),
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
      onTap: () => _showEditElderDialog(elder),
    );
  }

  void _showEditElderDialog(dynamic elder) {
    final nameController = TextEditingController(text: elder['user_name']);
    final ageController = TextEditingController(text: elder['age'].toString());
    String currentGender = elder['gender'] ?? 'M';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '編輯資訊',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFieldLabel('長輩姓名'),
                TextField(
                  controller: nameController,
                  decoration: _dialogInputDecoration(
                    Icons.person_outline,
                    '例如：王大明',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('年齡'),
                          TextField(
                            controller: ageController,
                            keyboardType: TextInputType.number,
                            decoration: _dialogInputDecoration(null, '歲'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('性別'),
                          Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                _genderChoice(
                                  label: '男',
                                  isSelected: currentGender == 'M',
                                  onTap: () =>
                                      setDialogState(() => currentGender = 'M'),
                                ),
                                _genderChoice(
                                  label: '女',
                                  isSelected: currentGender == 'F',
                                  onTap: () =>
                                      setDialogState(() => currentGender = 'F'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      // 1. 在 await 之前捕獲狀態
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      final result = await ApiService.updateElderInfo(
                        familyId: widget.userId,
                        elderId: elder['id'],
                        userName: nameController.text.trim(),
                        age: int.tryParse(ageController.text.trim()),
                        gender: currentGender,
                      );

                      if (!mounted) return;

                      if (result.containsKey('message')) {
                        // 2. 使用捕獲的狀態
                        navigator.pop();
                        _fetchPairedElders();

                        messenger.showSnackBar(
                          SnackBar(
                            content: const Text('更新成功 ✨'),
                            backgroundColor: Colors.green[600],
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      '儲存變更',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.notoSansTc(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey,
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration(IconData? icon, String hint) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  Widget _genderChoice({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF2563EB) : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }
}
