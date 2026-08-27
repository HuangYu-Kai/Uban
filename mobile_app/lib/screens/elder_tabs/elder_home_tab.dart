import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import '../almanac/farmer_almanac_screen.dart';
import '../news_listen_player/news_listen_player_screen.dart';
import '../../models/almanac_data_helper.dart';
import '../../services/api_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class ElderHomeTab extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  /// 切換到「聊天」分頁的回呼（首頁「和小雲聊天」大按鈕用）。
  final VoidCallback? onNavigateToChat;

  const ElderHomeTab({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
    this.onNavigateToChat,
  });

  @override
  State<ElderHomeTab> createState() => _ElderHomeTabState();
}

class _ElderHomeTabState extends State<ElderHomeTab> {
  late String _lunarDate;
  late String _solarTerm;
  late String _dayName;
  late String _dateStr;
  late String _monthStr;

  List<Map<String, dynamic>> _newsItems = [];
  bool _isLoadingNews = true;
  int _topNewsIndex = 0;

  /// 家屬是否已為這位長輩開通 PRO（真相在後端，見 SubscriptionService）。
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _fetchNews();
    _loadSubscription();
  }

  /// 長輩端的 roomId 即 elder_profile.elder_id（見 main.dart 的 elderIdUuid）。
  Future<void> _loadSubscription() async {
    final elderId = widget.roomId;
    if (elderId == null || elderId.isEmpty) return;
    final isPro = await SubscriptionService.isPro(elderId);
    if (mounted) setState(() => _isPro = isPro);
  }

  Future<void> _fetchNews({String? category}) async {
    final targetCategory = category ?? 'all';
    try {
      debugPrint('📡 正在抓取新聞... 類別: $targetCategory, 網址: ${ApiService.baseUrl}/news');
      var parsed = <Map<String, dynamic>>[];

      // 動態抓取指定類別 (limit 為 30 符合目前前端設計)
      final allResponse =
          await ApiService.getNews(category: targetCategory, limit: 30);

      final allSuccess = allResponse['status'] == 'success';
      if (allSuccess) {
        parsed = _parseNewsItems(allResponse);
        debugPrint('✅ 抓取成功，取得 ${parsed.length} 則新聞');
      } else {
        debugPrint('❌ 抓取失敗: ${allResponse['message']}');
      }

      // 如果 'all' 為空，嘗試手動匯總 (Fallback)
      if (parsed.isEmpty && targetCategory == 'all') {
        parsed = await _fetchNewsByMultipleCategories();
      }

      // 仍然為空則抓 politics 作為保底
      if (parsed.isEmpty) {
        final fallback =
            await ApiService.getNews(category: 'politics', limit: 30);
        parsed = _parseNewsItems(fallback);
      }

      final deduped = _dedupeNewsItems(parsed).take(30).toList();

      if (mounted) {
        setState(() {
          _newsItems = deduped;
          _isLoadingNews = false;
          // 適老化：顯示最新一則頭條，不自動輪播（避免長輩困惑）。
          _topNewsIndex = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingNews = false);
      }
    }
  }

  List<Map<String, dynamic>> _parseNewsItems(Map<String, dynamic> response) {
    final data = response['data'];
    final items = (data is Map ? data['items'] : null);
    final parsed = <Map<String, dynamic>>[];
    if (items is List) {
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          parsed.add(item);
        } else if (item is Map) {
          parsed.add(item.map((key, value) => MapEntry(key.toString(), value)));
        }
      }
    }
    return parsed;
  }

  Future<List<Map<String, dynamic>>> _fetchNewsByMultipleCategories() async {
    final categories = <String>[
      'politics',
      'international',
      'finance',
      'technology',
      'life',
      'society',
      'sports',
      'entertainment',
      'culture',
      'local',
      'china',
    ];
    final responses = await Future.wait(
      categories.map((c) => ApiService.getNews(category: c, limit: 2)),
    );
    final merged = <Map<String, dynamic>>[];
    for (final response in responses) {
      if (response['status'] == 'success') {
        merged.addAll(_parseNewsItems(response));
      }
    }
    return merged;
  }

  void _updateTime() {
    final now = DateTime.now();
    final lunar = Lunar.fromDate(now);

    setState(() {
      _lunarDate = "${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}";
      _solarTerm = lunar.getJieQi();
      if (_solarTerm.isEmpty) {
        _solarTerm = "立春";
      }

      try {
        _dayName = DateFormat('EEEE', 'zh_TW').format(now);
        _dateStr = DateFormat('dd').format(now);
        _monthStr = DateFormat('MM月', 'zh_TW').format(now);
      } catch (e) {
        debugPrint('DateFormat error: $e');
        _dayName = "星期${['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1]}";
        _dateStr = now.day.toString().padLeft(2, '0');
        _monthStr = "${now.month}月";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 頂部封面漸層（Figma：55B695 → FFFFFF）
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF55B695), Color(0xFFFFFFFF)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 52), // 第一層：teal 封面帶
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 第二層：DFFFF4 → 白（偏左、右側內縮露出圓角，往上露出一截）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 58,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFDFFFF4), Color(0xFFFFFFFF)],
                          stops: [0.0, 0.5],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // 第三層：DDE6DE 主內容 sheet（往下 offset，露出第二層）
                  Positioned(
                    top: 42,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFDDE6DE),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 44),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildElderDateCard(),
                                const SizedBox(height: AppSpacing.lg),
                                _buildFeaturedNewsCard(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 會員徽章 + 頭像（浮在右上、坐在第三層 sheet 上緣）
                  Positioned(
                    top: 20,
                    right: 20,
                    child: _buildHeader(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHeader() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 會員徽章：只有已訂閱才亮金豬，未訂閱不顯示（不做銀/銅階）
        if (_isPro) ...[
          _buildMembershipBadge(),
          const SizedBox(width: 10),
        ],
        // 使用者頭像
        Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/user_avatar.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.person_rounded, color: AppColors.primary, size: 36),
            ),
          ),
        ),
      ],
    );
  }

  /// 訂閱徽章膠囊（金豬會員）。
  /// 只有一階：家屬已為長輩開通 PRO 就亮金豬，未訂閱則整個膠囊不顯示。
  /// （不做銀豬 / 銅豬分級；assets 內的 silver/bronze 圖暫時用不到。）
  Widget _buildMembershipBadge() {
    const String tierLabel = '金豬會員';
    const String badgeAsset = 'assets/images/pig_badge_gold.png';
    const Color pillColor = Color(0xFFFFF1C4);
    const Color textColor = Color(0xFF9A6B1E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Image.asset(
              badgeAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Text('🐷', style: TextStyle(fontSize: 24))),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tierLabel,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 大日期卡片（毛玻璃，點擊跳轉至農民曆與神明誕辰）。
  Widget _buildElderDateCard() {
    final now = DateTime.now();
    final almanac = AlmanacDataHelper.calculateForDate(now);

    // 提煉今日精華摘要（神誕 / 宜忌精簡）
    String summaryText;
    if (almanac.hasDeityBirthday) {
      final deityName = almanac.deities.first.name;
      summaryText = '🌟 今日【$deityName】・宜 ${almanac.yiList.take(2).join('、')}';
    } else if (almanac.yiList.isNotEmpty && almanac.jiList.isNotEmpty) {
      summaryText = '📜 今日農民曆：宜 ${almanac.yiList.take(2).join('、')} ｜ 忌 ${almanac.jiList.take(2).join('、')}';
    } else {
      summaryText = '📜 點此查看今日農民曆・神明誕辰與吉凶';
    }

    return GlassCard(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FarmerAlmanacScreen(
              initialDate: DateTime.now(),
              userName: widget.userName,
            ),
          ),
        );
      },
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_monthStr$_dateStr日',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _dayName,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _lunarDate,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _solarTerm,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 🌿 農民曆與神明吉凶資訊導引列（薄荷綠毛玻璃質感，融於首頁主視覺）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summaryText,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 單一大頭條新聞卡（大圖 + 大標 + 全寬「唸給我聽」+ 看更多）。
  /// 只重做呈現，新聞抓取與 TTS 聆聽功能沿用既有邏輯。
  Widget _buildFeaturedNewsCard() {
    Widget header = Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '今日頭條',
          style: GoogleFonts.notoSansTc(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );

    if (_isLoadingNews) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ElderScale.cardRadius),
            ),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_newsItems.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ElderScale.cardRadius),
            ),
            child: Text('目前沒有新聞，稍後再看看', style: ElderScale.body),
          ),
        ],
      );
    }

    // 頭條優先挑「有圖片」的新聞當背景；都沒有才退回第一則
    bool itemHasImage(Map<String, dynamic> it) {
      final u = ((it['image_url'] ?? it['image']) ?? '').toString().trim();
      return u.startsWith('http://') || u.startsWith('https://');
    }

    final item = _newsItems.firstWhere(
      itemHasImage,
      orElse: () => _newsItems[_topNewsIndex % _newsItems.length],
    );
    final imageUrl =
        ((item['image_url'] ?? item['image']) ?? '').toString().trim();
    final hasImage = itemHasImage(item);
    final title = (item['title'] ?? '無標題').toString();

    // 無圖時的實心底
    Widget fallbackBg = Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Icon(
        Icons.newspaper_rounded,
        size: 90,
        color: Colors.white.withValues(alpha: 0.25),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        // 整塊卡片可點 → 聆聽新聞畫面
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openNewsListenPlayer(item),
            borderRadius: BorderRadius.circular(ElderScale.cardRadius),
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ElderScale.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景大圖（或漸層底）
                  if (hasImage)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : fallbackBg,
                      errorBuilder: (_, __, ___) => fallbackBg,
                    )
                  else
                    fallbackBg,
                  // 底部深色漸層，讓標題看得清楚
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x33000000),
                          Color(0xCC000000),
                        ],
                        stops: [0.3, 0.6, 1.0],
                      ),
                    ),
                  ),
                  // 「點我聆聽」提示
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.headphones_rounded,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 6),
                          Text(
                            '點我聆聽',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 標題壓在圖片底部
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 看更多新聞 → 新聞列表
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openNewsListFromTopEntry,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '看更多新聞',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.primaryDark, size: 26),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _orderedNewsItemsWithTopFirst() {
    if (_newsItems.isEmpty) return const [];
    final topIndex = _topNewsIndex % _newsItems.length;
    final topItem = _newsItems[topIndex];
    final seenKeys = <String>{_newsIdentityKey(topItem)};
    final others = <Map<String, dynamic>>[];
    for (var i = 0; i < _newsItems.length; i++) {
      if (i == topIndex) continue;
      final item = _newsItems[i];
      final key = _newsIdentityKey(item);
      if (seenKeys.contains(key)) continue;
      seenKeys.add(key);
      others.add(item);
    }
    others.sort((a, b) => _newsSortScore(b).compareTo(_newsSortScore(a)));
    return [topItem, ...others];
  }

  List<Map<String, dynamic>> _dedupeNewsItems(
      List<Map<String, dynamic>> items) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final item in items) {
      final key = _newsIdentityKey(item);
      if (seen.contains(key)) continue;
      seen.add(key);
      deduped.add(item);
    }
    deduped.sort((a, b) => _newsSortScore(b).compareTo(_newsSortScore(a)));
    return deduped;
  }

  String _newsIdentityKey(Map<String, dynamic> item) {
    final sourceUrl = (item['source_url'] ?? '').toString().trim();
    final title = (item['title'] ?? '').toString().trim();
    if (sourceUrl.isNotEmpty) return sourceUrl;
    return title;
  }

  int _newsSortScore(Map<String, dynamic> item) {
    final published =
        DateTime.tryParse((item['published_at'] ?? '').toString());
    if (published != null) return published.millisecondsSinceEpoch;
    final raw = (item['published_at_raw'] ?? '').toString();
    final rawDate =
        DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    if (rawDate != null) return rawDate.millisecondsSinceEpoch;
    final updated = DateTime.tryParse((item['updated_at'] ?? '').toString());
    if (updated != null) return updated.millisecondsSinceEpoch;
    return 0;
  }

  // 看更多新聞：進聆聽頁並自動展開新聞列表面板
  void _openNewsListFromTopEntry() {
    if (_newsItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有可瀏覽的新聞')),
      );
      return;
    }
    final currentTop = _newsItems[_topNewsIndex % _newsItems.length];
    _openNewsListenPlayer(currentTop, startExpanded: true);
  }

  // 點頭條卡：進聆聽頁，停在聆聽（面板收合）
  void _openNewsListenPlayer(Map<String, dynamic> currentItem,
      {bool startExpanded = false}) {
    final playlist = _orderedNewsItemsWithTopFirst().take(30).toList();
    if (playlist.isEmpty) return;
    final currentKey = _newsIdentityKey(currentItem);
    final initialIndex =
        playlist.indexWhere((item) => _newsIdentityKey(item) == currentKey);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewsListenPlayerScreen(
          newsItems: playlist,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
          userId: widget.userId,
          startExpanded: startExpanded,
        ),
      ),
    );
  }

}
