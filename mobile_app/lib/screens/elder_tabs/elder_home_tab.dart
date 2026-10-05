import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../almanac/farmer_almanac_screen.dart';
import '../news_listen_player/news_listen_player_screen.dart';
import '../../models/chinese_converter.dart';
import '../../models/elder_place.dart';
import '../../services/api/location_api.dart';
import '../../services/api_service.dart';
import '../../services/elder_home_place_service.dart';
import '../../services/friend_service.dart';
import '../../services/subscription_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/reminder_schedule.dart';
import '../../widgets/ui/ui.dart';
import 'elder_layout.dart';
import 'widgets/elder_task_sheet.dart';
import 'streak/streak_celebration.dart';
import 'streak/streak_service.dart';
import 'widgets/gem_in.dart';
import 'widgets/weather_glyph.dart';

class ElderHomeTab extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  /// 切換到「聊天」分頁的回呼（首頁「和小雲聊天」大按鈕用）。
  final VoidCallback? onNavigateToChat;

  /// 連勝慶祝畫面的「去餵小豬」：由 `ElderHomeScreen` 傳入，轉成既有的 `_onNavTap(2)`。
  final VoidCallback? onGoFeedPig;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey。全部選填、預設
  //   null——GlobalKey 必須由上層 ElderHomeScreen 持有並傳入（IndexedStack
  //   保活導致本頁 initState 只會跑一次，無法自行偵測「使用者第一次切到本
  //   頁」，判斷邏輯因此留在上層，詳見 elder_home_screen.dart）。傳 null 時
  //   完全不影響現有畫面。
  final GlobalKey? dateCardKey;
  final GlobalKey? newsCardKey;
  final GlobalKey? moreNewsKey;

  /// ⚠️ 僅供 widget test 注入假新聞資料使用（見
  /// `elder_home_tab_news_visibility_test.dart`）。正式呼叫端
  /// （`elder_home_screen.dart`）恆不傳這個欄位，不影響任何現有行為。
  ///
  /// 背景：`flutter test` 的 `TestWidgetsFlutterBinding` 會攔截整個測試
  /// 套件的 HTTP 請求並一律回傳 400（見上述測試檔頭說明），導致
  /// `_fetchNews()` 永遠落在失敗分支、`_newsItems` 恆為空陣列——沒有這個
  /// 欄位就無法用 widget test 驗證「已經有真實新聞資料」那個分支的版面
  /// 配置（第五十三輪 item 7 新增的「主卡片之外再補幾則精簡新聞列」）。
  @visibleForTesting
  final List<Map<String, dynamic>>? debugInitialNewsItemsForTest;

  /// ⚠️ 僅供 widget test 注入假提醒資料（同上，正式呼叫端恆為 null）。非 null 時
  /// 不呼叫 `_loadNextDoseData`（不讀 SharedPreferences、不打 API），任務卡／抽屜
  /// 直接用這份資料與 [debugInitialCompletedIdsForTest] 建構。
  @visibleForTesting
  final List<Map<String, dynamic>>? debugInitialRemindersForTest;

  /// ⚠️ 僅供 widget test：搭配 [debugInitialRemindersForTest] 指定「今天已完成」的提醒 id。
  @visibleForTesting
  final Set<int>? debugInitialCompletedIdsForTest;

  /// ⚠️ 僅供 widget test：直接指定「家」（非 null 時不呼叫 `_loadHomePlace`，
  /// 不連網）。正式呼叫端恆為 null。
  @visibleForTesting
  final ElderPlace? debugInitialHomePlaceForTest;

  const ElderHomeTab({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
    this.onNavigateToChat,
    this.onGoFeedPig,
    this.dateCardKey,
    this.newsCardKey,
    this.moreNewsKey,
    this.debugInitialNewsItemsForTest,
    this.debugInitialRemindersForTest,
    this.debugInitialCompletedIdsForTest,
    this.debugInitialHomePlaceForTest,
  });

  @override
  State<ElderHomeTab> createState() => _ElderHomeTabState();
}

class _ElderHomeTabState extends State<ElderHomeTab> {
  late String _lunarDate;
  late String _solarTerm;
  late String _dayName;

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

  /// 「帶我回家」的目的地；null 代表尚未設定家——入口卡仍顯示（見
  /// [_buildGoHomeEntry]），只是呈現停用提示樣態，不隱藏整張卡。
  ElderPlace? _homePlace;

