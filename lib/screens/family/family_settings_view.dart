import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'family_subscription_screen.dart';

class FamilySettingsView extends StatelessWidget {
  const FamilySettingsView({super.key});

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
                onTap: () {},
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
                true,
              ),
              _buildSwitchItem(Icons.summarize_outlined, '每日摘要通知', true),
              _buildSwitchItem(Icons.auto_awesome, 'AI 洞察提醒', false),
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
              onPressed: () {},
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
              '家',
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
                  '林子強 (家政管理員)',
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
          IconButton(onPressed: () {}, icon: const Icon(Icons.edit_outlined)),
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

  Widget _buildSwitchItem(IconData icon, String title, bool value) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: GoogleFonts.notoSansTc()),
      trailing: Switch(
        value: value,
        onChanged: (val) {},
        activeTrackColor: const Color(0xFFFF9800).withValues(alpha: 0.5),
        activeThumbColor: const Color(0xFFFF9800),
      ),
    );
  }
}
