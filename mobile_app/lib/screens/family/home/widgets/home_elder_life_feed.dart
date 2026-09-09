import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../models/activity_log_entry.dart';
import '../sheets/category_detail_sheet.dart';
import 'home_pulse_dot.dart';

/// 📸 長輩生活動態時光牆 (包含話題關鍵字雲、日期篩選與類別動態卡)
class HomeElderLifeFeed extends StatefulWidget {
  final Elder? currentElder;
  final List<dynamic> realLogs;
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
  final Set<String> _likedCategories = {};
  String? _selectedTopicKeyword;
  int _selectedDateFilterIndex = 0; // 0: 全部, 1: 今天, 2: 昨天, 3: 歷史月曆
  DateTime? _selectedHistoricalDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = widget.currentElder?.displayName ?? '長輩';
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    List<Map<String, dynamic>> rawFeedItems = [];

    if (widget.realLogs.isNotEmpty) {
      rawFeedItems = widget.realLogs.map((log) {
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

        if (eventType == 'news_view' || eventType == 'news_query' || contentStr.contains('新聞') || contentStr.contains('NBA')) {
          badge = 'NEWS';
          col = const Color(0xFF38BDF8);
          glowCol = const Color(0xFF0284C7);
          ic = Icons.sports_basketball_rounded;
        } else if (eventType == 'youtube_query' || contentStr.contains('YouTube') || contentStr.contains('音樂') || contentStr.contains('影片') || contentStr.contains('歌曲')) {
          badge = 'MEDIA';
          col = const Color(0xFFF43F5E);
          glowCol = const Color(0xFFBE123C);
          ic = Icons.play_circle_fill_rounded;
        } else if (contentStr.contains('散步') || contentStr.contains('步數') || contentStr.contains('運動') || contentStr.contains('伸展') || contentStr.contains('體操') || contentStr.contains('健身') || eventType == 'activity') {
          badge = 'WALK';
          col = const Color(0xFF34D399);
          glowCol = const Color(0xFF059669);
          ic = Icons.directions_run_rounded;
        } else if (contentStr.contains('藥') || (contentStr.contains('打卡') && !contentStr.contains('伸展') && !contentStr.contains('運動')) || eventType == 'medication') {
          badge = 'MEDICINE';
          col = const Color(0xFFA78BFA);
          glowCol = const Color(0xFF7C3AED);
          ic = Icons.medication_rounded;
        } else if (contentStr.contains('對話') || contentStr.contains('聊天') || contentStr.contains('小嘎') || contentStr.contains('寂寞') || eventType == 'mood' || eventType == 'chat') {
          badge = 'AI CHAT';
          col = const Color(0xFFF59E0B);
          glowCol = const Color(0xFFD97706);
          ic = Icons.favorite_rounded;
        }

        return {
          'id': log['log_id'] ?? log.hashCode,
          'rawTimestamp': tsStr,
          'time': timeStr,
          'date': dateStr,
          'badge': badge,
          'title': contentStr.length > 15 ? '${contentStr.substring(0, 15)}...' : contentStr,
          'desc': contentStr,
          'fullQuery': '與 AI 長輩陪伴語音互動',
          'fullAi': contentStr,
          'isChat': badge == 'AI CHAT',
          'icon': ic,
          'color': col,
          'glow': glowCol,
        };
      }).toList();
    }

