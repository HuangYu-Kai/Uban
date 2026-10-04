import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';
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
    final c = UbanColors.of(context);
    final name = currentElder?.displayName ?? '長輩';
    final moodTitle = moodInsightData?['mood_title'] ?? '溫馨平穩';
    final moodScore = moodInsightData?['mood_score'] ?? 88;

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

    final double? scoreNum = double.tryParse('$moodScore');
    final double meter = ((scoreNum ?? 0) / 100).clamp(0.0, 1.0);

    return FamCard(
      key: aiMoodRadarKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 設計稿 `.mood`：分數方塊＋標籤＋心情標題＋細進度條。
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.brandContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '$moodScore',
                  maxLines: 1,
                  style: famText(c.brandStrong, 22, weight: FontWeight.w700, tabular: true),
                ),
              ),
              const SizedBox(width: 14),
              // ★ 鐵律 #14：心情標題為後端字串，需可收縮。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('長輩身心觀察',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(
                      '$moodTitle',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 18, weight: FontWeight.w900, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: meter,
                        minHeight: 8,
                        backgroundColor: c.surface3,
                        color: c.brandFill,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 情緒分析描述
          Text(
            summaryText,
            style: famText(c.text, 15, height: 1.6),
          ),

          const SizedBox(height: 14),
          Text('今天可以聊',
              style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 8),

          // 話題列（不放 spark 圖示）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              icebreakerTopic,
              style: famText(c.text, 14.5, height: 1.5),
            ),
          ),

          const SizedBox(height: 14),

          // 方案 B：直接動作按鈕 (Action Buttons)
          Row(
            children: [
              Expanded(
                child: FamButton(
                  label: '撥打電話聊聊',
                  height: 48,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    showDialog(
                      context: context,
                      builder: (c2) => AlertDialog(
                        title: Text(
                          '撥打關懷電話給$name',
                          style: famText(c.text, 18, weight: FontWeight.w900),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '推薦聊天開場白',
                              style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: c.surface2,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                icebreakerTopic,
                                style: famText(c.text, 15, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c2),
                            child: Text('取消', style: famText(c.text2, 15, weight: FontWeight.w700)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(c2);
                              final startCall = onStartVideoCall;
                              if (startCall != null) {
                                startCall();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('目前無法發起通話，請稍後再試',
                                        style: famText(Colors.white, 14)),
                                    backgroundColor: c.danger,
                                  ),
                                );
                              }
                            },
                            child: const Text('開始撥號'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FamButton(
                  label: '傳送關懷卡',
                  kind: FamButtonKind.tonal,
                  height: 48,
                  onPressed: () => SendCareCardSheet.show(
                    context,
                    currentElder: currentElder,
                    elderName: name,
                    onCareMessageSent: onCareMessageSent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }
}