  @override
  void initState() {
    super.initState();
    _updateTime();
    // ⚠️ 見 `widget.debugInitialNewsItemsForTest` 欄位說明：僅供 widget
    // test 注入假資料，production 呼叫端恆為 null，行為與原本完全相同。
    final debugNews = widget.debugInitialNewsItemsForTest;
    if (debugNews != null) {
      _newsItems = debugNews;
      _isLoadingNews = false;
    } else {
      _fetchNews();
    }
    _loadSubscription();
    _fetchWeather();
    final debugReminders = widget.debugInitialRemindersForTest;
    if (debugReminders != null) {
      _reminders = List<Map<String, dynamic>>.from(debugReminders);
      _completedReminderIds = {...?widget.debugInitialCompletedIdsForTest};
      _isLoadingNextDose = false;
    } else {
      _loadNextDoseData();
    }
    final debugHome = widget.debugInitialHomePlaceForTest;
    if (debugHome != null) {
      _homePlace = debugHome;
    } else {
      _loadHomePlace();
    }
  }

  /// 「帶我回家」：先用本機快取立即顯示，再向後端同步最新的「家」。
  ///
  /// elder_id 優先用 `widget.roomId`（長輩端 roomId 即 elder_profile.elder_id，
  /// 見 [_loadNextDoseData] 說明）；拿不到才退回 [FriendService.resolveMyElderId]。
  /// 快取依 elder_id 分開存放，所以必須先確定 elder_id 才能讀快取——
  /// 否則同一支手機換長輩帳號時，會短暫顯示前一位長輩的家。
  Future<void> _loadHomePlace() async {
    var elderId = widget.roomId;
    if (elderId == null || elderId.isEmpty) {
      elderId = await FriendService.resolveMyElderId(widget.userId);
    }
    if (elderId == null || elderId.isEmpty || !mounted) return;

    final cached = await ElderHomePlaceService.loadCached(elderId: elderId);
    if (!mounted) return;
    if (cached != null) setState(() => _homePlace = cached);

    final home = await ElderHomePlaceService.refresh(
      elderId: elderId,
      userId: widget.userId,
    );
    if (!mounted) return;
    setState(() => _homePlace = home);
  }

