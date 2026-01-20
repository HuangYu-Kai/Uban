import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'family_subscription_screen.dart';

import '../identification_screen.dart';
import '../../services/api_service.dart';

class FamilySettingsView extends StatefulWidget {
  const FamilySettingsView({super.key});

  @override
  State<FamilySettingsView> createState() => _FamilySettingsViewState();
}

class _FamilySettingsViewState extends State<FamilySettingsView> {
  String _userName = '林子強 (家政管理員)';
  bool _isEmergencyOn = true;
  bool _isDailySummaryOn = true;
  bool _isAiInsightOn = false;

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出並回到身分選擇頁面嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushAndRemoveUntil(
                context,
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
                onTap: () => _showPairingCodeDialog(),
              ),
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
            const SizedBox(height: 40),
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
                  'ID: user_882910',
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

  void _showPairingCodeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('管理配對碼'),
              content: FutureBuilder<Map<String, dynamic>>(
                future: ApiService.generatePairingCode(2), // 演示 ID
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || snapshot.data?['error'] != null) {
                    return const Text('無法連線到伺服器，請確認後端已啟動。');
                  }
                  final code = snapshot.data?['pairing_code'] ?? '----';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('請將此四位數代碼提供給長輩：'),
                      const SizedBox(height: 16),
                      Text(
                        code,
                        style: GoogleFonts.inter(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '代碼有效期限為 10 分鐘',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
