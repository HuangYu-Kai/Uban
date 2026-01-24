import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'family_script_editor_screen.dart';
import 'family_marketplace_view.dart';

class FamilyScriptsView extends StatelessWidget {
  const FamilyScriptsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text(
          '劇本管理',
          style: GoogleFonts.notoSansTc(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFFF9800),
              size: 30,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Marketplace Banner
            _buildMarketplaceBanner(context),
            const SizedBox(height: 32),

            // 1. 推薦模版 (Templates)
            Text(
              '推薦模版 (Templates)',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildTemplateCard(
                    '☀️ 早安日報',
                    'AI 自動對話流',
                    Colors.blue[50]!,
                    Colors.blue[700]!,
                  ),
                  _buildTemplateCard(
                    '💊 吃藥提醒',
                    '多重通知邏輯',
                    Colors.orange[50]!,
                    Colors.orange[700]!,
                  ),
                  _buildTemplateCard(
                    '🎂 生日驚喜',
                    '多媒體自動推播',
                    Colors.red[50]!,
                    Colors.red[700]!,
                  ),
                  _buildTemplateCard(
                    '🧘 運動提醒',
                    '健康教練介入',
                    Colors.green[50]!,
                    Colors.green[700]!,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 2. 我的活躍劇本 (Active Flows)
            Text(
              '我的活躍劇本 (Active Flows)',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            _buildFlowItem(
              context,
              '每日血壓藥提醒',
              '每天 08:00',
              '動作：發出警報 + AI 語音 ("爸，吃藥囉，吃完按一下")',
              '邏輯：若 15分 未按 -> Line 通知我',
              true,
              Icons.check_circle,
              Colors.green,
            ),
            _buildFlowItem(
              context,
              '週三下午茶話題 (京劇)',
              '週三 14:00',
              '動作：RAG 搜尋 "最新京劇演出" -> 推播影片連結',
              '邏輯：自動推送到廣播站頻道',
              true,
              Icons.check_circle,
              Colors.green,
            ),
            _buildFlowItem(
              context,
              '寒流關懷 (暫停中)',
              '氣象局發布低溫特報',
              '動作：AI 提醒 ("這兩天很冷，圍巾要圍喔")',
              '邏輯：自動語音對話觸發',
              false,
              Icons.warning_amber_rounded,
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(
    String title,
    String subtitle,
    Color bg,
    Color textColor,
  ) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowItem(
    BuildContext context,
    String title,
    String trigger,
    String action,
    String logic,
    bool isActive,
    IconData statusIcon,
    Color statusColor,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FamilyScriptEditorScreen(scriptTitle: title),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                Switch(
                  value: isActive,
                  onChanged: (v) {},
                  activeThumbColor: const Color(0xFFFF9800),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDetailRow(Icons.access_time, '觸發：', trigger),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.play_circle_outline, '動作：', action),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.psychology_outlined, '邏輯：', logic),
          ],
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketplaceBanner(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FamilyMarketplaceView(),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: NetworkImage(
              'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070&auto=format&fit=crop',
            ),
            fit: BoxFit.cover,
            opacity: 0.1,
          ),
          gradient: const LinearGradient(
            colors: [Color(0xFF212121), Color(0xFF424242)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Colors.amber, size: 28),
                const SizedBox(width: 12),
                Text(
                  '劇本市集',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '探索由專家設計的專業陪伴流程\n失智關懷、健康提醒、情感導引...',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ).animate().shimmer(delay: 1.seconds, duration: 1500.ms),
    );
  }
}
