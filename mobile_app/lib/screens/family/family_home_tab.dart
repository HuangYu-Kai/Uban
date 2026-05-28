import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/elder.dart';
import 'alert_center_screen.dart';
import 'widgets/ai_suggestion_card.dart';

/// 🏠 首頁 Tab
///
/// 集中顯示最重要的資訊：
/// 1. 長輩在線狀態
/// 2. AI 今日近況摘要（最主要）
/// 3. 警示預覽
class FamilyHomeTab extends StatelessWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final VoidCallback? onNavigateToAlerts;

  const FamilyHomeTab({
    super.key,
    this.currentElder,
    this.isElderOnline = false,
    this.onNavigateToAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 在線狀態橫幅
              _buildStatusBanner(context),
              const SizedBox(height: 16),

              // AI 近況摘要（最主要元件）
              _buildAiSection(context),
              const SizedBox(height: 16),

              // 警示預覽
              _buildAlertPreview(context),
            ]),
          ),
        ),
      ],
    );
  }

  // ─── 在線狀態橫幅 ───

  Widget _buildStatusBanner(BuildContext context) {
    final online = isElderOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: online
            ? const Color(0xFFECFDF5)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: online
              ? const Color(0xFF6EE7B7)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          // 脈衝燈
          _PulseDot(color: online ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? '長輩裝置在線' : '長輩裝置離線',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: online
                        ? const Color(0xFF065F46)
                        : const Color(0xFF475569),
                  ),
                ),
                Text(
                  online
                      ? '可即時通話、傳送訊息'
                      : '訊息將在長輩上線後送達',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: online
                        ? const Color(0xFF047857)
                        : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 最後更新時間
          Text(
            '10:30 更新',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── AI 近況摘要 ───

  Widget _buildAiSection(BuildContext context) {
    if (currentElder == null) {
      return _buildNoElderPlaceholder(context);
    }
    return AiSuggestionCard(
      elderName: currentElder!.displayName,
      elderId: currentElder!.id,
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.06);
  }

  Widget _buildNoElderPlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.family_restroom_rounded,
              color: Colors.white, size: 56),
          const SizedBox(height: 16),
          Text(
            '尚未選擇長輩',
            style: GoogleFonts.notoSansTc(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請使用頂部選擇器選擇或配對長輩\n才能查看照護資訊',
            style: GoogleFonts.notoSansTc(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ─── 警示預覽 ───

  // Mock 警示資料（之後從 PredictiveAlertService 取）
  static const List<Map<String, dynamic>> _mockAlerts = [
    {
      'title': '活動量偏低',
      'desc': '今日步數僅 800 步，低於平均值',
      'level': 'medium',
      'icon': Icons.directions_walk_rounded,
    },
    {
      'title': '用藥提醒確認',
      'desc': '下午 2 點的血壓藥尚未確認服用',
      'level': 'high',
      'icon': Icons.medication_rounded,
    },
  ];

  Widget _buildAlertPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFF59E0B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '最新警示',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_mockAlerts.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (onNavigateToAlerts != null) {
                    onNavigateToAlerts!();
                  } else if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => AlertCenterScreen(
                          elderName: currentElder?.displayName ?? '長輩',
                          elderId: currentElder?.id,
                        ),
                      ),
                    );
                  }
                },
                child: Text(
                  '查看全部 →',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 警示列表
          ..._mockAlerts.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(bottom: e.key < _mockAlerts.length - 1 ? 10 : 0),
                child: _AlertItem(data: e.value, index: e.key),
              )),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }
}

// ─── 子元件：脈衝燈 ───

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .fade(duration: 1200.ms, begin: 1.0, end: 0.3)
        .then()
        .fade(duration: 1200.ms, begin: 0.3, end: 1.0);
  }
}

// ─── 子元件：警示列 ───

class _AlertItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  const _AlertItem({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    Color levelColor;
    Color bgColor;
    switch (data['level'] as String) {
      case 'high':
        levelColor = const Color(0xFFEF4444);
        bgColor = const Color(0xFFFEF2F2);
        break;
      case 'medium':
        levelColor = const Color(0xFFF59E0B);
        bgColor = const Color(0xFFFFFBEB);
        break;
      default:
        levelColor = const Color(0xFF3B82F6);
        bgColor = const Color(0xFFEFF6FF);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: levelColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              data['icon'] as IconData,
              color: levelColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data['desc'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFFCBD5E1),
            size: 24,
          ),
        ],
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideX(begin: 0.05);
  }
}
