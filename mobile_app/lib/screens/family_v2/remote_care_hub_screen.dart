// lib/screens/family_v2/remote_care_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'placeholder_screens.dart';

/// 🎭 遠端照護中樞
/// 
/// 整合三大功能方向的主控台
class RemoteCareHubScreen extends StatefulWidget {
  final int? elderId;
  final String elderName;

  const RemoteCareHubScreen({
    super.key,
    this.elderId,
    this.elderName = '爸媽',
  });

  @override
  State<RemoteCareHubScreen> createState() => _RemoteCareHubScreenState();
}

class _RemoteCareHubScreenState extends State<RemoteCareHubScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF8B5CF6),
              Color(0xFFF1F5F9),
            ],
            stops: [0.0, 0.3, 0.7],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('🎭 遠端陪伴增強'),
                        SizedBox(height: 12),
                        _buildDirection1Cards(),
                        
                        SizedBox(height: 24),
                        
                        _buildSectionTitle('📋 生活指引後台'),
                        SizedBox(height: 12),
                        _buildDirection2Cards(),
                        
                        SizedBox(height: 24),
                        
                        _buildSectionTitle('❤️ 情感連結橋樑'),
                        SizedBox(height: 12),
                        _buildDirection3Cards(),
                        
                        SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: Colors.white, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '遠端照護中樞',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '關心 ${widget.elderName}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.notoSansTc(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  // ========================================
  // 方向 1：遠端陪伴增強
  // ========================================

  Widget _buildDirection1Cards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                title: '主動關心劇本',
                subtitle: '預設時間自動問候',
                icon: Icons.schedule_send,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
                ),
                onTap: () => _navigateTo(CareScriptEditorScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                title: 'AI 人格調教',
                subtitle: '自定義小優風格',
                icon: Icons.psychology,
                gradient: LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                ),
                onTap: () => _navigateTo(AiPersonaEditorScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        _buildFeatureCard(
          title: '即時陪伴窗口',
          subtitle: '即時看對話，快速插話',
          icon: Icons.monitor_heart,
          gradient: LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
          ),
          isWide: true,
          onTap: () => _navigateTo(LiveCompanionScreen(elderId: widget.elderId ?? 1)),
        ),
      ],
    );
  }

  // ========================================
  // 方向 2：生活指引後台
  // ========================================

  Widget _buildDirection2Cards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                title: '每日時間表',
                subtitle: '規劃作息',
                icon: Icons.access_time,
                gradient: LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF34D399)],
                ),
                onTap: () => _navigateTo(DailyScheduleScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                title: '健康提醒',
                subtitle: '用藥 & 回診',
                icon: Icons.medication,
                gradient: LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                ),
                onTap: () => _navigateTo(HealthReminderScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        _buildFeatureCard(
          title: '內容推送',
          subtitle: '推送影片、文章、音樂給爸媽',
          icon: Icons.send,
          gradient: LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
          ),
          isWide: true,
          onTap: () => _navigateTo(ContentPushScreen(elderId: widget.elderId ?? 1)),
        ),
      ],
    );
  }

  // ========================================
  // 方向 3：情感連結橋樑
  // ========================================

  Widget _buildDirection3Cards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                title: '心情儀表板',
                subtitle: '情緒分析',
                icon: Icons.mood,
                gradient: LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF22D3EE)],
                ),
                onTap: () => _navigateTo(MoodDashboardScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                title: '回憶寶盒',
                subtitle: '記錄時刻',
                icon: Icons.photo_album,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
                ),
                onTap: () => _navigateTo(MemoryBoxScreen(elderId: widget.elderId ?? 1)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ========================================
  // 通用卡片組件
  // ========================================

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
    bool isWide = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        height: isWide ? 120 : 140,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // 背景圖案
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  icon,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              
              // 內容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: Colors.white,
                      size: 32,
                    ),
                    Spacer(),
                    Text(
                      title,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.2,
                      ),
                      maxLines: isWide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).scale(begin: Offset(0.95, 0.95), end: Offset(1, 1)),
    );
  }

  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }
}
