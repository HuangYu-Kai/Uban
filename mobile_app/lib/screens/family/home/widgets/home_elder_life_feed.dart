import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/server_time.dart';
import '../../widgets/fam_ui.dart';
import '../models/activity_log_entry.dart';
import '../models/feed_grouping.dart';
import '../sheets/category_detail_sheet.dart';

/// 📸 長輩生活動態時光牆（日期篩選＋依日期、類型分組的動態卡）
///
/// ★ 2026-10-07：
/// - 移除上方「話題標籤雲」（用內容關鍵字猜主題，字級只看排列順序，沒有意義）。
/// - 移除「給個心意」（只改按鈕外觀並跳一句寫死的「已傳送女兒的心意」，什麼都沒送出）。
/// - 卡片改為「先分天、再依 event_type 分類」，說明只講實際筆數（見 [FeedGrouping]）。
/// - 時間改用 [ServerTime]：後端存 UTC、回傳不帶 Z，過去直接切字串會少 8 小時，
///   台灣早上 8 點前的紀錄還會被算到前一天。
class HomeElderLifeFeed extends StatefulWidget {
  final Elder? currentElder;
  final List<dynamic> realLogs;

  /// 保留參數以相容既有呼叫端；分組不再使用 AI 推論的主題（`topic_clusters`）。
  final Map<String, dynamic>? moodInsightData;

  const HomeElderLifeFeed({
    super.key,
    this.currentElder,
    this.realLogs = const [],
    this.moodInsightData,
  });

  @override
  State<HomeElderLifeFeed> createState() => _HomeElderLifeFeedState();
}

class _HomeElderLifeFeedState extends State<HomeElderLifeFeed> {
  int _selectedDateFilterIndex = 0; // 0: 全部, 1: 今天, 2: 昨天, 3: 歷史月曆
  DateTime? _selectedHistoricalDate;

