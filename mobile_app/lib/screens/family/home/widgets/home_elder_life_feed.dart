import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';
import '../models/activity_log_entry.dart';
import '../sheets/category_detail_sheet.dart';

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
    final c = UbanColors.of(context);
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

        if (eventType == 'news_view' || eventType == 'news_query' || contentStr.contains('新聞') || contentStr.contains('NBA')) {
          badge = 'NEWS';
        } else if (eventType == 'youtube_query' || contentStr.contains('YouTube') || contentStr.contains('音樂') || contentStr.contains('影片') || contentStr.contains('歌曲')) {
          badge = 'MEDIA';
        } else if (contentStr.contains('散步') || contentStr.contains('步數') || contentStr.contains('運動') || contentStr.contains('伸展') || contentStr.contains('體操') || contentStr.contains('健身') || eventType == 'activity') {
          badge = 'WALK';
        } else if (contentStr.contains('藥') || (contentStr.contains('打卡') && !contentStr.contains('伸展') && !contentStr.contains('運動')) || eventType == 'medication') {
          badge = 'MEDICINE';
        } else if (contentStr.contains('對話') || contentStr.contains('聊天') || contentStr.contains('小嘎') || contentStr.contains('寂寞') || eventType == 'mood' || eventType == 'chat') {
          badge = 'AI CHAT';
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

    // 設計稿 `.card`＋`.sec-head`＋`.cloud`＋`.feed`：整塊一張卡，內容不放圖示。
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與即時連線標籤（標題可收縮：長輩名字長度不可控，鐵律 #14）
          FamSecHead(
            title: '$name 動態時光牆',
            trailing: const FamChip(label: '即時同步', tone: FamTone.brand, dot: true),
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

          // 話題關鍵字雲（`.cloud`）
          _buildTopicPulseCloud(activeFilteredItems),

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

    void addTag(String tagLabel, String keyword) {
      final cleanKw = keyword.trim();
      if (cleanKw.isNotEmpty && !seenKeywords.contains(cleanKw)) {
        seenKeywords.add(cleanKw);
        tags.add({
          'tag': tagLabel,
          'keyword': cleanKw,
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
            addTag('📈 #台股焦點', '台股');
          } else if (fullText.contains('股票') || fullText.contains('股市')) {
            addTag('📈 #股市觀點', '股市');
          } else {
            addTag('📈 #財經趨勢', '財經');
          }
        }
        // 美食佳餚與料理食譜
        else if (fullText.contains('食譜') || fullText.contains('烹飪') || fullText.contains('做菜') || fullText.contains('美食') || fullText.contains('火鍋') || fullText.contains('料理')) {
          if (fullText.contains('火鍋')) {
            addTag('🍳 #火鍋佳餚', '火鍋');
          } else if (fullText.contains('食譜') || fullText.contains('做菜')) {
            addTag('🍳 #烹飪食譜', '食譜');
          } else {
            addTag('🍳 #美食料理', '美食');
          }
        }
        // 影音點播 (YouTube / 歌名 / 歌手)
        else if (badge == 'MEDIA' || fullText.contains('YouTube') || fullText.contains('音樂') || fullText.contains('歌曲')) {
          final match = RegExp(r'(?:YouTube 音樂/影片|歌曲|音樂)[：:\s]*([^\s|｜]+)').firstMatch(fullText);
          if (match != null) {
            final kw = match.group(1)!.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
            if (kw.length >= 2) {
              addTag('🎵 #$kw', kw);
              continue;
            }
          }
          addTag('🎵 #經典音樂', '音樂');
        }
        // 健康運動與作息
        else if (badge == 'WALK' || fullText.contains('運動') || fullText.contains('散步') || fullText.contains('步數')) {
          if (fullText.contains('散步')) {
            addTag('🌿 #戶外散步', '散步');
          } else if (fullText.contains('運動')) {
            addTag('🏃 #日常運動', '運動');
          } else if (fullText.contains('步數')) {
            addTag('👟 #健走步數', '步數');
          } else {
            addTag('🏃 #健康作息', '健康');
          }
        }
        // 熱門新聞點閱與關注
        else if (badge == 'NEWS' || fullText.contains('新聞')) {
          if (fullText.contains('NBA') || fullText.contains('體育') || fullText.contains('籃球') || fullText.contains('棒球')) {
            addTag('🏀 #體育賽事', '體育');
          } else if (fullText.contains('財經') || fullText.contains('股市') || fullText.contains('經濟')) {
            addTag('📈 #財經焦點', '財經');
          } else if (fullText.contains('影視') || fullText.contains('娛樂') || fullText.contains('明星')) {
            addTag('🎬 #影視娛樂', '娛樂');
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
            addTag('📰 #$tagLabel', tagKeyword);
          }
        }
        // 用藥提醒與健康打卡
        else if (badge == 'MEDICINE' || fullText.contains('藥') || fullText.contains('打卡')) {
          if (fullText.contains('血壓')) {
            addTag('💊 #血壓用藥', '血壓');
          } else if (fullText.contains('藥')) {
            addTag('💊 #按時服藥', '藥');
          } else {
            addTag('🌟 #晨間健康打卡', '打卡');
          }
        }
        // AI 陪伴與歷史回憶對話
        else if (badge == 'AI CHAT' || fullText.contains('對話') || fullText.contains('聊天') || fullText.contains('故事')) {
          if (fullText.contains('布莊') || fullText.contains('童年') || fullText.contains('往事')) {
            addTag('💬 #昔日記憶故事', '故事');
          } else if (fullText.contains('歌仔戲') || fullText.contains('戲曲')) {
            addTag('🎭 #歌仔戲曲', '歌仔戲');
          } else {
            addTag('💬 #AI親情對話', '對話');
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
    final c = UbanColors.of(context);
    // 設計稿 `.cloud`：字級高低錯落（13–19），品牌深色、粗體；選中者以淡品牌底表示。
    const sizes = [19.0, 14.0, 16.0, 13.0, 15.0];

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < dynamicTopics.length; i++)
          Builder(builder: (_) {
            final t = dynamicTopics[i];
            final isSelected = _selectedTopicKeyword == t['keyword'];
            // 標籤文字去掉開頭的表情與「#」。
            final label = (t['tag'] as String)
                .replaceAll(RegExp(r'^[^\w一-龥#]+'), '')
                .replaceFirst('#', '')
                .trim();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
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
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? c.brandContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: famText(c.brandStrong, sizes[i % sizes.length],
                      weight: FontWeight.w700),
                ),
              ),
            );
          }),
      ],
    );
  }

  List<Widget> _buildUnifiedTimelineCategoryCards(BuildContext context, List<Map<String, dynamic>> activeFilteredItems) {
    final c = UbanColors.of(context);
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
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
        final keywords = (cluster['match_keywords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

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
            'tagline': makeDynamicTagline(mediaLeftovers, '影音娛樂：點播喜愛的經典歌曲與影音 🎶'),
            'previewSummary': makeDynamicSummary(mediaLeftovers, '$name點播收聽影音娛樂內容。'),
            'items': mediaLeftovers,
          });
        }

        final remaining = unmatchedItems.where((i) => !mediaLeftovers.contains(i)).toList();
        if (remaining.isNotEmpty) {
          categoriesToRender.add({
            'title': '每日生活足跡記錄',
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
          'tagline': makeDynamicTagline(chatItems, '家族互動：陪伴對話與語音卡片 💌'),
          'previewSummary': makeDynamicSummary(chatItems, '$name與 AI 進行語音陪伴對話交流。'),
          'items': chatItems,
        });
      }

      if (categoriesToRender.isEmpty) {
        categoriesToRender.add({
          'title': '每日生活足跡記錄',
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
          dateLabel = '今日生活動態';
        } else if (rawDate == yesterdayStr) {
          dateLabel = '昨天生活動態';
        } else if (rawDate.length >= 10) {
          final m = int.tryParse(rawDate.substring(5, 7)) ?? 0;
          final d = int.tryParse(rawDate.substring(8, 10)) ?? 0;
          dateLabel = '$m月$d日 生活動態';
        } else {
          dateLabel = rawDate;
        }

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.3),
            ),
          ),
        );
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildCategoryCard(
            context,
            categoryTitle: cat['title'] as String,
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
    required String tagline,
    required String previewSummary,
    required List<Map<String, dynamic>> items,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = UbanColors.of(context);
    final count = items.length;
    final name = widget.currentElder?.displayName ?? '長輩';

    final cleanTitle = categoryTitle.replaceAll(RegExp(r'^[^\w一-龥]+'), '').trim();
    final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : categoryTitle;
    final bool liked = _likedCategories.contains(displayTitle);

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
            title: displayTitle,
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

          if (items.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                previewSummary.isNotEmpty ? previewSummary : '尚無相關紀錄',
                style: famText(c.text2, 14),
              ),
            ),
          ] else ...[
            // `.fitem`：左時間、右標題＋說明；項目間以 line 分隔。
            ...items.take(3).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isLast = idx == (items.length > 3 ? 2 : items.length - 1);
              final parsed = ActivityLogParser.parseActivityLogItem(item, cs);

              final rawTs = item['rawTimestamp']?.toString() ?? '';
              final clockTime = (rawTs.length >= 16)
                  ? rawTs.substring(11, 16)
                  : (parsed.timeText.contains(' ') ? parsed.timeText.split(' ').last : parsed.timeText);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: isLast ? null : Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        clockTime,
                        maxLines: 1,
                        style: famText(c.text2, 14, weight: FontWeight.w600, tabular: true),
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
                            style: famText(c.text, 15, weight: FontWeight.w700, height: 1.3),
                          ),
                          if (parsed.subtitle != null && parsed.subtitle!.isNotEmpty) ...[
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
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
          ],

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: FamButton(
                  label: '查看紀錄 ($count)',
                  kind: FamButtonKind.tonal,
                  height: 46,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    showCategoryDetailModal(
                      context,
                      categoryTitle: displayTitle,
                      items: items,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              FamButton(
                label: liked ? '已送心意' : '給個心意',
                kind: liked ? FamButtonKind.filled : FamButtonKind.ghost,
                height: 46,
                expand: false,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    if (_likedCategories.contains(displayTitle)) {
                      _likedCategories.remove(displayTitle);
                    } else {
                      _likedCategories.add(displayTitle);
                    }
                  });
                  // 外觀沿用家屬主題的 snackBarTheme（深底淺字、浮動）。
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '已傳送女兒的溫馨心意給 $name！❤️',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.surface, 14, weight: FontWeight.w700),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
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