    // Filter by topic keyword if selected
    List<Map<String, dynamic>> itemsPool = rawFeedItems;
    if (_selectedTopicKeyword != null) {
      final kw = _selectedTopicKeyword!.trim().toLowerCase();
      itemsPool = rawFeedItems.where((i) {
        final b = i['badge']?.toString().toLowerCase() ?? '';
        final t = i['title']?.toString() ?? '';
        final d = i['desc']?.toString() ?? '';
        final fullText = '$b $t $d';

        if (fullText.contains(kw)) return true;

        if ((kw == '影音' || kw == '音樂' || kw.contains('音樂')) &&
            (fullText.contains('音樂') || fullText.contains('影音') || fullText.contains('歌曲') || fullText.contains('youtube') || b == 'media')) {
          return true;
        }
        if ((kw == '散步' || kw == '運動' || kw == '健走') &&
            (fullText.contains('散步') || fullText.contains('運動') || fullText.contains('步數') || b == 'walk')) {
          return true;
        }
        if ((kw == '新聞' || kw == '體育') &&
            (fullText.contains('新聞') || fullText.contains('體育') || fullText.contains('nba') || b == 'news')) {
          return true;
        }
        if ((kw == '對話' || kw == '故事' || kw == '聊天') &&
            (fullText.contains('對話') || fullText.contains('故事') || fullText.contains('聊天') || fullText.contains('小嘎') || b == 'ai chat')) {
          return true;
        }
        if ((kw == '藥' || kw == '血壓' || kw == '打卡') &&
            (fullText.contains('藥') || fullText.contains('血壓') || fullText.contains('打卡') || b == 'medicine')) {
          return true;
        }

        return false;
      }).toList();
    }

    final todayItems = itemsPool.where((i) => i['date'] == todayStr).toList();
    final yesterdayItems = itemsPool.where((i) => i['date'] == yesterdayStr).toList();

