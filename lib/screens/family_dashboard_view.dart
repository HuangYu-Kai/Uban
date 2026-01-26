import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'family_script_editor_screen.dart';
import 'family/family_care_journal_view.dart';

class FamilyDashboardView extends StatelessWidget {
  const FamilyDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header: Switch Elder + Avatar
              _buildHeader(),
              const SizedBox(height: 24),

              // 2. AI Mood Card
              _buildMoodCard(context),
              const SizedBox(height: 24),

              // 3. Quick Actions
              Row(
                children: [
                  Expanded(
                    child: _buildQuickAction(
                      '撥打視訊',
                      'Call Mom',
                      Icons.videocam_rounded,
                      [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
                      const Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildQuickAction(
                      '聽聽媽媽說什麼',
                      'Listen',
                      Icons.mic_none_rounded,
                      [const Color(0xFFF1F8E9), const Color(0xFFDCEDC8)],
                      const Color(0xFF388E3C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 3.5 Quick Link to Scripts Editor
              _buildEditorQuickLink(context),
              const SizedBox(height: 32),

              // 4. Timeline
              Text(
                '今日動態',
                style: GoogleFonts.notoSansTc(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              _buildTimeline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorQuickLink(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const FamilyScriptEditorScreen(scriptTitle: '新劇本編輯'),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '探索劇本功能',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '視覺化編輯長輩的互動流程',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
      ).animate().shimmer(delay: 2.seconds, duration: 1500.ms),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Switch Elder Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFAB60),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                '切換長輩',
                style: GoogleFonts.notoSansTc(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Elder Name & Status
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '正在陪伴',
              style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey),
            ),
            Text(
              '林美玲 媽媽',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: const NetworkImage(
                'https://randomuser.me/api/portraits/women/90.jpg',
              ),
              backgroundColor: Colors.grey[200],
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMoodCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FamilyCareJournalView(),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFA726), Color(0xFFFFB74D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white70, size: 24),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white70,
                  size: 20,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Text('😄', style: TextStyle(fontSize: 50)),
                ).animate().scale(
                  delay: 500.ms,
                  duration: 800.ms,
                  curve: Curves.elasticOut,
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '心情愉快',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '今日互動指數：高',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '「媽媽今天精神很好！早上聊到『鄧麗君』的時候特別開心，還跟著唱了兩句。目前沒有發現負面情緒。」',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    String label,
    String subLabel,
    IconData icon,
    List<Color> gradientColors,
    Color accentColor,
  ) {
    return Container(
      height: 120, // Reduced from 160 to fit constraints
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: -5,
            child: Icon(
              icon,
              size: 60, // Reduced size
              color: accentColor.withValues(alpha: 0.1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0), // Reduced padding
            child: Column(
              mainAxisAlignment: MainAxisAlignment
                  .spaceBetween, // Use spaceBetween instead of Spacer
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: accentColor),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18, // Slightly smaller
                          fontWeight: FontWeight.bold,
                          color: accentColor.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        subLabel,
                        style: GoogleFonts.inter(
                          fontSize: 12, // Slightly smaller
                          color: accentColor.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        _buildTimelineItem(
          '14:15',
          '記錄了媽媽的一段回憶',
          '「這張照片是在阿里山拍的啦，那...」',
          true,
          Colors.blue,
        ),
        _buildTimelineItem('13:00', '記憶遊戲', '完成程度：80%', false, Colors.orange),
        _buildTimelineItem(
          '10:00',
          '廣播錄音',
          '媽媽發布了一則關於「種蘭花」的語音。',
          true,
          Colors.green,
          isAudio: true,
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    String time,
    String title,
    String content,
    bool showAction,
    Color color, {
    bool isAudio = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 8,
                backgroundColor: Colors.white,
                child: CircleAvatar(radius: 6, backgroundColor: color),
              ),
              Container(width: 2, height: 80, color: Colors.grey[300]),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      if (showAction) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              isAudio ? Icons.play_arrow : Icons.play_arrow,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAudio ? '點擊播放' : '點擊觀看',
                              style: GoogleFonts.notoSansTc(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
