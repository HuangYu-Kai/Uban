import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../sheets/send_care_card_sheet.dart';

/// 🤖 AI 長輩情緒氣象台 & 破冰話題卡片
class HomeAiMoodRadarCard extends StatelessWidget {
  final Elder? currentElder;
  final Map<String, dynamic>? moodInsightData;
  final List<dynamic> realLogs;
  final VoidCallback? onStartVideoCall;
  final ValueChanged<String>? onCareMessageSent;
  final GlobalKey? aiMoodRadarKey;

  const HomeAiMoodRadarCard({
    super.key,
    this.currentElder,
    this.moodInsightData,
    this.realLogs = const [],
    this.onStartVideoCall,
    this.onCareMessageSent,
    this.aiMoodRadarKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = currentElder?.displayName ?? '長輩';
    final moodTitle = moodInsightData?['mood_title'] ?? '溫馨平穩';
    final moodScore = moodInsightData?['mood_score'] ?? 88;
    final moodIcon = moodInsightData?['mood_icon'] ?? '🍵';

    final String summaryText;
    final String icebreakerTopic;

    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final todayLogs = realLogs.where((log) => (log['timestamp']?.toString() ?? '').startsWith(todayStr)).toList();

    if (moodInsightData != null && moodInsightData!['summary'] != null && moodInsightData!['summary'].toString().isNotEmpty) {
      summaryText = moodInsightData!['summary'].toString();
      icebreakerTopic = moodInsightData!['icebreaker_topic']?.toString() ?? '$name！今天過得好嗎？撥個電話聽聽長輩的聲音關心一下吧！';
    } else if (todayLogs.isNotEmpty) {
      final hasWalk = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('散步') || (l['content']?.toString() ?? '').contains('步數'));
      final hasMed = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('藥'));
      final hasNews = todayLogs.any((l) => (l['content']?.toString() ?? '').contains('新聞'));

      List<String> acts = [];
      if (hasMed) acts.add('按時完成了晨間用藥打卡');
      if (hasWalk) acts.add('完成了公園散步運動');
      if (hasNews) acts.add('點閱收聽了熱門新聞');

      final actStr = acts.isNotEmpty ? acts.join('，且') : '作息非常規律';
      summaryText = '$name 今天情緒非常穩定愉快，$actStr！';
      icebreakerTopic = hasNews
          ? '$name！我今天看到熱門賽事新聞，感覺超精彩的！您最近也有在關注戰況嗎？'
          : '$name！聽說您今天有出門散步，公園空氣感覺怎麼樣呢？';
    } else {
      final lastLogDate = realLogs.isNotEmpty ? (realLogs.first['timestamp']?.toString() ?? '').substring(0, 10) : '';
      if (lastLogDate.length >= 10) {
        final m = lastLogDate.substring(5, 7);
        final d = lastLogDate.substring(8, 10);
        summaryText = '$name 今天尚未產生新的動態紀錄。最近一次紀錄於 $m/$d，作息狀況平穩！';
      } else {
        summaryText = '$name 今日尚無活動紀錄，撥個電話問候關心一下長輩吧！';
      }
      icebreakerTopic = '$name！今天過得好嗎？已有段時間沒聽到您的聲音，撥個電話問候關心您！';
    }

    return Container(
      key: aiMoodRadarKey,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部標題與情緒指標徽章
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.sentiment_satisfied_alt_rounded, color: cs.onPrimary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '長輩身心觀察',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '近期情緒與日常狀態',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 情緒指標 Badge
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$moodIcon ', style: const TextStyle(fontSize: 13)),
                      Flexible(
                        child: Text(
                          '$moodTitle ($moodScore%)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
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
              color: cs.onSurface,
            ),
          ),

          const SizedBox(height: 18),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 16),

          // 💡 關懷話題建議標題
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: isDark ? const Color(0xFFFDE24F) : cs.outline, size: 20),
              const SizedBox(width: 8),
              Text(
                '今日關懷話題建議：',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 溫馨金句卡（第一人稱溫情問候）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerHigh : const Color(0xFFFFF9DB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline, width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“',
                  style: TextStyle(
                    fontSize: 32,
                    height: 0.8,
                    fontWeight: FontWeight.w900,
                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    icebreakerTopic,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
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
                        backgroundColor: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: Text(
                          '📞 撥打關懷電話給$name',
                          style: GoogleFonts.notoSansTc(color: cs.onSurface, fontWeight: FontWeight.w800),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '💡 推薦聊天開場白：',
                              style: GoogleFonts.notoSansTc(color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                icebreakerTopic,
                                style: GoogleFonts.notoSansTc(color: cs.onSurface, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: Text('取消', style: GoogleFonts.notoSansTc(color: cs.outline)),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                            onPressed: () {
                              Navigator.pop(c);
                              final startCall = onStartVideoCall;
                              if (startCall != null) {
                                startCall();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('目前無法發起通話，請稍後再試', style: GoogleFonts.notoSansTc()),
                                    backgroundColor: const Color(0xFFEF4444),
                                  ),
                                );
                              }
                            },
                            icon: Icon(Icons.phone_rounded, color: cs.onPrimary, size: 18),
                            label: Text('開始撥號', style: GoogleFonts.notoSansTc(color: cs.onPrimary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: Icon(Icons.phone_in_talk_rounded, size: 18, color: cs.onPrimary),
                  label: Text(
                    '撥打電話聊聊',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimary,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 1,
                    shadowColor: cs.primary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => SendCareCardSheet.show(
                    context,
                    currentElder: currentElder,
                    elderName: name,
                    onCareMessageSent: onCareMessageSent,
                  ),
                  icon: Icon(Icons.mark_email_unread_rounded, size: 18, color: cs.outline),
                  label: Text(
                    '傳送關懷卡',
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w800,
                      color: cs.outline,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.tertiary,
                    foregroundColor: cs.outline,
                    elevation: 1,
                    shadowColor: cs.tertiary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
}