  Future<void> _goHome() async {
    final home = _homePlace;
    if (home == null) return;
    HapticFeedback.mediumImpact();
    // 通知配對家屬「正在導航回家」：fire-and-forget，不等待、不讓通知失敗
    // 擋住長輩開導航（下一行 openNavigation 不依賴它的結果）。
    unawaited(_notifyFamilyHeadingHome());
    final ok = await ElderHomePlaceService.openNavigation(home);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '無法開啟地圖，請確認已安裝 Google 地圖',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
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

  /// 通知配對家屬「長輩正在導航回家」。elder_id 解析邏輯與 [_loadHomePlace]
  /// 相同（優先用 `widget.roomId`，拿不到才退回 [FriendService.resolveMyElderId]）。
  /// 呼叫端必須 `unawaited`——這只是順便通知，絕不能拖慢或擋住開導航。
  Future<void> _notifyFamilyHeadingHome() async {
    var elderId = widget.roomId;
    if (elderId == null || elderId.isEmpty) {
      elderId = await FriendService.resolveMyElderId(widget.userId);
    }
    if (elderId == null || elderId.isEmpty) return;
    await LocationApi.notifyHeadingHome(elderId: elderId, userId: widget.userId);
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
    // ★ 連勝紀錄（新功能）：打卡「成功之後」才檢查，上面的樂觀更新／回退邏輯不變。
    if (success) unawaited(_checkStreak());
  }

  bool _taskSheetOpen = false;

  /// 連勝：今天的提醒剛好全部完成、且今天還沒慶祝過，就顯示慶祝畫面。
  /// 失敗一律吞掉（見 [StreakService.syncToday]），不影響打卡本身。
  Future<void> _checkStreak() async {
    final celebration = await StreakService.syncToday(
      reminders: _reminders,
      completedIds: _completedReminderIds,
    );
    if (celebration == null || !mounted) return;
    // 抽屜若還開著就先收起來：否則按「去餵小豬」切到小豬分頁後，抽屜會還蓋在上面。
    // （_taskSheetOpen 只在抽屜存在期間為 true，此時最上層路由就是抽屜。）
    if (_taskSheetOpen) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    await showStreakCelebration(context, celebration,
        onFeedPig: widget.onGoFeedPig);
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
      } catch (e) {
        debugPrint('DateFormat error: $e');
        _dayName = "星期${['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1]}";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, 14, 18, elderNavClearance(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGreeting(c),
              // 「帶我回家」：獨立的大入口，問候列之後、今天卡之前最顯眼的位置。
              // 尚未設定「家」時仍顯示（停用樣態提示家屬去設定），不整個藏起來。
              GemIn(index: 0, child: _buildGoHomeEntry(c)),
              const SizedBox(height: _cardGap),
              // ★ 一屏到底：首頁只留三張卡（今天／任務／今日頭條），依序以寶石鑲入錯開入場。
              // 刻意不把新聞卡排到前面——今天與任務是健康相關資訊，優先度更高。
              // 超出第一屏的部分交給外層既有的 SingleChildScrollView 捲動。
              GemIn(index: 1, child: _buildTodayCard(c)),
              const SizedBox(height: _cardGap),
              GemIn(index: 2, child: _buildTaskCard(c)),
              const SizedBox(height: _cardGap),
              GemIn(index: 3, child: _buildFeaturedNewsCard(c)),
            ],
          ),
        ),
      ),
    );
  }

  static const double _cardGap = 14;

  /// 依時間的問候語：05–11 早安、12–17 午安，其餘晚安。
  String _greetingText() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return '早安';
    if (h >= 12 && h < 18) return '午安';
    return '晚安';
  }

  /// 設計稿 `.greet`：頭像＋問候＋名字＋金豬會員徽章（徽章沿用 [_isPro]）。
  Widget _buildGreeting(UbanColors c) {
    final name = widget.userName.trim();
    final initial = name.isNotEmpty ? String.fromCharCode(name.runes.first) : '長';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: c.brandContainer, shape: BoxShape.circle),
            child: Text(initial,
                style: ubanText(24, FontWeight.w900, c.brandStrong)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greetingText(),
                    style: ubanText(18, FontWeight.w400, c.text2)),
                // ⚠️ 名字（動態）＋徽章同列：用 Wrap，放不下時徽章換行，名字也可省略（鐵律 #14）。
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name.isEmpty ? '您好' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(26, FontWeight.w900, c.text, height: 1.25),
                    ),
                    // 會員徽章：只有已訂閱才亮金豬，未訂閱不顯示（不做銀／銅階）。
                    if (_isPro) _buildMembershipBadge(c),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「帶我回家」獨立大入口（GPS，`_goHome()`）：首頁問候列之後最顯眼的卡片，
  /// 無論是否已設定「家」都顯示——未設定時呈現停用提示樣態，不整個藏起來，
  /// 讓長輩知道「有這個功能，只是還沒設定好」。
  ///
  /// Semantics 固定念「帶我回家」，與按鈕上顯示的標籤文字一致（鐵律 #14：
  /// 副標是可收縮的動態字串，`maxLines`＋`ellipsis` 防溢位）。
  Widget _buildGoHomeEntry(UbanColors c) {
    final hasHome = _homePlace != null;
    final iconBg = hasHome ? c.brandContainer : c.text3.withValues(alpha: .15);
    final iconFg = hasHome ? c.brandStrong : c.text3;
    final subtitle =
        hasHome ? '導航回家，並通知家人您正在路上' : '請家人先在 App 幫您設定住家';

    final card = UbanCard(
      onTap: hasHome ? _goHome : null,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.home_rounded, size: 34, color: iconFg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('帶我回家',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(22, FontWeight.w900, c.text)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(15, FontWeight.w400, c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            hasHome ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
            size: 28,
            color: c.text3,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: hasHome,
      label: '帶我回家',
      excludeSemantics: true,
      onTap: hasHome ? _goHome : null,
      child: ExcludeSemantics(
        child: Opacity(opacity: hasHome ? 1 : .55, child: card),
      ),
    );
  }

  /// 訂閱徽章膠囊（金豬會員）。只有一階：家屬已為長輩開通 PRO 就亮金豬。
  Widget _buildMembershipBadge(UbanColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Image.asset(
              'assets/images/pig_badge_gold.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                  child: Text('🐷', style: TextStyle(fontSize: 18))),
            ),
          ),
          const SizedBox(width: 4),
          Text('金豬會員', style: ubanText(16, FontWeight.w700, c.warm)),
        ],
      ),
    );
  }

  /// 「今天」卡右側的天氣方塊（設計稿 `.weather`）。
  ///
  /// 讀取中顯示精簡佔位；失敗（[WeatherService] 回傳 null）只讓「這一塊」顯示平靜的
  /// 「稍後再試」文案——刻意不做紅色警示，這位長輩容易被警告字樣嚇到。
  /// 天氣小圖跟著實際降雨機率走（分級與 [WeatherService] 三段文案同源：<20／<50／其餘）。
  Widget _buildWeatherBox(UbanColors c) {
    Widget box(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.brandSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        );

    if (_isLoadingWeather) {
      return box(const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ));
    }

    final weather = _weatherInfo;
    if (weather == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: box(Text(
          '天氣暫時看不到，稍後再試',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: ubanText(16, FontWeight.w400, c.text2),
        )),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: box(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WeatherGlyph(rainy: weather.rainProbability >= 50, size: 40),
          const SizedBox(height: 2),
          // ⚠️ 溫度區間是動態字串，包 FittedBox 防止窄螢幕／大字級溢位。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${weather.minTemp.round()}°–${weather.maxTemp.round()}°',
              maxLines: 1,
              style: ubanBrandText(22, FontWeight.w600, c.text, height: 1.2),
            ),
          ),
          Text(
            weather.condition,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ubanText(16, FontWeight.w400, c.text2),
          ),
        ],
      )),
    );
  }

  Widget _infoTag(UbanColors c, String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c.text2),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ubanText(17, FontWeight.w700, c.text2),
            ),
          ),
        ],
      ),
    );
  }

  /// 「今天」卡（設計稿 `.today`）：日期／星期＋天氣方塊＋農曆節氣 tag，
  /// 點擊跳轉至農民曆與神明誕辰（[FarmerAlmanacScreen] 的唯一入口）。
  Widget _buildTodayCard(UbanColors c) {
    final now = DateTime.now();
    final weather = _weatherInfo;
    final dateStyle = ubanBrandText(46, FontWeight.w600, c.text, height: 1);
    final unitStyle = ubanText(22, FontWeight.w700, c.text);

    return UbanCard(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今天',
                        style: ubanText(16, FontWeight.w700, c.text3,
                            letterSpacingEm: .1)),
                    const SizedBox(height: 4),
                    // ≥40pt 的展示文字用 FittedBox：大字級／窄螢幕時等比縮小而不溢位。
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${now.month}', style: dateStyle),
                            TextSpan(text: '月', style: unitStyle),
                            TextSpan(text: '${now.day}', style: dateStyle),
                            TextSpan(text: '日', style: unitStyle),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(20, FontWeight.w700, c.text),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildWeatherBox(c),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoTag(c, '農曆$_lunarDate'),
              if (_solarTerm.isNotEmpty) _infoTag(c, _solarTerm),
              if (weather != null && weather.rainProbability >= 20)
                _infoTag(c, '降雨 ${weather.rainProbability}%',
                    icon: Icons.umbrella_rounded),
              if (weather != null && weather.isFromCache)
                _infoTag(c, '上次查到的天氣'),
            ],
          ),
        ],
      ),
    );
  }

  /// 任務卡（設計稿 `.taskcard`）：進度環（中間只寫「done/total」）＋下一件＋打卡鈕；
  /// 點卡片開「今天要做的事」抽屜。
  ///
  /// 視覺沿用 [UbanCard]。讀取失敗與「真的沒有提醒／都完成了」分成兩種畫面
  /// （第四十九輪：避免網路不穩被誤導成「今天沒有藥要吃」）。
  Widget _buildTaskCard(UbanColors c) {
    if (_isLoadingNextDose) {
      return UbanCard(
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text('提醒讀取中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w700, c.text)),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final next = nextDue(_reminders, _completedReminderIds, now);
    if (next == null && _hasNextDoseLoadError) {
      return UbanCard(
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 28, color: c.text3),
            const SizedBox(width: 14),
            Expanded(
              child: Text('提醒暫時讀不到，請確認網路連線',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w700, c.text)),
            ),
          ],
        ),
      );
    }

    final groups = groupByStatus(_reminders, _completedReminderIds, now);
    final done = groups.done.length;
    final total = done + groups.dueNow.length + groups.later.length;

    final Widget right;
    if (next == null) {
      right = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 24, color: c.brandStrong),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  total == 0 ? '今天沒有要做的事' : '今天的事都做完了',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w900, c.brandStrong),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            Text('小豬也替您開心', style: ubanText(16, FontWeight.w400, c.text2)),
          ],
        ],
      );
    } else {
      final timeStr = (next['time_str'] ?? '').toString();
      final title = (next['title'] ?? '提醒').toString();
      // ⚠️ 時間＋標題皆為動態長度（後端自訂文字），時間用 FittedBox、標題限 2 行省略。
      right = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('下一件',
              style: ubanText(16, FontWeight.w700, c.text3, letterSpacingEm: .1)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(timeStr,
                maxLines: 1,
                style: ubanBrandText(24, FontWeight.w600, c.text, height: 1.3)),
          ),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ubanText(19, FontWeight.w700, c.text, height: 1.3)),
        ],
      );
    }

    return UbanCard(
      onTap: total > 0 ? _openTaskSheet : null,
      child: Row(
        children: [
          UbanProgressRing(done: done, total: total),
          const SizedBox(width: 16),
          Expanded(child: right),
          if (next != null) ...[
            const SizedBox(width: 12),
            UbanButton(
              label: '打卡',
              expand: false,
              onPressed: () => _completeNextDose(next),
            ),
          ],
        ],
      ),
    );
  }

  /// 開「今天要做的事」抽屜（設計稿 `#sh-tasks`）。抽屜內打卡仍走 [_completeNextDose]。
  void _openTaskSheet() {
    HapticFeedback.lightImpact();
    _taskSheetOpen = true;
    showUbanSheet<void>(
      context,
      (ctx) => ElderTaskSheetBody(
        readGroups: () =>
            groupByStatus(_reminders, _completedReminderIds, DateTime.now()),
        onCheckIn: _completeNextDose,
      ),
    ).whenComplete(() => _taskSheetOpen = false);
  }

  /// 今日頭條卡（設計稿 `.news-hero`＋`.headline`）。
  ///
  /// ★ 第五十二輪起的鐵則（`elder_home_tab_news_visibility_test.dart` 鎖定）：
  /// 「今日頭條」標題必須在 360x640 第一屏內，所以讀取中／無資料兩態一律用固定 76px 的
  /// 小縮圖精簡列，不得回到「依剩餘空間長出大圖」（第五十輪 `leftover.clamp(170, 260)`
  /// 把整張卡擠出第一屏的教訓）。有資料時的 150px 主圖在標題「之後」，不影響標題位置。
  ///
  /// 新聞抓取與 TTS 聆聽沿用既有 [_openNewsListenPlayer]／[_openNewsListFromTopEntry]，
  /// 這裡只做呈現。
  Widget _buildFeaturedNewsCard(UbanColors c) {
    Widget header({bool withMore = false}) => Row(
          children: [
            Expanded(
              child: Text('今日頭條',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(22, FontWeight.w900, c.text)),
            ),
            if (withMore)
              // 看更多新聞 → 新聞列表（沿用既有 _openNewsListFromTopEntry）
              UbanButton(
                key: widget.moreNewsKey,
                label: '更多',
                variant: UbanButtonVariant.ghost,
                expand: false,
                onPressed: _openNewsListFromTopEntry,
              ),
          ],
        );

    // 縮圖固定尺寸：不依 MediaQuery 動態計算（理由見上方說明）。
    const double thumbSize = 76;

    if (_isLoadingNews) {
      return UbanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('新聞讀取中…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(19, FontWeight.w700, c.text)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_newsItems.isEmpty) {
      // 明確寫「還在整理中」，長輩才不會誤以為「頭條」功能被拿掉（第五十輪）。
      return UbanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: thumbSize,
                  height: thumbSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.newspaper_rounded,
                      size: 30, color: c.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('今天的新聞還在整理中，請稍候',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(19, FontWeight.w700, c.text)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 頭條優先挑「有圖片」的新聞當主圖；都沒有才退回第一則
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

    // 主卡片之外再補幾則精簡列（見 [_extraHeadlineCount]）。用 `!=`（參照相等）
    // 排除主卡片那一則——`item` 就是 `_newsItems` 裡的元素本身。
    final int extraCount = _extraHeadlineCount(context);
    final List<Map<String, dynamic>> extraItems = extraCount <= 0
        ? const []
        : _newsItems.where((it) => it != item).take(extraCount).toList();

    // 無圖（或圖片載入失敗）時的主圖底：品牌漸層＋「示意圖」小標。
    Widget fallbackHero = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.brand, c.brandFill, c.brandStrong],
              stops: const [0, .6, 1],
            ),
          ),
        ),
        Center(
          child: Icon(Icons.article_rounded,
              size: 48, color: Colors.white.withValues(alpha: .5)),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('示意圖', style: ubanText(16, FontWeight.w700, c.text2)),
          ),
        ),
      ],
    );

    return UbanCard(
      key: widget.newsCardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header(withMore: true),
          // 主圖＋標題：點擊 → 聆聽新聞畫面（沿用既有 _openNewsListenPlayer）
          PressableScale(
            onTap: () => _openNewsListenPlayer(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasImage)
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) =>
                                progress == null ? child : fallbackHero,
                            errorBuilder: (_, __, ___) => fallbackHero,
                          )
                        else
                          fallbackHero,
                        Positioned(
                          left: 14,
                          bottom: 14,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                            decoration: BoxDecoration(
                              color: c.surface.withValues(alpha: .94),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle_fill_rounded,
                                    size: 22, color: c.brandStrong),
                                const SizedBox(width: 8),
                                Text('點我聆聽',
                                    style: ubanText(17, FontWeight.w700, c.text)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ⚠️ 標題是後端動態文字、長度不可控，限 2 行省略（鐵律 #14）。
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(21, FontWeight.w900, c.text, height: 1.4),
                ),
              ],
            ),
          ),
          if (extraItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (int i = 0; i < extraItems.length; i++)
              _buildHeadlineRow(extraItems[i], i + 2, c),
          ],
        ],
      ),
    );
  }

  /// 主卡片之外，還要視「螢幕總高度」補幾則精簡新聞列（見呼叫端
  /// [_buildFeaturedNewsCard] 的說明）。
  ///
  /// 刻意只讀 `MediaQuery.size.height` 這一個穩定數字做粗粒度分級，**不**
  /// 反推「扣掉今天卡／下一包藥卡之後還剩多少空間」——後者依賴其他卡片
  /// 當下的動態高度（天氣文字長度、用藥資料筆數都會變動），正是第五十輪
  /// `_availableNewsImageHeight` 讓卡片暴衝、把整張「今日頭條」擠出第一屏
  /// 的根因（見 `_buildFeaturedNewsCard` 開頭的完整說明）。單純的螢幕高度
  /// 分級沒有這個問題：數字固定、每列高度也固定（單行 ellipsis，不像主
  /// 卡片標題可能跳 1～2 行），上限有界，不會重蹈覆轍。
  ///
  /// 門檻依 `elder_home_tab_news_visibility_test.dart` 兩組實測基準訂定：
  ///   - 360x640（窄機）：header 到第一屏可視底線僅 ~120px 預算，扣掉主
  ///     卡片本身（含 padding，約 100～111px）後剩不到 20px——連一則精簡列
  ///     （約 34px）都放不下，故回傳 0，不勉強塞。
  ///   - 412x915（大機）：預算約 387px，主卡片＋2 則精簡列（約 85px）後仍
  ///     有 100px 以上餘裕，故回傳上限 2（「不用太多，僅填滿就好」，見
  ///     使用者原話，不是能塞多少就塞多少）。
  ///   700 是兩組實測值（640／915）中間、留有餘裕的分界點，尚未涵蓋的機型
  ///   尺寸屬合理外插，非任意數字。
  int _extraHeadlineCount(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight >= 700) return 2;
    return 0;
  }

  /// 設計稿 `.headline`：序號＋單行標題，整列可點，沿用既有 [_openNewsListenPlayer]。
  /// 每列高度固定可預期（單行 ellipsis），見 [_extraHeadlineCount] 的量測基準。
  Widget _buildHeadlineRow(Map<String, dynamic> item, int number, UbanColors c) {
    final title = (item['title'] ?? '無標題').toString();
    return PressableScale(
      onTap: () => _openNewsListenPlayer(item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('$number',
                  style: ubanBrandText(18, FontWeight.w600, c.brandStrong)),
            ),
            const SizedBox(width: 8),
            // ⚠️ 標題是後端動態文字、長度不可控，包 Expanded／ellipsis（鐵律 #14）。
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ubanText(18, FontWeight.w500, c.text),
              ),
            ),
          ],
        ),
      ),
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