    List<Map<String, dynamic>> activeFilteredItems;
    if (_selectedDateFilterIndex == 0) {
      activeFilteredItems = itemsPool;
    } else if (_selectedDateFilterIndex == 1) {
      activeFilteredItems = todayItems;
    } else if (_selectedDateFilterIndex == 2) {
      activeFilteredItems = yesterdayItems;
    } else {
      if (_selectedHistoricalDate != null) {
        final targetStr = "${_selectedHistoricalDate!.year}-${_selectedHistoricalDate!.month.toString().padLeft(2, '0')}-${_selectedHistoricalDate!.day.toString().padLeft(2, '0')}";
        activeFilteredItems = itemsPool.where((i) => i['date'] == targetStr).toList();
      } else {
        activeFilteredItems = itemsPool;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
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
          // 標題與即時連線標籤
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
                      child: Icon(Icons.grid_view_rounded, color: cs.onPrimary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name 動態時光牆',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '目前共 ${activeFilteredItems.length} 筆生活足跡',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13.5,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline, width: 1.2),
                ),
                child: Row(
                  children: [
                    HomePulseDot(color: cs.secondary),
                    const SizedBox(width: 6),
                    Text(
                      '即時同步',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 📅 日期篩選標籤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateChip(
                  '🌐 全部足跡 (${itemsPool.length})',
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
                      : '歷史月曆',
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

          const SizedBox(height: 12),

          // 🏷️ 特色功能 1：長輩熱情話題關鍵字雲 (Topic Pulse Cloud)
          _buildTopicPulseCloud(activeFilteredItems),

          const SizedBox(height: 20),

          // ─── 時間軸發光節點 + AI 主題卡片合二為一 ───
          if (activeFilteredItems.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.event_note_rounded, color: Colors.white38, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    '該搜尋條目尚無活動紀錄 🗓️',
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

  List<Map<String, dynamic>> _extractDynamicTopicTags(
    List<Map<String, dynamic>> rawFeedItems,
    dynamic moodInsightData,
    String elderInterests,
  ) {
    List<Map<String, dynamic>> tags = [];
    final Set<String> seenKeywords = {};

    void addTag(String tagLabel, String keyword, Color color) {
      final cleanKw = keyword.trim();
      if (cleanKw.isNotEmpty && !seenKeywords.contains(cleanKw)) {
        seenKeywords.add(cleanKw);
        tags.add({
          'tag': tagLabel,
          'keyword': cleanKw,
          'color': color,
        });
      }
    }

    if (rawFeedItems.isNotEmpty) {
      for (final item in rawFeedItems) {
        final desc = item['desc']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';
        final badge = item['badge']?.toString() ?? '';
        final fullText = '$title $desc';

        // 財經與台股投資
        if (fullText.contains('財經') || fullText.contains('台股') || fullText.contains('股票') || fullText.contains('股市') || fullText.contains('投資') || fullText.contains('理財')) {
          if (fullText.contains('台股')) {
            addTag('📈 #台股焦點', '台股', const Color(0xFF10B981));
          } else if (fullText.contains('股票') || fullText.contains('股市')) {
            addTag('📈 #股市觀點', '股市', const Color(0xFF10B981));
          } else {
            addTag('📈 #財經趨勢', '財經', const Color(0xFF10B981));
          }
        }
        // 美食佳餚與料理食譜
        else if (fullText.contains('食譜') || fullText.contains('烹飪') || fullText.contains('做菜') || fullText.contains('美食') || fullText.contains('火鍋') || fullText.contains('料理')) {
          if (fullText.contains('火鍋')) {
            addTag('🍳 #火鍋佳餚', '火鍋', const Color(0xFFFB923C));
          } else if (fullText.contains('食譜') || fullText.contains('做菜')) {
            addTag('🍳 #烹飪食譜', '食譜', const Color(0xFFFB923C));
          } else {
            addTag('🍳 #美食料理', '美食', const Color(0xFFFB923C));
          }
        }
        // 影音點播 (YouTube / 歌名 / 歌手)
        else if (badge == 'MEDIA' || fullText.contains('YouTube') || fullText.contains('音樂') || fullText.contains('歌曲')) {
          final match = RegExp(r'(?:YouTube 音樂/影片|歌曲|音樂)[：:\s]*([^\s|｜]+)').firstMatch(fullText);
          if (match != null) {
            final kw = match.group(1)!.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
            if (kw.length >= 2) {
              addTag('🎵 #$kw', kw, const Color(0xFFF43F5E));
              continue;
            }
          }
          addTag('🎵 #經典音樂', '音樂', const Color(0xFFF43F5E));
        }
        // 健康運動與作息
        else if (badge == 'WALK' || fullText.contains('運動') || fullText.contains('散步') || fullText.contains('步數')) {
          if (fullText.contains('散步')) {
            addTag('🌿 #戶外散步', '散步', const Color(0xFF34D399));
          } else if (fullText.contains('運動')) {
            addTag('🏃 #日常運動', '運動', const Color(0xFF34D399));
          } else if (fullText.contains('步數')) {
            addTag('👟 #健走步數', '步數', const Color(0xFF34D399));
          } else {
            addTag('🏃 #健康作息', '健康', const Color(0xFF34D399));
          }
        }
        // 熱門新聞點閱與關注
        else if (badge == 'NEWS' || fullText.contains('新聞')) {
          if (fullText.contains('NBA') || fullText.contains('體育') || fullText.contains('籃球') || fullText.contains('棒球')) {
            addTag('🏀 #體育賽事', '體育', const Color(0xFF38BDF8));
          } else if (fullText.contains('財經') || fullText.contains('股市') || fullText.contains('經濟')) {
            addTag('📈 #財經焦點', '財經', const Color(0xFF38BDF8));
          } else if (fullText.contains('影視') || fullText.contains('娛樂') || fullText.contains('明星')) {
            addTag('🎬 #影視娛樂', '娛樂', const Color(0xFF38BDF8));
          } else {
            final match = RegExp(r'【([^】]+)】').firstMatch(fullText);
            var tagLabel = '熱門時事';
            var tagKeyword = '新聞';
            if (match != null) {
              final cat = match.group(1)!.replaceAll('新聞', '').replaceAll('點閱', '').trim();
              if (cat.isNotEmpty && cat != 'all') {
                tagLabel = '$cat新聞';
                tagKeyword = cat;
              }
            }
            addTag('📰 #$tagLabel', tagKeyword, const Color(0xFF38BDF8));
          }
        }
        // 用藥提醒與健康打卡
        else if (badge == 'MEDICINE' || fullText.contains('藥') || fullText.contains('打卡')) {
          if (fullText.contains('血壓')) {
            addTag('💊 #血壓用藥', '血壓', const Color(0xFFA78BFA));
          } else if (fullText.contains('藥')) {
            addTag('💊 #按時服藥', '藥', const Color(0xFFA78BFA));
          } else {
            addTag('🌟 #晨間健康打卡', '打卡', const Color(0xFFA78BFA));
          }
        }
        // AI 陪伴與歷史回憶對話
        else if (badge == 'AI CHAT' || fullText.contains('對話') || fullText.contains('聊天') || fullText.contains('故事')) {
          if (fullText.contains('布莊') || fullText.contains('童年') || fullText.contains('往事')) {
            addTag('💬 #昔日記憶故事', '故事', const Color(0xFFF59E0B));
          } else if (fullText.contains('歌仔戲') || fullText.contains('戲曲')) {
            addTag('🎭 #歌仔戲曲', '歌仔戲', const Color(0xFFF59E0B));
          } else {
            addTag('💬 #AI親情對話', '對話', const Color(0xFFF59E0B));
          }
        }
      }
    }

    return tags;
  }

  Widget _buildTopicPulseCloud(List<Map<String, dynamic>> rawFeedItems) {
    if (rawFeedItems.isEmpty) return const SizedBox.shrink();
    final dynamicTopics = _extractDynamicTopicTags(rawFeedItems, widget.moodInsightData, '');

    if (dynamicTopics.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: dynamicTopics.map((t) {
          final isSelected = _selectedTopicKeyword == t['keyword'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (_selectedTopicKeyword == t['keyword']) {
                    _selectedTopicKeyword = null;
                  } else {
                    _selectedTopicKeyword = t['keyword'] as String;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: cs.outline,
                          width: 1.2,
                        ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  t['tag'] as String,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateChip(String label, {required bool isSelected, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(
                  color: cs.outline,
                  width: 1.2,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildUnifiedTimelineCategoryCards(BuildContext context, List<Map<String, dynamic>> activeFilteredItems) {
    final name = widget.currentElder?.displayName ?? '長輩';
    final apiClusters = widget.moodInsightData?['topic_clusters'] as List<dynamic>?;

    String makeDynamicTagline(List<Map<String, dynamic>> items, String fallback, {String? categoryTitle}) {
      if (items.isEmpty) return fallback;
      final count = items.length;
      final title = categoryTitle ?? fallback;
      if (title.contains('健康') || title.contains('作息') || title.contains('運動')) {
        final medCount = items.where((i) => "${i['title']} ${i['desc']}".contains('藥')).length;
        final exerciseCount = items.where((i) => "${i['title']} ${i['desc']}".contains('運動') || "${i['title']} ${i['desc']}".contains('步') || "${i['title']} ${i['desc']}".contains('伸展')).length;
        if (medCount > 0 && exerciseCount > 0) {
          return '今日作息規律，已完成 $medCount 次用藥打卡與 $exerciseCount 項健康運動';
        } else if (medCount > 0) {
          return '今日作息規律，已按時完成 $medCount 次用藥打卡';
        } else if (exerciseCount > 0) {
          return '今日健康活力充沛，已完成 $exerciseCount 項日常伸展與運動';
        }
        return '今日健康狀態良好，累計完成 $count 項日常作息';
      }
      if (title.contains('新聞') || title.contains('體育') || title.contains('賽事')) {
        return '長輩重點關注熱門時事與體育賽事動態 ($count 則)';
      }
      if (title.contains('影音') || title.contains('音樂') || title.contains('娛樂')) {
        return '長輩點播聆聽了 $count 首經典歌曲與娛樂影音';
      }
      if (title.contains('陪伴') || title.contains('對話') || title.contains('溫情')) {
        return '長輩與 AI 陪伴對話互動 $count 次，互動狀況良好';
      }
      return '累計 $count 筆最新生活足跡記錄';
    }

    String makeDynamicSummary(List<Map<String, dynamic>> items, String fallback) {
      if (items.isEmpty) return fallback;
      final descs = items.map((i) => i['desc']?.toString() ?? '').where((d) => d.isNotEmpty).toList();
      if (descs.isEmpty) return fallback;
      return descs.take(2).join('； ');
    }

    List<Map<String, dynamic>> categoriesToRender = [];

    if (apiClusters != null && apiClusters.isNotEmpty) {
      final Set<int> matchedItemIds = {};

      for (final cluster in apiClusters) {
        final title = cluster['title']?.toString() ?? '主題紀錄';
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
        } else if (iconName.contains('play') || iconName.contains('music')) {
          iconData = Icons.play_circle_fill_rounded;
        } else if (iconName.contains('trending') || iconName.contains('chart') || iconName.contains('finance')) {
          iconData = Icons.trending_up_rounded;
        } else if (iconName.contains('restaurant') || iconName.contains('food')) {
          iconData = Icons.restaurant_rounded;
        }

        final matchedItems = activeFilteredItems.where((item) {
          if (keywords.isEmpty) return true;
          final b = item['badge'].toString();
          final d = item['desc'].toString();
          final t = item['title'].toString();
          return keywords.any((k) => b.contains(k) || d.contains(k) || t.contains(k));
        }).toList();

        if (matchedItems.isNotEmpty) {
          for (final it in matchedItems) {
            final itemId = it['id'];
            if (itemId is int) {
              matchedItemIds.add(itemId);
            }
          }
          categoriesToRender.add({
            'title': title,
            'icon': iconData,
            'color': Color(colorHex),
            'glow': Color(glowHex),
            'tagline': makeDynamicTagline(matchedItems, '$title 相關動態'),
            'previewSummary': makeDynamicSummary(matchedItems, '$name今日關心 $title。'),
            'items': matchedItems,
          });
        }
      }

      final unmatchedItems = activeFilteredItems.where((item) {
        final id = item['id'];
        return id == null || (id is int && !matchedItemIds.contains(id));
      }).toList();

      if (unmatchedItems.isNotEmpty) {
        final mediaLeftovers = unmatchedItems.where((i) {
          final d = "${i['title']} ${i['desc']} ${i['badge']}";
          return d.contains('YouTube') || d.contains('影音') || d.contains('音樂') || d.contains('歌曲') || d.contains('歌') || d.contains('MEDIA');
        }).toList();

        if (mediaLeftovers.isNotEmpty) {
          categoriesToRender.add({
            'title': '音樂影音與娛樂點播',
            'icon': Icons.play_circle_fill_rounded,
            'color': const Color(0xFFF43F5E),
            'glow': const Color(0xFFBE123C),
            'tagline': makeDynamicTagline(mediaLeftovers, '影音娛樂：點播喜愛的經典歌曲與影音 🎶'),
            'previewSummary': makeDynamicSummary(mediaLeftovers, '$name點播收聽影音娛樂內容。'),
            'items': mediaLeftovers,
          });
        }

        final remaining = unmatchedItems.where((i) => !mediaLeftovers.contains(i)).toList();
        if (remaining.isNotEmpty) {
          categoriesToRender.add({
            'title': '每日生活足跡記錄',
            'icon': Icons.auto_awesome_rounded,
            'color': const Color(0xFF818CF8),
            'glow': const Color(0xFF4F46E5),
            'tagline': makeDynamicTagline(remaining, '生活狀態：保持健康互動 ✅'),
            'previewSummary': makeDynamicSummary(remaining, '$name今日生活足跡與活動紀錄。'),
            'items': remaining,
          });
        }
      }
    }

    if (categoriesToRender.isEmpty) {
      final financeItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('財經') || d.contains('台股') || d.contains('股票') || d.contains('股市') || d.contains('投資') || d.contains('理財');
      }).toList();

      if (financeItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '財經觀點與台股投資',
          'icon': Icons.trending_up_rounded,
          'color': const Color(0xFF10B981),
          'glow': const Color(0xFF059669),
          'tagline': makeDynamicTagline(financeItems, '財經焦點：股市與財經資訊 📊'),
          'previewSummary': makeDynamicSummary(financeItems, '$name關心財經市場與台股動態。'),
          'items': financeItems,
        });
      }

      final foodItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('食譜') || d.contains('烹飪') || d.contains('做菜') || d.contains('美食') || d.contains('火鍋') || d.contains('料理');
      }).toList();

      if (foodItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '美食佳餚與餐飲食譜交流',
          'icon': Icons.restaurant_rounded,
          'color': const Color(0xFFFB923C),
          'glow': const Color(0xFFC2410C),
          'tagline': makeDynamicTagline(foodItems, '飲食點滴：美食與健康食譜 🥗'),
          'previewSummary': makeDynamicSummary(foodItems, '$name關注分享日常飲食料理。'),
          'items': foodItems,
        });
      }

      final sportsItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('NBA') || d.contains('體育') || d.contains('新聞') || d.contains('賽事') || d.contains('詹姆斯');
      }).toList();

      if (sportsItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '體育賽事與熱門新聞關注',
          'icon': Icons.sports_basketball_rounded,
          'color': const Color(0xFF38BDF8),
          'glow': const Color(0xFF0284C7),
          'tagline': makeDynamicTagline(sportsItems, '關注新聞：體育與球賽資訊 🏆'),
          'previewSummary': makeDynamicSummary(sportsItems, '$name收聽關注熱門新聞點閱紀錄。'),
          'items': sportsItems,
        });
      }

      final healthItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('散步') || d.contains('步數') || d.contains('藥') || d.contains('打卡') || d.contains('作息') || d.contains('運動') || d.contains('活動') || d.contains('WALK');
      }).toList();

      if (healthItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '健康運動與日常作息保養',
          'icon': Icons.directions_run_rounded,
          'color': const Color(0xFF34D399),
          'glow': const Color(0xFF059669),
          'tagline': makeDynamicTagline(healthItems, '作息狀態：健康打卡與運動 🏃‍♂️'),
          'previewSummary': makeDynamicSummary(healthItems, '$name按時完成晨間打卡與健康運動。'),
          'items': healthItems,
        });
      }

      final mediaItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('YouTube') || d.contains('影音') || d.contains('音樂') || d.contains('歌曲') || d.contains('歌') || d.contains('MEDIA');
      }).toList();

      if (mediaItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '音樂影音與娛樂點播',
          'icon': Icons.play_circle_fill_rounded,
          'color': const Color(0xFFF43F5E),
          'glow': const Color(0xFFBE123C),
          'tagline': makeDynamicTagline(mediaItems, '影音娛樂：點播喜愛的經典歌曲與影音 🎶'),
          'previewSummary': makeDynamicSummary(mediaLeftoversSafe(activeFilteredItems), '$name點播收聽影音娛樂內容。'),
          'items': mediaItems,
        });
      }

      final chatItems = activeFilteredItems.where((i) {
        final d = "${i['title']} ${i['desc']} ${i['badge']}";
        return d.contains('對話') || d.contains('故事') || d.contains('女兒') || d.contains('關懷') || d.contains('聊天') || d.contains('說說話') || d.contains('AI CHAT');
      }).toList();

      if (chatItems.isNotEmpty) {
        categoriesToRender.add({
          'title': '溫情陪伴與家族互動',
          'icon': Icons.favorite_rounded,
          'color': const Color(0xFFF59E0B),
          'glow': const Color(0xFFD97706),
          'tagline': makeDynamicTagline(chatItems, '家族互動：陪伴對話與語音卡片 💌'),
          'previewSummary': makeDynamicSummary(chatItems, '$name與 AI 進行語音陪伴對話交流。'),
          'items': chatItems,
        });
      }

      if (categoriesToRender.isEmpty) {
        categoriesToRender.add({
          'title': '每日生活足跡記錄',
          'icon': Icons.auto_awesome_rounded,
          'color': const Color(0xFF818CF8),
          'glow': const Color(0xFF4F46E5),
          'tagline': makeDynamicTagline(activeFilteredItems, '生活狀態：保持健康互動 ✅'),
          'previewSummary': makeDynamicSummary(activeFilteredItems, '$name今日穩定使用系統，作息規律與狀況平穩。'),
          'items': activeFilteredItems,
        });
      }
    }

    // 嚴格由新到舊排序
    categoriesToRender.sort((a, b) {
      final itemsA = a['items'] as List<Map<String, dynamic>>?;
      final itemsB = b['items'] as List<Map<String, dynamic>>?;
      final tsA = (itemsA != null && itemsA.isNotEmpty) ? (itemsA.first['rawTimestamp'] ?? itemsA.first['time'] ?? '') : '';
      final tsB = (itemsB != null && itemsB.isNotEmpty) ? (itemsB.first['rawTimestamp'] ?? itemsB.first['time'] ?? '') : '';
      return tsB.toString().compareTo(tsA.toString());
    });

    final List<Widget> widgets = [];
    String? lastRenderedDate;

    for (final cat in categoriesToRender) {
      final items = cat['items'] as List<Map<String, dynamic>>? ?? [];
      final firstItem = items.isNotEmpty ? items.first : null;
      final rawDate = firstItem?['date']?.toString() ?? '';

      if (rawDate.isNotEmpty && rawDate != lastRenderedDate) {
        lastRenderedDate = rawDate;
        String dateLabel;
        if (rawDate == todayStr) {
          dateLabel = '📅 今日生活動態';
        } else if (rawDate == yesterdayStr) {
          dateLabel = '📅 昨天生活動態';
        } else if (rawDate.length >= 10) {
          final m = int.tryParse(rawDate.substring(5, 7)) ?? 0;
          final d = int.tryParse(rawDate.substring(8, 10)) ?? 0;
          dateLabel = '📅 $m月$d日 生活動態';
        } else {
          dateLabel = '📅 $rawDate';
        }

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    dateLabel,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.15),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
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
      );
    }

    return widgets;
  }

  List<Map<String, dynamic>> mediaLeftoversSafe(List<Map<String, dynamic>> items) {
    return items.where((i) {
      final d = "${i['title']} ${i['desc']} ${i['badge']}";
      return d.contains('YouTube') || d.contains('影音') || d.contains('音樂') || d.contains('歌曲') || d.contains('MEDIA');
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = items.length;
    final name = widget.currentElder?.displayName ?? '長輩';

    final cleanTitle = categoryTitle.replaceAll(RegExp(r'^[^\w\u4e00-\u9fa5]+'), '').trim();
    final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : categoryTitle;

    return Container(
      padding: const EdgeInsets.all(18),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(categoryIcon, color: cs.onPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13.5,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count 筆',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (items.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                previewSummary.isNotEmpty ? previewSummary : '尚無相關紀錄',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ] else ...[
            ...items.take(3).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isLast = idx == (items.length > 3 ? 2 : items.length - 1);
              final parsed = ActivityLogParser.parseActivityLogItem(item, cs);

              final rawTs = item['rawTimestamp']?.toString() ?? '';
              final clockTime = (rawTs.length >= 16)
                  ? rawTs.substring(11, 16)
                  : (parsed.timeText.contains(' ') ? parsed.timeText.split(' ').last : parsed.timeText);

              final badgeTextColor = isDark
                  ? parsed.themeColor
                  : () {
                      final hsl = HSLColor.fromColor(parsed.themeColor);
                      return hsl.withLightness((hsl.lightness * 0.72).clamp(0.2, 0.45)).toColor();
                    }();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (clockTime.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
                                  : cs.outline.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              clockTime,
                              style: GoogleFonts.inter(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: parsed.themeColor.withValues(alpha: isDark ? 0.25 : 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(parsed.icon, size: 16, color: parsed.themeColor),
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
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                  height: 1.3,
                                ),
                              ),
                              if (parsed.subtitle != null && parsed.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  parsed.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: parsed.themeColor.withValues(alpha: isDark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            parsed.statusText,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 12,
                      thickness: 0.8,
                      color: cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.15),
                    ),
                ],
              );
            }),
          ],

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    showCategoryDetailModal(
                      context,
                      categoryTitle: displayTitle,
                      categoryIcon: categoryIcon,
                      categoryColor: categoryColor,
                      items: items,
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_stories_rounded, color: cs.onPrimary, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '查看紀錄 ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14.0,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, color: cs.onPrimary, size: 11),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    if (_likedCategories.contains(displayTitle)) {
                      _likedCategories.remove(displayTitle);
                    } else {
                      _likedCategories.add(displayTitle);
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.favorite_rounded, color: cs.secondary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已傳送女兒的溫馨心意給 $name！❤️',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(color: cs.onSurface, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: cs.surface,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: cs.outline, width: 1.5),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _likedCategories.contains(displayTitle)
                        ? cs.secondary.withValues(alpha: 0.15)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _likedCategories.contains(displayTitle) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _likedCategories.contains(displayTitle) ? cs.secondary : cs.outline,
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _likedCategories.contains(displayTitle) ? '已送心意' : '給個心意',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _likedCategories.contains(displayTitle) ? cs.secondary : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
