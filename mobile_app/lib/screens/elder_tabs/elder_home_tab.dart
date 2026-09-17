import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../almanac/farmer_almanac_screen.dart';
import '../news_listen_player/news_listen_player_screen.dart';
import '../../models/almanac_data_helper.dart';
import '../../models/chinese_converter.dart';
import '../../services/api_service.dart';
import '../../services/subscription_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/reminder_schedule.dart';
import '../../widgets/glass_card.dart';

class ElderHomeTab extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  /// 切換到「聊天」分頁的回呼（首頁「和小雲聊天」大按鈕用）。
  final VoidCallback? onNavigateToChat;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey。全部選填、預設
  //   null——GlobalKey 必須由上層 ElderHomeScreen 持有並傳入（IndexedStack
  //   保活導致本頁 initState 只會跑一次，無法自行偵測「使用者第一次切到本
  //   頁」，判斷邏輯因此留在上層，詳見 elder_home_screen.dart）。傳 null 時
  //   完全不影響現有畫面。
  final GlobalKey? dateCardKey;
  final GlobalKey? newsCardKey;
  final GlobalKey? moreNewsKey;

  const ElderHomeTab({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
    this.onNavigateToChat,
    this.dateCardKey,
    this.newsCardKey,
    this.moreNewsKey,
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

  // ★ B1c：天氣卡片狀態。
  WeatherInfo? _weatherInfo;
  bool _isLoadingWeather = true;

  // ★ B1c：下一筆提醒卡片狀態。
  List<Map<String, dynamic>> _reminders = [];
  Set<int> _completedReminderIds = {};
  bool _isLoadingNextDose = true;
  // ★ 第四十九輪：讀取失敗與「真的沒有提醒／都完成了」原本是同一種畫面
  // （`_reminders` 維持空陣列，`_buildNextDoseCard` 看到 `next == null` 就顯示
  // 「今天的提醒都完成了 🌟」）。長輩開 App 那一刻網路不穩，會被誤導成「今天
  // 沒有藥要吃」。這個旗標讓兩者在畫面上分開顯示，見 [_buildNextDoseCard]。
  bool _hasNextDoseLoadError = false;
  // 本頁在 IndexedStack 底下保活、initState 只會跑一次（見上方
  // `dateCardKey` 的說明）——代表若冷啟動當下第一次讀取就失敗，沒有任何
  // 其他觸發點會再試一次，長輩會在整個 session 都看到錯誤卡片。因此失敗時
  // 額外安排最多一次自動重試（見 [_loadNextDoseData] 尾端），而不是只改文案。
  int _nextDoseLoadAttempt = 0;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _fetchNews();
    _loadSubscription();
    _fetchWeather();
    _loadNextDoseData();
  }

  /// 抓取天氣（見 [WeatherService]）。內含快取與失敗兜底，這裡只負責
  /// 顯示讀取狀態並在拿到結果後更新畫面。
  Future<void> _fetchWeather() async {
    final info = await WeatherService.getWeather(widget.userId);
    if (!mounted) return;
    setState(() {
      _weatherInfo = info;
      _isLoadingWeather = false;
    });
  }

  /// 載入「下一筆待辦提醒」卡片所需資料：長輩的排程提醒清單 + 今天已完成
  /// 的打卡紀錄。
  ///
  /// ⚠️ 提醒清單一律用 `widget.roomId`（長輩端的 roomId 即
  /// elder_profile.elder_id，見上方類別註解與 main.dart 的 elderIdUuid），
  /// 不可用 `widget.userId`（DB 整數 PK）——兩者是不同的鍵，`elder_profile_tab.dart`
  /// 的 `_loadElderReminders` 對此有詳細說明（第四十三輪修復的鍵不匹配 bug）。
  Future<void> _loadNextDoseData() async {
    _nextDoseLoadAttempt++;
    final elderId = widget.roomId;
    if (elderId == null || elderId.isEmpty) {
      // 拿不到 elderId 不是「今天沒有提醒」，是「還不知道長輩是誰」——同樣
      // 不該顯示慶祝文案，比照下面 catch 分支處理（含自動重試，見尾端說明）。
      if (mounted) {
        setState(() {
          _isLoadingNextDose = false;
          _hasNextDoseLoadError = true;
        });
      }
      _scheduleNextDoseRetry();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final completedList = prefs.getStringList('completed_tasks_$today') ?? [];
      final completedIds =
          completedList.map((e) => int.tryParse(e) ?? -1).toSet();

      final list = await ApiService.getElderReminders(elderId);
      if (!mounted) return;
      setState(() {
        _reminders = List<Map<String, dynamic>>.from(list);
        _completedReminderIds = completedIds;
        _isLoadingNextDose = false;
        _hasNextDoseLoadError = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNextDose = false;
          _hasNextDoseLoadError = true;
        });
      }
      _scheduleNextDoseRetry();
    }
  }

  /// 讀取失敗時安排最多一次自動重試。本頁在 `IndexedStack` 下 initState
  /// 只跑一次，若不主動再試，冷啟動當下的一次網路不穩就會讓卡片錯誤畫面
  /// 卡住一整個 session（見 [_hasNextDoseLoadError] 的說明）。只重試一次
  /// （`_nextDoseLoadAttempt < 2`），避免對持續離線的裝置無限重試。
  void _scheduleNextDoseRetry() {
    if (_nextDoseLoadAttempt >= 2) return;
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) _loadNextDoseData();
    });
  }

  /// 打卡：同時做「本機立即生效」＋「背景同步後端」兩件事——
  /// App 目前有兩條各自獨立的打卡路徑（「我的」分頁的清單只寫本機
  /// SharedPreferences；提醒彈窗只打 API），本卡片兩邊都寫，才能讓首頁卡片
  /// 與「我的」分頁看到一致的完成狀態。
  Future<void> _completeNextDose(Map<String, dynamic> reminder) async {
    final id = int.tryParse(reminder['id']?.toString() ?? '');
    if (id == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _completedReminderIds.add(id));

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setStringList(
      'completed_tasks_$today',
      _completedReminderIds.map((e) => e.toString()).toList(),
    );

    // ★ 第四十九輪修復：這裡是「先更新本機再同步後端」的樂觀更新（點下去
    // 畫面立刻打勾），過去用 unawaited 完全不管成不成功——網路失敗時畫面
    // 照樣顯示打卡完成，家屬端資料庫其實沒有這筆用藥紀錄，是用藥安全
    // 問題。改成 await 讀 bool，失敗時把上面剛寫入的兩份樂觀更新狀態都
    // 回退（記憶體中的 _completedReminderIds、SharedPreferences 的
    // completed_tasks_<today>），並提示使用者可以再按一次。
    // ApiService.completeElderReminder 內部已經把逾時／連線失敗／後端
    // 錯誤全部吞成 false、不會對外拋例外（見 reminder_api.dart），這裡的
    // try/catch 只是防禦未來改版又開始拋例外，不能取代讀 bool。
    bool success;
    try {
      success = await ApiService.completeElderReminder(id);
    } catch (e) {
      debugPrint('⚠️ [ElderHomeTab] completeElderReminder 例外: $e');
      success = false;
    }
    if (!mounted) return;
    if (!success) {
      setState(() => _completedReminderIds.remove(id));
      await prefs.setStringList(
        'completed_tasks_$today',
        _completedReminderIds.map((e) => e.toString()).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '打卡沒有送出成功，請確認網路後再按一次「打卡」',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFFB91C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
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
      debugPrint(
          '📡 正在抓取新聞... 類別: $targetCategory, 網址: ${ApiService.baseUrl}/news');
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
      // ★ getJieQi() 只在「今天剛好是節氣當天」才回傳名稱，其餘約 360 天
      //   都回空字串。原本的 fallback 寫死「立春」，等於一年到頭首頁都在
      //   跟長輩說現在是立春——九月中顯示立春是明確的錯誤資訊。
      //   改用 getPrevJieQi(true) 取「當前所處的節氣區間」，才是長輩要看的。
      _solarTerm = lunar.getJieQi();
      if (_solarTerm.isEmpty) {
        try {
          _solarTerm = lunar.getPrevJieQi(true).getName();
        } catch (e) {
          // 取不到就留空，由 ElderDateSummaryRow 自行省略，
          // 絕不再用寫死的節氣冒充。
          debugPrint('⚠️ [ElderHomeTab] 取得當前節氣失敗: $e');
          _solarTerm = '';
        }
      }
      // ★ 第四十九輪：`lunar` 套件的 24 節氣表本身是簡體字，其中「驚蟄／
      // 處暑／芒種／穀雨／小滿」這 5 個（每個約 15 天、一年約 75 天）沒有
      // 特別轉繁體。兩條路徑（上面直接命中的 getJieQi()、下面 fallback 的
      // getPrevJieQi）都可能回傳簡體，因此在兩者匯流之後、只包一次，涵蓋
      // 全部情況——同一套修法已用在 models/almanac_data_helper.dart（農民曆
      // 頁面），這裡是本頁首頁卡片獨立的第二處，兩者是不同檔案、必須分開改。
      _solarTerm = ChineseConverter.toTraditional(_solarTerm);

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
                                // ★ 一屏到底修復：首頁只留三塊（今天卡／下一包藥／新聞），
                                // 天氣併入今天卡、日期卡與天氣卡合一，新聞卡壓成精簡列，
                                // 移除跟底部導覽列「電話」分頁重複的「打電話給家人」大按鈕。
                                _buildTodayCard(),
                                const SizedBox(height: AppSpacing.lg),
                                _buildNextDoseCard(),
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
              errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 36),
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
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
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
              errorBuilder: (_, __, ___) => const Center(
                  child: Text('🐷', style: TextStyle(fontSize: 24))),
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

  /// 「今天」卡右半天氣直欄（回應林阿公「看不到天氣」的抱怨）。
  ///
  /// ★ 一屏到底修復：原本獨立一張天氣 [GlassCard] 併入日期／農民曆卡，
  /// 此方法只回傳右半內容，容器由 [_buildTodayCard] 統一提供。
  /// 讀取中顯示精簡佔位；失敗（[WeatherService] 回傳 null）只讓「這半邊」
  /// 顯示平靜的「稍後再試」文案並塌陷，左半日期／農民曆長條不受影響——
  /// 刻意不做任何看起來像錯誤/警示的紅色狀態，這位長輩容易被警告字樣嚇到。
  /// ★ 天氣圖示必須跟著實際天氣走。原本寫死 Icons.wb_sunny_rounded，
  /// 下雨天會在「陰雨綿綿」旁邊畫一顆太陽——對看不清小字的長輩來說，
  /// 圖示才是主要訊號，畫錯等於給錯出門建議。
  /// 分級與 WeatherService 的三段文案同源（降雨 <20 / <50 / 其餘）。
  IconData _weatherIcon(WeatherInfo w) {
    if (w.rainProbability >= 50) return Icons.umbrella_rounded;
    if (w.rainProbability >= 20) return Icons.grain_rounded;
    return Icons.wb_sunny_rounded;
  }

  Color _weatherIconColor(WeatherInfo w) {
    if (w.rainProbability >= 50) return const Color(0xFF4A6FA5);
    if (w.rainProbability >= 20) return const Color(0xFF6B8CBE);
    return AppColors.accent;
  }

  Widget _buildWeatherHalf() {
    if (_isLoadingWeather) {
      return const Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    final weather = _weatherInfo;
    if (weather == null) {
      return Text(
        '天氣資訊暫時看不到，稍後再試',
        style: ElderScale.caption,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ⚠️ 溫度區間是動態字串、跟圖示同列，包 Flexible／ellipsis 避免窄
        // 螢幕溢位。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_weatherIcon(weather),
                size: 22, color: _weatherIconColor(weather)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${weather.minTemp.round()}°–${weather.maxTemp.round()}°',
                style: GoogleFonts.notoSansTc(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${weather.condition}・降雨${weather.rainProbability}%',
          style: ElderScale.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
        // ★ 第四十九輪：WeatherInfo.isFromCache 之前定義了卻從沒被畫面讀過
        // （全 repo 搜尋只有 weather_service.dart 自己的定義處）——連線失敗
        // 時頂替的舊資料，長輩看起來跟剛查到的一模一樣。現在補上這行小字，
        // 只在 isFromCache 為 true 時顯示，不影響平常（新資料）的畫面。
        if (weather.isFromCache) ...[
          const SizedBox(height: 2),
          Text(
            '（上次查到的資料）',
            style: ElderScale.caption.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ],
      ],
    );
  }

  /// 下一筆待辦提醒卡片，回應林陳阿嬤「只想看下一筆藥」的需求。
  ///
  /// 視覺選擇：沿用首頁既有的 teal/slate 語言（[GlassCard] + [AppColors]），
  /// 而不是「我的」分頁提醒清單用的暖色系（bg 0xFFFFFDF9／border
  /// 0xFFEADBCE）——理由是本卡片與同一版面上的天氣卡、日期卡、新聞卡並排，
  /// 沿用暖色會讓整頁風格分裂成兩套系統；暖色系留給「我的」分頁自己的
  /// 清單語境即可。
  Widget _buildNextDoseCard() {
    if (_isLoadingNextDose) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '提醒讀取中…',
                style: ElderScale.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final next = nextDue(_reminders, _completedReminderIds, DateTime.now());
    if (next == null) {
      // ★ 第四十九輪：「讀取失敗」與「真的沒有提醒／都已完成」以前是同一張卡片
      // （`_reminders` 空陣列時兩者都會走到這裡），長輩開 App 那一刻網路不穩
      // 會被誤導成「今天沒有藥要吃」。改用 [_hasNextDoseLoadError] 分流成兩種
      // 語氣不同的文案：讀取失敗用中性圖示與措辭，不使用 🌟 慶祝語氣。
      if (_hasNextDoseLoadError) {
        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 28, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '提醒暫時讀不到，請確認網路連線',
                  style: ElderScale.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          children: [
            const Text('🌟', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '今天的提醒都完成了 🌟',
                style: ElderScale.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final category = (next['category'] ?? '').toString();
    final emoji = _reminderEmoji(category);
    final timeStr = (next['time_str'] ?? '').toString();
    final title = (next['title'] ?? '提醒').toString();

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          // ⚠️ 時間＋標題同列且皆為動態長度（後端自訂文字），包 Expanded／
          // ellipsis 避免窄螢幕溢位。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: ElderScale.sectionTitle
                      .copyWith(color: AppColors.primaryDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: ElderScale.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _completeNextDose(next),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              '打卡',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提醒分類對應的 emoji 圖示。無法辨識的分類一律回傳鬧鐘，跟「我的」
  /// 分頁其他提醒相關畫面的預設圖示保持一致的保守作法。
  String _reminderEmoji(String category) {
    switch (category) {
      case 'medication':
        return '💊';
      case 'water':
        return '🚰';
      case 'exercise':
        return '🚶';
      default:
        return '⏰';
    }
  }

  /// 「今天」卡（毛玻璃，日期／農曆＋天氣合一，點擊跳轉至農民曆與神明誕辰）。
  ///
  /// ★ 一屏到底修復：原本天氣卡與日期／農曆卡是首頁兩張獨立的卡片（合計
  /// 約 359px），現在合成一張約 168px 的卡片——左半沿用既有
  /// [ElderDateSummaryRow]（完全不改它的原始碼，只用外層 [Expanded] 縮減
  /// 可用寬度，讓它自己既有的 [FittedBox] 等比縮小保護視需要接手）、右半
  /// 是新的 [_buildWeatherHalf]。[FarmerAlmanacScreen] 的唯一入口——底部的
  /// 農民曆長條——原封不動保留在卡片下半部。
  Widget _buildTodayCard() {
    final now = DateTime.now();
    final almanac = AlmanacDataHelper.calculateForDate(now);

    // 提煉今日精華摘要（神誕 / 宜忌精簡）
    String summaryText;
    if (almanac.hasDeityBirthday) {
      final deityName = almanac.deities.first.name;
      summaryText = '🌟 今日【$deityName】・宜 ${almanac.yiList.take(2).join('、')}';
    } else if (almanac.yiList.isNotEmpty && almanac.jiList.isNotEmpty) {
      summaryText =
          '📜 今日農民曆：宜 ${almanac.yiList.take(2).join('、')} ｜ 忌 ${almanac.jiList.take(2).join('、')}';
    } else {
      summaryText = '📜 點此查看今日農民曆・神明誕辰與吉凶';
    }

    return GlassCard(
      key: widget.dateCardKey,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ElderDateSummaryRow(
                  monthStr: _monthStr,
                  dateStr: _dateStr,
                  dayName: _dayName,
                  lunarDate: _lunarDate,
                  solarTerm: _solarTerm,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _buildWeatherHalf()),
            ],
          ),
          const SizedBox(height: 12),
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

  /// 今日頭條精簡列（小縮圖 + 兩行標題 + 「點我聆聽」＋「更多」）。
  ///
  /// ★ 一屏到底修復：原本是「大標題列 + 寫死 300px 大圖 + 看更多按鈕」
  /// （合計約 406px），改成一行約 113px 的精簡列。新聞抓取與 TTS 聆聽功能
  /// 完全沿用既有邏輯（[_openNewsListenPlayer]／[_openNewsListFromTopEntry]
  /// 皆未改動），只重做呈現。
  /// 依「這一屏還剩多少高度」決定新聞圖要多大。
  ///
  /// 首頁的硬需求是一屏到底不滾動（見 app_theme.dart 的 ElderScale
  /// docstring：「每屏選項少」）。真實長輩手機可用高度只有約 510px，
  /// 塞不下原本 406px 的大圖版新聞卡；但在平板或桌機視窗上，砍掉通話
  /// 大鈕之後會空出兩三百 px，維持精簡列就顯得空盪。
  ///
  /// 回傳 0 表示空間不足、走精簡橫列；大於 0 則是大圖的高度。
  double _availableNewsImageHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 版面固定開銷：頂部封面帶 52 ＋ sheet 偏移 42 ＋ 內距 44；
    // 底部 130 已含浮動導覽列 104 的淨空。
    final double available = mq.size.height - mq.padding.top - 138 - 130;
    // 其餘區塊的實測高度：今天卡 182、下一包藥 118、兩個間距 48、
    // 新聞標題列 36 ＋ 間距 8。下一包藥全部完成時會更矮，這裡取較高值
    // 保守估計，寧可少長一點也不要讓畫面被迫捲動。
    const double usedByOthers = 182 + 24 + 118 + 24 + 44;
    final double leftover = available - usedByOthers;

    // 精簡橫列本身約需 80px。要長成大圖至少得多出 190px 才划算，
    // 否則只是把小圖放大、反而擠掉呼吸空間。
    if (leftover < 190) return 0;
    return (leftover - 70).clamp(120.0, 300.0);
  }

  Widget _buildFeaturedNewsCard() {
    final double bigImageH = _availableNewsImageHeight(context);
    Widget header = Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '今日頭條',
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
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
          const SizedBox(height: 8),
          Container(
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ],
      );
    }

    if (_newsItems.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('目前沒有新聞，稍後再看看', style: ElderScale.body),
          ),
        ],
      );
    }

    // 頭條優先挑「有圖片」的新聞當縮圖；都沒有才退回第一則
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

    // 無圖時的縮圖底
    Widget fallbackThumb = Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Icon(
        Icons.newspaper_rounded,
        size: 28,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        // 整塊卡片可點 → 聆聽新聞畫面（沿用既有 _openNewsListenPlayer）
        Material(
          key: widget.newsCardKey,
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openNewsListenPlayer(item),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Flex(
                // 空間夠就大圖在上、標題在下（直排）；不夠就縮圖在左、
                // 標題在右（橫排）。同一份內容與同一組導覽目的地，只換排法。
                direction: bigImageH > 0 ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: bigImageH > 0 ? double.infinity : 64,
                      height: bigImageH > 0 ? bigImageH : 64,
                      child: hasImage
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null ? child : fallbackThumb,
                              errorBuilder: (_, __, ___) => fallbackThumb,
                            )
                          : fallbackThumb,
                    ),
                  ),
                  SizedBox(
                    width: bigImageH > 0 ? 0 : 12,
                    height: bigImageH > 0 ? 10 : 0,
                  ),
                  // ⚠️ 標題是後端動態文字、長度不可控，包 Expanded／Flexible ＋
                  // maxLines/ellipsis 避免窄螢幕溢位。直排時不能用 Expanded
                  // （父層高度不受限會拋錯），改用 Flexible(fit: loose)。
                  Flexible(
                    fit: bigImageH > 0 ? FlexFit.loose : FlexFit.tight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // ⚠️「點我聆聽」為固定字串，但跟按鈕同列，仍防禦性
                        // 包 Flexible／ellipsis，避免系統字體放大時溢位。
                        Row(
                          children: [
                            const Icon(Icons.play_circle_fill_rounded,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '點我聆聽',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // 看更多新聞 → 新聞列表（沿用既有
                            // _openNewsListFromTopEntry）
                            TextButton(
                              key: widget.moreNewsKey,
                              onPressed: _openNewsListFromTopEntry,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '更多',
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 16, color: AppColors.primaryDark),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

/// 首頁日期卡片「國曆（左）／農曆（右）」兩欄排版。
///
/// 從 [_ElderHomeTabState._buildTodayCard]（原 `_buildElderDateCard`）抽出成獨立、不連網、不讀
/// SharedPreferences 的 [StatelessWidget]，讓 widget test 能直接 pump 這個
/// 元件驗證大字級下的溢位情形，不需要連帶啟動 [ElderHomeTab] 的新聞抓取／
/// 訂閱查詢等重量級 initState 副作用。
///
/// 排版邏輯：平時（卡片可用寬度足夠）維持原本的 `Row` + `Spacer`——左欄
/// （國曆日期＋星期）靠左、右欄（農曆＋節氣）靠右，兩欄間距由 `Spacer`
/// 動態撐開，外觀與抽出前逐像素相同。只有在系統字體被調到很大、兩欄實際
/// 需要的寬度超過可用寬度時，才整體等比縮小（`FittedBox` +
/// `BoxFit.scaleDown`），避免 RenderFlex 溢位；不使用
/// `TextOverflow.ellipsis` 裁切文字。
///
/// 兩欄是否「塞得下」用 [TextPainter] 依目前 [TextScaler] 精確量測，而不是
/// 用固定 flex 比例分配空間——左欄（44pt 六個字）與右欄（24pt 最多五個字）
/// 的自然寬度差距很大，固定 flex 比例在「其實塞得下」時也可能誤判為塞不下
/// 而提早縮小其中一欄，那會違反「1.0 倍字級外觀不得改變」的要求。
class ElderDateSummaryRow extends StatelessWidget {
  final String monthStr;
  final String dateStr;
  final String dayName;
  final String lunarDate;
  final String solarTerm;

  /// 量測與 FittedBox 之間預留的安全誤差（邏輯像素）。
  ///
  /// [TextPainter] 量測與 [Text] 實際排版理論上會得到相同寬度，但仍以極小
  /// 誤差值防禦浮點捨入——寧可在邊界值附近提早一點點進入等比縮小分支，
  /// 也不要讓 RenderFlex 在邊界誤判為「塞得下」而真的溢位一個像素。
  static const double _overflowSafetyMargin = 1.0;

  const ElderDateSummaryRow({
    super.key,
    required this.monthStr,
    required this.dateStr,
    required this.dayName,
    required this.lunarDate,
    required this.solarTerm,
  });

  // ⚠️ 這裡刻意不寫死 `TextDirection` 型別名稱：本檔已 import 'package:intl/intl.dart'，
  // intl 自己也有一個同名的 TextDirection class，與 dart:ui 的 TextDirection 撞名，
  // 裸寫 `TextDirection.ltr` 會被解析成 intl 那個（沒有 .ltr getter）而編譯失敗。
  // 改用 Directionality.of(context) 直接取得正確型別的值，同時也更精確地
  // 反映 Text widget 實際會用的方向（跟隨 ambient Directionality，而非寫死 ltr）。
  double _measureWidth(
    BuildContext context,
    String text,
    TextStyle style,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final dateStyle = GoogleFonts.notoSansTc(
      fontSize: 44,
      fontWeight: FontWeight.w900,
      color: AppColors.primary,
      height: 1.0,
    );
    final dayStyle = GoogleFonts.notoSansTc(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    );
    final lunarStyle = GoogleFonts.notoSansTc(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      color: AppColors.textSecondary,
    );
    final termStyle = GoogleFonts.notoSansTc(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryDark,
    );

    final dateText = '$monthStr$dateStr日';

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateText, style: dateStyle),
        const SizedBox(height: 6),
        Text(dayName, style: dayStyle),
      ],
    );
    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(lunarDate, style: lunarStyle),
        const SizedBox(height: 4),
        Text(solarTerm, style: termStyle),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final leftDateWidth =
            _measureWidth(context, dateText, dateStyle, scaler);
        final leftDayWidth = _measureWidth(context, dayName, dayStyle, scaler);
        final rightLunarWidth =
            _measureWidth(context, lunarDate, lunarStyle, scaler);
        final rightTermWidth =
            _measureWidth(context, solarTerm, termStyle, scaler);
        final leftWidth =
            leftDateWidth > leftDayWidth ? leftDateWidth : leftDayWidth;
        final rightWidth =
            rightLunarWidth > rightTermWidth ? rightLunarWidth : rightTermWidth;

        final available = constraints.maxWidth;
        final fits = !available.isFinite ||
            (leftWidth + rightWidth + _overflowSafetyMargin) <= available;

        if (fits) {
          // 塞得下：與抽出前完全相同的排版，1.0 倍字級外觀零改變。
          return Row(
            children: [
              leftColumn,
              const Spacer(),
              rightColumn,
            ],
          );
        }

        // 塞不下（例如系統字體被調到很大）：兩欄整體等比縮小，不裁切文字。
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leftColumn,
              const SizedBox(width: 12),
              rightColumn,
            ],
          ),
        );
      },
    );
  }
}
