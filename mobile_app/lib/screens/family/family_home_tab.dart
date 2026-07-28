import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import 'alert_center_screen.dart';

/// 🏠 子女端首頁 Tab (全新極光玻璃與 AI 情緒氣象台 + 生活時光牆)
class FamilyHomeTab extends StatefulWidget {
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
  State<FamilyHomeTab> createState() => _FamilyHomeTabState();
}

class _FamilyHomeTabState extends State<FamilyHomeTab> {
  Map<String, dynamic>? _moodInsightData;
  List<dynamic> _realLogs = [];
  int _selectedDateFilterIndex = 0; // 0: 今天, 1: 昨天, 2: 歷史月曆
  DateTime? _selectedHistoricalDate;

  @override
  void initState() {
    super.initState();
    _loadDynamicData();
  }


  void _showFullDialogueDialog(BuildContext context, String query, String ai, String timeStr) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.auto_stories_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Text(
              '🗣️ AI 語音陪伴對話紀錄 ($timeStr)',
              style: GoogleFonts.notoSansTc(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('👴 長輩提問：', style: GoogleFonts.notoSansTc(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
              ),
              child: Text(query, style: GoogleFonts.notoSansTc(color: Colors.white, height: 1.4)),
            ),
            const SizedBox(height: 14),
            Text('🤖 AI 小嘎回報與陪伴：', style: GoogleFonts.notoSansTc(color: const Color(0xFFFCD34D), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Text(ai, style: GoogleFonts.notoSansTc(color: const Color(0xFFFEF3C7), height: 1.4)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('關閉', style: GoogleFonts.notoSansTc(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCategoryDetailModal(
    BuildContext context, {
    required String categoryTitle,
    required IconData categoryIcon,
    required Color categoryColor,
    required List<Map<String, dynamic>> items,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(color: Colors.black87, blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: categoryColor, width: 1.5),
                      ),
                      child: Icon(categoryIcon, color: categoryColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryTitle,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '包含 ${items.length} 筆相關新聞閱覽與 AI 陪伴對話',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(c),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          '尚無該主題分類的新紀錄',
                          style: GoogleFonts.notoSansTc(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final isChat = item['isChat'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: (item['color'] as Color).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (item['color'] as Color).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item['badge'] as String,
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: item['color'] as Color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item['title'] as String,
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${item['date']} ${item['time']}',
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item['desc'] as String,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                ),
                                if (isChat) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                      foregroundColor: const Color(0xFFFCD34D),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(color: Color(0xFFF59E0B)),
                                      ),
                                    ),
                                    onPressed: () {
                                      _showFullDialogueDialog(
                                        context,
                                        item['fullQuery'] as String? ?? '',
                                        item['fullAi'] as String? ?? '',
                                        item['time'] as String? ?? '',
                                      );
                                    },
                                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                    label: Text(
                                      '📖 展開檢視長輩與 AI 完整對話逐字稿',
                                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void didUpdateWidget(FamilyHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id) {
      _loadDynamicData();
    }
  }

  Future<void> _loadDynamicData() async {
    if (widget.currentElder == null) return;
    final elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();

    try {
      final insight = await ApiService.getElderMoodInsight(elderIdStr);
      final logs = await ApiService.getElderActivityLogs(elderIdStr, limit: 10);
      if (mounted) {
        setState(() {
          _moodInsightData = insight;
          _realLogs = logs;
        });
      }
    } catch (e) {
      // Ignore exception gracefully
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF38BDF8),
      backgroundColor: const Color(0xFF1E293B),
      onRefresh: _loadDynamicData,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. 長輩頂部極光卡片與在線狀態
                _buildElderHeaderCard(context),
                const SizedBox(height: 16),

                // 2. 🤖 亮點一：AI 長輩情緒氣象台 & 破冰金句卡片
                _buildAiMoodRadarCard(context),
                const SizedBox(height: 16),

                // 3. 📸 亮點二：長輩生活動態時光牆 (Elder Life Feed)
                _buildElderLifeFeedSection(context),
                const SizedBox(height: 16),

                // 4. 警示預覽
                _buildAlertPreview(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 1. 長輩頂部極光卡片與在線狀態 ───

  Widget _buildElderHeaderCard(BuildContext context) {
    final online = widget.isElderOnline;
    final name = widget.currentElder?.displayName ?? '長輩';
    final location = widget.currentElder?.location ?? '台北市';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 大頭照與在線 Pulse
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/user_avatar.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: _PulseDot(color: online ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: online ? const Color(0xFF10B981).withValues(alpha: 0.25) : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: online ? const Color(0xFF34D399) : Colors.white24,
                            ),
                          ),
                          child: Text(
                            online ? '在線通話機' : '離線',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: online ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          '$location • 今日累積 3,850 步',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            color: const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }

  // ─── 2. 🤖 AI 長輩情緒氣象台 & 破冰話題 (方案 B：第一人稱問候 + 快捷動作) ───

  Widget _buildAiMoodRadarCard(BuildContext context) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final moodTitle = _moodInsightData?['mood_title'] ?? '溫馨平穩';
    final moodScore = _moodInsightData?['mood_score'] ?? 88;
    final moodIcon = _moodInsightData?['mood_icon'] ?? '🍵';
    final summaryText = _moodInsightData?['summary'] ?? '$name 今天情緒非常穩定愉快，下午點閱收聽了熱門體育新聞，展現高度興趣！';
    final icebreakerTopic = _moodInsightData?['icebreaker_topic'] ?? '$name！我今天看到經典賽新聞，感覺超精彩的！您最近也有在關注戰況嗎？';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0F2942),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部標題與極光情緒氣象發光球
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 情緒氣象台',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '即時情緒趨勢分析',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 極光發光情緒指標 Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text('$moodIcon ', style: const TextStyle(fontSize: 13)),
                    Text(
                      '$moodTitle ($moodScore%)',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 情緒分析描述
          Text(
            summaryText,
            style: GoogleFonts.notoSansTc(
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFE2E8F0),
            ),
          ),

          const SizedBox(height: 18),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 16),

          // 💡 破冰話題建議標題
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(
                '今日推薦關懷破冰話題：',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFCD34D),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 奢華亮金發光金句卡（第一人稱溫情問候）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF261C05),
                  Color(0xFF1F1703),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '“',
                  style: TextStyle(
                    fontSize: 32,
                    height: 0.8,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFDE68A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    icebreakerTopic,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFEF3C7),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 方案 B：直接動作按鈕 (Action Buttons)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: Text(
                          '📞 撥打關懷電話給$name',
                          style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '💡 推薦聊天開場白：',
                              style: GoogleFonts.notoSansTc(color: const Color(0xFFFCD34D), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                icebreakerTopic,
                                style: GoogleFonts.notoSansTc(color: const Color(0xFFFEF3C7), height: 1.4),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: Text('取消', style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8))),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                            onPressed: () {
                              Navigator.pop(c);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('正在發起即時關懷連線...', style: GoogleFonts.notoSansTc()),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                            },
                            icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                            label: Text('開始撥號', style: GoogleFonts.notoSansTc(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18, color: Colors.white),
                  label: Text(
                    '撥打電話聊聊',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Clipboard.setData(ClipboardData(text: icebreakerTopic));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white),
                            const SizedBox(width: 10),
                            Expanded(child: Text('已複製話題並準備帶入關懷卡！', style: GoogleFonts.notoSansTc())),
                          ],
                        ),
                        backgroundColor: const Color(0xFF8B5CF6),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.mark_email_unread_rounded, size: 18, color: Color(0xFF78350F)),
                  label: Text(
                    '傳送關懷卡',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF78350F),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFDE68A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.05);
  }

  // ─── 3. 📸 長輩生活動態時光牆 (動態擴充與折疊/展開機制 + 日期篩選) ───

  Widget _buildElderLifeFeedSection(BuildContext context) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    List<Map<String, dynamic>> rawFeedItems = [];

    if (_realLogs.isNotEmpty) {
      rawFeedItems = _realLogs.map((log) {
        final contentStr = log['content']?.toString() ?? '';
        final eventType = log['event_type']?.toString() ?? '';
        final tsStr = log['timestamp']?.toString() ?? '';

        String dateStr = todayStr;
        String timeStr = '12:00';
        if (tsStr.length >= 16) {
          dateStr = tsStr.substring(0, 10);
          final clockStr = tsStr.substring(11, 16);
          if (dateStr == todayStr) {
            timeStr = clockStr;
          } else if (dateStr == yesterdayStr) {
            timeStr = '昨天 $clockStr';
          } else {
            final m = dateStr.substring(5, 7);
            final d = dateStr.substring(8, 10);
            timeStr = '$m/$d $clockStr';
          }
        }

        String badge = 'LOG';
        Color col = const Color(0xFF38BDF8);
        Color glowCol = const Color(0xFF0284C7);
        IconData ic = Icons.auto_awesome_rounded;

        if (eventType == 'news_view' || contentStr.contains('新聞') || contentStr.contains('NBA')) {
          badge = 'NEWS';
          col = const Color(0xFF38BDF8);
          glowCol = const Color(0xFF0284C7);
          ic = Icons.sports_basketball_rounded;
        } else if (contentStr.contains('散步') || contentStr.contains('步數')) {
          badge = 'WALK';
          col = const Color(0xFF34D399);
          glowCol = const Color(0xFF059669);
          ic = Icons.directions_run_rounded;
        } else if (contentStr.contains('藥') || contentStr.contains('打卡') || eventType == 'medication') {
          badge = 'MEDICINE';
          col = const Color(0xFFA78BFA);
          glowCol = const Color(0xFF7C3AED);
          ic = Icons.medication_rounded;
        } else if (contentStr.contains('對話') || contentStr.contains('聊天') || contentStr.contains('小嘎') || contentStr.contains('寂寞') || eventType == 'mood') {
          badge = 'AI CHAT';
          col = const Color(0xFFF59E0B);
          glowCol = const Color(0xFFD97706);
          ic = Icons.favorite_rounded;
        }

        return {
          'id': log['log_id'] ?? log.hashCode,
          'time': timeStr,
          'date': dateStr,
          'badge': badge,
          'title': contentStr.length > 15 ? contentStr.substring(0, 15) + '...' : contentStr,
          'desc': contentStr,
          'fullQuery': '與 AI 長輩陪伴語音互動',
          'fullAi': contentStr,
          'isChat': badge == 'AI CHAT',
          'icon': ic,
          'color': col,
          'glow': glowCol,
        };
      }).toList();
    } else {
      rawFeedItems = [
        {
          'id': 1,
          'time': '16:45',
          'date': todayStr,
          'badge': 'NEWS',
          'title': '點閱收聽體育新聞',
          'desc': '長輩收聽熱門體育新聞《NBA熱火誤發詹姆斯加盟預告》，隨後發起 AI 語音問答交流 🏆',
          'isChat': false,
          'icon': Icons.sports_basketball_rounded,
          'color': const Color(0xFF38BDF8),
          'glow': const Color(0xFF0284C7),
        },
        {
          'id': 2,
          'time': '15:30',
          'date': todayStr,
          'badge': 'WALK',
          'title': '公園散步履約打卡',
          'desc': '在大安森林公園完成步數目標 3,850 步，達成今日規律健康標章 🏃‍♂️',
          'isChat': false,
          'icon': Icons.directions_run_rounded,
          'color': const Color(0xFF34D399),
          'glow': const Color(0xFF059669),
        },
        {
          'id': 3,
          'time': '14:00',
          'date': todayStr,
          'badge': 'AI CHAT',
          'title': '童年大稻埕布莊故事',
          'desc': '長輩與小嘎分享年輕時在大稻埕布莊當學徒的往事 💬',
          'fullQuery': '聊聊以前大稻埕布莊的事',
          'fullAi': '宇璿，您說您年輕時在布莊當學徒，那時候的布匹顏色跟質感真令人懷念！要不要再多說說當時最熱銷的布款呢？',
          'isChat': true,
          'icon': Icons.auto_stories_rounded,
          'color': const Color(0xFFF59E0B),
          'glow': const Color(0xFFD97706),
        },
        {
          'id': 4,
          'time': '11:20',
          'date': todayStr,
          'badge': 'CARE',
          'title': '收到女兒關懷',
          'desc': '收到女兒傳送的語音卡片：「爸，今晚想吃火鍋嗎？」💌',
          'isChat': false,
          'icon': Icons.favorite_rounded,
          'color': const Color(0xFFEC4899),
          'glow': const Color(0xFFBE185D),
        },
        {
          'id': 5,
          'time': '08:15',
          'date': todayStr,
          'badge': 'MEDICINE',
          'title': '晨間降壓藥與量血壓',
          'desc': '已按時服用【降血壓藥】乙顆，血壓 122 mmHg 狀態良好 💊',
          'isChat': false,
          'icon': Icons.medication_rounded,
          'color': const Color(0xFFA78BFA),
          'glow': const Color(0xFF7C3AED),
        },
        {
          'id': 6,
          'time': '昨天 19:30',
          'date': yesterdayStr,
          'badge': 'AI CHAT',
          'title': '晚間台語歌仔戲對話',
          'desc': '長輩與小嘎聊起《身騎白馬》歌詞與王寶釧故事 🎭',
          'fullQuery': '想聽聽歌仔戲身騎白馬',
          'fullAi': '好呀，宇璿！薛平貴騎著白馬過三關，這段戲曲真的是經典名作，您以前也很愛聽歌仔戲嗎？',
          'isChat': true,
          'icon': Icons.theater_comedy_rounded,
          'color': const Color(0xFFF59E0B),
          'glow': const Color(0xFFD97706),
        },
        {
          'id': 7,
          'time': '昨天 07:00',
          'date': yesterdayStr,
          'badge': 'ROUTINE',
          'title': '晨間點睛打卡',
          'desc': '長輩開啟 Uban 完成晨間打卡，精神狀態極佳 🌟',
          'isChat': false,
          'icon': Icons.wb_sunny_rounded,
          'color': const Color(0xFFFBBF24),
          'glow': const Color(0xFFD97706),
        },
      ];
    }

    final todayItems = rawFeedItems.where((i) => i['date'] == todayStr).toList();
    final yesterdayItems = rawFeedItems.where((i) => i['date'] == yesterdayStr).toList();

    List<Map<String, dynamic>> activeFilteredItems;
    if (_selectedDateFilterIndex == 0) {
      // 0: 預設全部歷來紀錄 (All Footprints)
      activeFilteredItems = rawFeedItems;
    } else if (_selectedDateFilterIndex == 1) {
      // 1: 今天
      activeFilteredItems = todayItems;
    } else if (_selectedDateFilterIndex == 2) {
      // 2: 昨天
      activeFilteredItems = yesterdayItems;
    } else {
      // 3: 歷史月曆選取
      if (_selectedHistoricalDate != null) {
        final targetStr = "${_selectedHistoricalDate!.year}-${_selectedHistoricalDate!.month.toString().padLeft(2, '0')}-${_selectedHistoricalDate!.day.toString().padLeft(2, '0')}";
        activeFilteredItems = rawFeedItems.where((i) => i['date'] == targetStr).toList();
      } else {
        activeFilteredItems = rawFeedItems;
      }
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與即時連線標籤
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF818CF8)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name 動態時光牆',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '目前共 ${activeFilteredItems.length} 筆生活足跡',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const _PulseDot(color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    Text(
                      '即時同步',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 日期篩選標籤 (預設選中「全部足跡」，點擊精準過濾)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateChip(
                  '🌐 全部足跡 (${rawFeedItems.length})',
                  isSelected: _selectedDateFilterIndex == 0,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 0);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  '📅 今天 (${todayItems.length})',
                  isSelected: _selectedDateFilterIndex == 1,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 1);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  '昨天 (${yesterdayItems.length})',
                  isSelected: _selectedDateFilterIndex == 2,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 2);
                  },
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  _selectedHistoricalDate != null
                      ? '🗓️ ${_selectedHistoricalDate!.month}/${_selectedHistoricalDate!.day}'
                      : '歷史月曆 🗓️',
                  isSelected: _selectedDateFilterIndex == 3,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedHistoricalDate ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF38BDF8),
                              onPrimary: Colors.white,
                              surface: Color(0xFF1E293B),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedHistoricalDate = picked;
                        _selectedDateFilterIndex = 3;
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 完美整合：時間軸發光節點 + AI 主題卡片合二為一 ───
          if (activeFilteredItems.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.event_note_rounded, color: Colors.white38, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    '該日期尚無長輩活動紀錄 🗓️',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊上方「🌐 全部足跡」觀看長輩完整歷史動態',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            ..._buildUnifiedTimelineCategoryCards(context, activeFilteredItems),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildDateChip(String label, {required bool isSelected, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildUnifiedTimelineCategoryCards(BuildContext context, List<Map<String, dynamic>> activeFilteredItems) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final apiClusters = _moodInsightData?['topic_clusters'] as List<dynamic>?;

    List<Map<String, dynamic>> categoriesToRender = [];

    if (apiClusters != null && apiClusters.isNotEmpty) {
      for (final cluster in apiClusters) {
        final title = cluster['title']?.toString() ?? '主題紀錄';
        final tagline = cluster['tagline']?.toString() ?? '';
        final previewSummary = cluster['preview_summary']?.toString() ?? '';
        final colorHexStr = cluster['color_hex']?.toString() ?? '0xFF38BDF8';
        final glowHexStr = cluster['glow_hex']?.toString() ?? '0xFF0284C7';
        final iconName = cluster['icon_name']?.toString() ?? '';
        final keywords = (cluster['match_keywords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

        final colorHex = int.tryParse(colorHexStr) ?? 0xFF38BDF8;
        final glowHex = int.tryParse(glowHexStr) ?? 0xFF0284C7;

        IconData iconData = Icons.auto_awesome_rounded;
        if (iconName.contains('sports') || iconName.contains('basketball')) {
          iconData = Icons.sports_basketball_rounded;
        } else if (iconName.contains('run') || iconName.contains('directions')) {
          iconData = Icons.directions_run_rounded;
        } else if (iconName.contains('favorite') || iconName.contains('heart')) {
          iconData = Icons.favorite_rounded;
        }

        final matchedItems = activeFilteredItems.where((item) {
          if (keywords.isEmpty) return true;
          final b = item['badge'].toString();
          final d = item['desc'].toString();
          final t = item['title'].toString();
          return keywords.any((k) => b.contains(k) || d.contains(k) || t.contains(k));
        }).toList();

        if (matchedItems.isNotEmpty) {
          categoriesToRender.add({
            'title': title,
            'icon': iconData,
            'color': Color(colorHex),
            'glow': Color(glowHex),
            'tagline': tagline,
            'previewSummary': previewSummary,
            'items': matchedItems,
          });
        }
      }
    }

    if (categoriesToRender.isEmpty) {
      final sportsItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('NBA') || d.contains('體育') || d.contains('新聞') || d.contains('賽事') || d.contains('詹姆斯');
      }).toList();

      if (sportsItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🏀 體育賽事與熱門新聞關注',
          'icon': Icons.sports_basketball_rounded,
          'color': const Color(0xFF38BDF8),
          'glow': const Color(0xFF0284C7),
          'tagline': '關注話題：NBA 球星交易與轉隊賽事討論 🏆',
          'previewSummary': '$name關注《NBA熱火誤發加盟預告》新聞，並與 AI 小嘎交流比賽戰況與球星動態。',
          'items': sportsItems,
        });
      }

      final healthItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('散步') || d.contains('步數') || d.contains('藥') || d.contains('打卡') || d.contains('作息');
      }).toList();

      if (healthItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '🏃‍♂️ 健康運動與日常作息保養',
          'icon': Icons.directions_run_rounded,
          'color': const Color(0xFF34D399),
          'glow': const Color(0xFF059669),
          'tagline': '作息狀態：公園散步達標 🏃‍♂️ • 降壓藥服用確認',
          'previewSummary': '在大安森林公園完成步數目標，晨間定時打卡與用藥完成，血壓控制良好。',
          'items': healthItems,
        });
      }

      final chatItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('對話') || d.contains('故事') || d.contains('女兒') || d.contains('關懷') || d.contains('聊天');
      }).toList();

      if (chatItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '💬 溫情陪伴與家族互動',
          'icon': Icons.favorite_rounded,
          'color': const Color(0xFFF59E0B),
          'glow': const Color(0xFFD97706),
          'tagline': '家族互動：收到女兒關懷卡片 💌 • 昔日記憶膠囊',
          'previewSummary': '$name與 AI 小嘎分享童年布莊回憶故事，並收到了來自女兒的溫馨聚餐語音卡片。',
          'items': chatItems,
        });
      }

      if (categoriesToRender.isEmpty) {
        categoriesToRender.add({
          'title': '🌟 每日生活足跡記錄',
          'icon': Icons.auto_awesome_rounded,
          'color': const Color(0xFF818CF8),
          'glow': const Color(0xFF4F46E5),
          'tagline': '生活狀態：開啟 Uban 保持健康互動 ✅',
          'previewSummary': '$name今日穩定使用系統，作息規律與狀況平穩。',
          'items': activeFilteredItems,
        });
      }
    }

    final categoriesList = categoriesToRender.asMap().entries.toList();

    return categoriesList.map((entry) {
      final idx = entry.key;
      final cat = entry.value;
      final isLast = idx == categoriesList.length - 1;
      final items = cat['items'] as List<Map<String, dynamic>>;
      final latestTime = items.isNotEmpty ? (items.first['time'] as String? ?? '') : '';

      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                if (latestTime.isNotEmpty) ...[
                  Text(
                    latestTime,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cat['color'] as Color,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E293B),
                    border: Border.all(color: cat['color'] as Color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (cat['glow'] as Color).withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(cat['icon'] as IconData, color: cat['color'] as Color, size: 18),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cat['color'] as Color,
                            Colors.white24,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _buildCategoryCard(
                  context,
                  categoryTitle: cat['title'] as String,
                  categoryIcon: cat['icon'] as IconData,
                  categoryColor: cat['color'] as Color,
                  glowColor: cat['glow'] as Color,
                  tagline: cat['tagline'] as String,
                  previewSummary: cat['previewSummary'] as String,
                  items: items,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String categoryTitle,
    required IconData categoryIcon,
    required Color categoryColor,
    required Color glowColor,
    required String tagline,
    required String previewSummary,
    required List<Map<String, dynamic>> items,
  }) {
    final count = items.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: categoryColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: categoryColor.withValues(alpha: 0.5)),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryTitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 11.5,
                        color: categoryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count 筆',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: categoryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            previewSummary,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              height: 1.45,
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: categoryColor.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: categoryColor.withValues(alpha: 0.6)),
                ),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _showCategoryDetailModal(
                  context,
                  categoryTitle: categoryTitle,
                  categoryIcon: categoryIcon,
                  categoryColor: categoryColor,
                  items: items,
                );
              },
              icon: const Icon(Icons.auto_stories_rounded, size: 16, color: Colors.white),
              label: Text(
                '🔍 點擊展開閱覽新聞與 AI 對話紀錄 ($count)',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 4. 警示預覽 ───

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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  if (widget.onNavigateToAlerts != null) {
                    widget.onNavigateToAlerts!();
                  } else if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => AlertCenterScreen(
                          elderName: widget.currentElder?.displayName ?? '長輩',
                          elderId: widget.currentElder?.id,
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

          ..._mockAlerts.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(bottom: e.key < _mockAlerts.length - 1 ? 10 : 0),
                child: _AlertItem(data: e.value, index: e.key),
              )),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}

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