  /// 把後端 activity_log 列轉成時光牆項目（時間換成本地時間）。
  static Map<String, dynamic> _toItem(
      dynamic log, String todayStr, String yesterdayStr) {
    final contentStr = log['content']?.toString() ?? '';
    final eventType = log['event_type']?.toString() ?? '';
    final tsStr = log['timestamp']?.toString() ?? '';
    final local = ServerTime.parse(tsStr);

    String dateStr = todayStr;
    String clock = '';
    String timeStr = '';
    if (local != null) {
      dateStr = ServerTime.dateKey(local);
      clock = ServerTime.clock(local);
      if (dateStr == todayStr) {
        timeStr = clock;
      } else if (dateStr == yesterdayStr) {
        timeStr = '昨天 $clock';
      } else {
        timeStr =
            '${dateStr.substring(5, 7)}/${dateStr.substring(8, 10)} $clock';
      }
    }

    String badge = 'LOG';
    if (eventType == 'news_view' ||
        eventType == 'news_query' ||
        contentStr.contains('新聞') ||
        contentStr.contains('NBA')) {
      badge = 'NEWS';
    } else if (eventType == 'youtube_query' ||
        contentStr.contains('YouTube') ||
        contentStr.contains('音樂') ||
        contentStr.contains('影片') ||
        contentStr.contains('歌曲')) {
      badge = 'MEDIA';
    } else if (contentStr.contains('散步') ||
        contentStr.contains('步數') ||
        contentStr.contains('運動') ||
        contentStr.contains('伸展') ||
        contentStr.contains('體操') ||
        contentStr.contains('健身') ||
        eventType == 'activity') {
      badge = 'WALK';
    } else if (contentStr.contains('藥') ||
        (contentStr.contains('打卡') &&
            !contentStr.contains('伸展') &&
            !contentStr.contains('運動')) ||
        eventType == 'medication') {
      badge = 'MEDICINE';
    } else if (contentStr.contains('對話') ||
        contentStr.contains('聊天') ||
        contentStr.contains('小嘎') ||
        contentStr.contains('寂寞') ||
        eventType == 'mood' ||
        eventType == 'chat') {
      badge = 'AI CHAT';
    }

    return {
      'id': log['log_id'] ?? log.hashCode,
      'rawTimestamp': tsStr,
      'sortTs': local,
      'time': timeStr,
      'clock': clock,
      'date': dateStr,
      'eventType': eventType,
      'badge': badge,
      'title': contentStr.length > 15
          ? '${contentStr.substring(0, 15)}...'
          : contentStr,
      'desc': contentStr,
      'fullQuery': '與 AI 長輩陪伴語音互動',
      'fullAi': contentStr,
      'isChat': badge == 'AI CHAT',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final name = widget.currentElder?.displayName ?? '長輩';
    final now = DateTime.now();
    final todayStr = ServerTime.dateKey(now);
    final yesterdayStr =
        ServerTime.dateKey(DateTime(now.year, now.month, now.day - 1));

    final itemsPool = [
      for (final log in widget.realLogs) _toItem(log, todayStr, yesterdayStr),
    ];

    final todayItems = itemsPool.where((i) => i['date'] == todayStr).toList();
    final yesterdayItems =
        itemsPool.where((i) => i['date'] == yesterdayStr).toList();

    List<Map<String, dynamic>> activeFilteredItems;
    if (_selectedDateFilterIndex == 0) {
      activeFilteredItems = itemsPool;
    } else if (_selectedDateFilterIndex == 1) {
      activeFilteredItems = todayItems;
    } else if (_selectedDateFilterIndex == 2) {
      activeFilteredItems = yesterdayItems;
    } else {
      if (_selectedHistoricalDate != null) {
        final targetStr = ServerTime.dateKey(_selectedHistoricalDate!);
        activeFilteredItems =
            itemsPool.where((i) => i['date'] == targetStr).toList();
      } else {
        activeFilteredItems = itemsPool;
      }
    }

    // 設計稿 `.card`＋`.sec-head`＋`.cloud`＋`.feed`：整塊一張卡，內容不放圖示。
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與即時連線標籤（標題可收縮：長輩名字長度不可控，鐵律 #14）
          FamSecHead(
            title: '$name 動態時光牆',
            trailing:
                const FamChip(label: '即時同步', tone: FamTone.brand, dot: true),
          ),
          const SizedBox(height: 2),
          Text(
            '目前共 ${activeFilteredItems.length} 筆生活足跡',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: famText(c.text2, 13.5),
          ),

          const SizedBox(height: 14),

          // 日期篩選
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FeedPill(
                  label: '全部 (${itemsPool.length})',
                  selected: _selectedDateFilterIndex == 0,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 0);
                  },
                ),
                const SizedBox(width: 8),
                _FeedPill(
                  label: '今天 (${todayItems.length})',
                  selected: _selectedDateFilterIndex == 1,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 1);
                  },
                ),
                const SizedBox(width: 8),
                _FeedPill(
                  label: '昨天 (${yesterdayItems.length})',
                  selected: _selectedDateFilterIndex == 2,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedDateFilterIndex = 2);
                  },
                ),
                const SizedBox(width: 8),
                _FeedPill(
                  label: _selectedHistoricalDate != null
                      ? '${_selectedHistoricalDate!.month}/${_selectedHistoricalDate!.day}'
                      : '歷史月曆',
                  selected: _selectedDateFilterIndex == 3,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    // 日期選擇器沿用家屬主題（不再硬塞深色）。
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedHistoricalDate ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
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

          const SizedBox(height: 12),

          if (activeFilteredItems.isEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Text(
                    '該搜尋條目尚無活動紀錄',
                    textAlign: TextAlign.center,
                    style: famText(c.text2, 14.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊上方「全部」觀看長輩完整歷史動態',
                    textAlign: TextAlign.center,
                    style: famText(c.text3, 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            ..._buildDayCards(
                context, activeFilteredItems, todayStr, yesterdayStr),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  List<Widget> _buildDayCards(
    BuildContext context,
    List<Map<String, dynamic>> items,
    String todayStr,
    String yesterdayStr,
  ) {
    final c = UbanColors.of(context);
    final widgets = <Widget>[];
    for (final day in FeedGrouping.group(items)) {
      final String dateLabel;
      if (day.date == todayStr) {
        dateLabel = '今日生活動態';
      } else if (day.date == yesterdayStr) {
        dateLabel = '昨天生活動態';
      } else if (day.date.length >= 10) {
        final m = int.tryParse(day.date.substring(5, 7)) ?? 0;
        final d = int.tryParse(day.date.substring(8, 10)) ?? 0;
        dateLabel = '$m月$d日 生活動態';
      } else {
        dateLabel = day.date;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            dateLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text3, 13,
                weight: FontWeight.w700, letterSpacing: 1.3),
          ),
        ),
      );
      for (final g in day.groups) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCategoryCard(
              context,
              categoryTitle: g.title,
              tagline: g.tagline,
              items: g.items,
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String categoryTitle,
    required String tagline,
    required List<Map<String, dynamic>> items,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = UbanColors.of(context);
    final count = items.length;

    // 卡內的區塊：surface2 底、圓角 20（不再巢狀加外框與陰影）。
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FamSecHead(
            title: categoryTitle,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count 筆',
                  maxLines: 1,
                  style: famText(c.text2, 12.5, weight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tagline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text2, 13.5, height: 1.45),
          ),

          const SizedBox(height: 8),

          // `.fitem`：左時間、右標題＋說明；項目間以 line 分隔。
          ...items.take(3).toList().asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final isLast = idx == (items.length > 3 ? 2 : items.length - 1);
            final parsed = ActivityLogParser.parseActivityLogItem(item, cs);

            final clockTime = item['clock']?.toString() ?? '';

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border:
                    isLast ? null : Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      clockTime,
                      maxLines: 1,
                      style: famText(c.text2, 14,
                          weight: FontWeight.w600, tabular: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parsed.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: famText(c.text, 15,
                              weight: FontWeight.w700, height: 1.3),
                        ),
                        if (parsed.subtitle != null &&
                            parsed.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            parsed.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text2, 13, height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 84),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        parsed.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text2, 12, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 10),

          FamButton(
            label: '查看紀錄 ($count)',
            kind: FamButtonKind.tonal,
            height: 46,
            onPressed: () {
              HapticFeedback.mediumImpact();
              showCategoryDetailModal(
                context,
                categoryTitle: categoryTitle,
                items: items,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 日期／篩選用的選取膠囊（選中＝淡品牌底＋品牌深字；未選＝surface2）。
class _FeedPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FeedPill({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.brandContainer : c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: famText(selected ? c.brandStrong : c.text2, 13.5,
              weight: selected ? FontWeight.w900 : FontWeight.w600),
        ),
      ),
    );
  }
}
