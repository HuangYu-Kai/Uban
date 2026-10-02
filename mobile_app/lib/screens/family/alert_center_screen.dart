import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/predictive_alert_service.dart';
import '../../services/api_service.dart';
import '../../utils/error_handler.dart';

/// ★ 第五十二輪 F2：警示紀錄清單的時間範圍篩選。放在檔案頂層（非
/// State 內部類別）純粹是 Dart enum 慣例，值本身只有這個畫面在用。
/// ★ 第五十三輪 familyfix53：新增 `custom`——使用者自行挑選起訖日期，取代
/// 原本只能用「本週／本月／全部」三段固定區間查找特定紀錄的限制。
enum _AlertTimeRange { week, month, all, custom }

/// ★ 第五十三輪 familyfix53：警示紀錄狀態篩選。對應後端 `emergency_alerts.status`
/// 狀態機（`active`→`acknowledged`→`resolved`，見 `routers/alert.py::get_alerts`
/// docstring）。`all` 代表不套用狀態篩選（維持既有行為：持久化警報＋一般
/// 活動提醒都顯示）；其餘三者只保留有真實 `alertId` 的持久化警報——一般
/// 活動提醒（`logItems`，見 `_loadHistoryAlerts`）沒有狀態機概念，選擇
/// 特定狀態時不應該混在裡面誤導使用者「這也是待處理的」。
enum _AlertStatusFilter { all, active, acknowledged, resolved }

extension on _AlertStatusFilter {
  /// 對應後端 `GET /alerts/{elder_id}?status=` 的值；`all` 回傳 null 代表
  /// 不帶這個查詢參數。
  String? get apiValue => switch (this) {
        _AlertStatusFilter.all => null,
        _AlertStatusFilter.active => 'active',
        _AlertStatusFilter.acknowledged => 'acknowledged',
        _AlertStatusFilter.resolved => 'resolved',
      };

  /// 家屬看得懂的中文標籤——不直接把英文狀態碼露出來（team-lead 要求）。
  String get label => switch (this) {
        _AlertStatusFilter.all => '全部狀態',
        _AlertStatusFilter.active => '未處理',
        _AlertStatusFilter.acknowledged => '處理中',
        _AlertStatusFilter.resolved => '已結案',
      };
}

/// 「全部」篩選給的較大 limit——如實告知使用者這不是真的「無限」，只是
/// 顯示較多筆（見 [_AlertCenterScreenState._buildAllRangeHint]）。與後端
/// `routers/alert.py::get_alerts` 的 `limit` 參數對應。
const int _kAllRangeLimit = 200;

/// ★ 第五十二輪 F2：警示紀錄卡片的單一動作控制項（PopupMenuButton）可選
/// 的兩個選項——取代原本「回報已處理」／「這是誤報」兩個並排按鈕。
enum _AlertMenuAction { resolve, falseAlarm }

/// 🚨 警示中心頁面
///
/// 顯示所有預測性警示和建議
class AlertCenterScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;

  /// ⚠️ `elderId`（上方，`int?`）與這裡的 `elderRoomId` 是**兩個不同的欄位**，
  /// 呼叫端務必不要搞混：
  /// - `elderId` 現行三個建構點都傳 `Elder.id`（DB 整數 PK／`user_id`），
  ///   本畫面內部目前沒有邏輯依賴它，只是保留既有欄位不動。
  /// - `elderRoomId` 對應 `Elder.elderId`（`elder_profile` 的 4 位數房間代
  ///   號字串），才是 `getElderActivityLogs`／`getEmergencyAlerts` 兩支 REST
  ///   端點與即時警報 `elder_id` 比對**實際需要**的值——`family_home_tab.dart`
  ///   全檔一律取 `currentElder?.elderId ?? currentElder?.id.toString()`
  ///   （見 `_loadDynamicData` :824、`_buildAlertPreview` :3170），呼叫端請
  ///   用同一套算法算出來傳入，**不要**只傳 `Elder.id.toString()`——兩者在
  ///   多數資料下數值不同，用錯會抓到空清單。
  final String? elderRoomId;

  /// ★ 第四十一輪（item 1）：家屬端首頁「最新警示」預覽（見
  /// `family_home_tab.dart::_buildAlertPreview` 約 :3168 起）展開前顯示的即時
  /// 跌倒／CCTV 警報，展開後的本畫面原本完全收不到——兩邊顯示的是兩批不同
  /// 資料（本畫面原本只從 `PredictiveAlertService` 載入預測型健康警示）。
  /// 呼叫端應傳入與預覽同一份 `activeAlerts`（未過濾），本畫面自行套用與
  /// 預覽相同的「隔離不同長輩」規則（見 [_AlertCenterScreenState._filteredActiveAlerts]）。
  /// 預設 `const []`：這是 Socket 即時狀態，畫面自己抓不到，只能由父層給；
  /// 沒有即時來源的入口（例如 `ai_hub_screen.dart`）維持空清單即可，不必為
  /// 此另外造一份假資料——見 [elderRoomId]，另外兩類警示改由本畫面自己用
  /// REST 抓取，所有入口拿到的資料因此仍會一致。
  final List<Map<String, dynamic>> activeAlerts;

  /// 測試專用注入點：提供時直接當成警示紀錄清單使用，略過
  /// `_loadHistoryAlerts()` 原本的網路抓取（見該方法開頭的判斷）。
  /// App 正常執行時一律是 `null`。
  ///
  /// ★ 第五十二輪 F2 新增：`_buildHistoryAlertCard`／`_buildAlertActionArea`
  /// 是本檔的 library-private 方法，測試檔案（不同檔案＝不同 library）
  /// 無法直接呼叫；`activeAlerts` 餵的是即時 CCTV 警報，不是這裡要驗證的
  /// 「已結案不得再有動作鍵」「未結案只有單一動作控制項」這兩項針對
  /// 持久化警示紀錄卡片的驗收項目。沒有這個注入點，對應的 widget test
  /// 就只能在測試檔裡另外手刻一份結構相近的重建版（有與正式程式碼漂移
  /// 不同步的風險），而不是命中真正的實作。
  final List<Map<String, dynamic>>? historyAlertItemsOverride;

  const AlertCenterScreen({
    super.key,
    required this.elderName,
    this.elderId,
    this.elderRoomId,
    this.activeAlerts = const [],
    this.historyAlertItemsOverride,
  });

  @override
  State<AlertCenterScreen> createState() => _AlertCenterScreenState();
}

class _AlertCenterScreenState extends State<AlertCenterScreen> {
  final _alertService = PredictiveAlertService();
  List<Alert> _alerts = [];
  // ★ 第四十一輪（item 1 追加）：family_home_tab.dart 預覽區另外兩個真實
  // 來源（_realLogs 活動流水、_emergencyAlerts 持久化跌倒警報）合併、排序
  // 後的結果。與 [Alert]／`_alerts`（預測型健康警示）是完全不同的資料
  // 種類，分開存放、分開渲染（見 _buildContent、_buildHistoryAlertsSection）。
  List<Map<String, dynamic>> _historyAlertItems = [];
  bool _isLoading = true;
  // ★ 第四十五輪：正在送出「標記誤報」請求的項目 id（防重複點擊／顯示 loading）。
  final Set<String> _falseAlarmPending = {};
  // ★ 第四十九輪 item 12：正在送出「回報已處理」請求的項目 id，用途同上。
  final Set<String> _resolvePending = {};

  // ★ 第五十二輪 F2：警示紀錄時間篩選（本週／本月／全部）。只存在本畫面
  // 的 State 裡——任務要求「記住目前選擇、不需要持久化」，`IndexedStack`
  // 保活即足夠讓使用者切分頁再切回來時維持選擇，不必寫 SharedPreferences。
  _AlertTimeRange _timeRange = _AlertTimeRange.week;
  // ★ 第五十三輪 familyfix53：使用者透過 showDateRangePicker 選定的自訂
  // 起訖日期（本地時間的日曆日，只取年/月/日）。只有 `_timeRange ==
  // custom` 時才有意義；尚未選過時為 null，此時 UI 會退回上一個非 custom
  // 的篩選（見 _selectCustomRange）。
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  // ★ 第五十三輪 familyfix53：警示紀錄狀態篩選，預設「全部狀態」（維持
  // 既有行為）。
  _AlertStatusFilter _statusFilter = _AlertStatusFilter.all;
  // 警示紀錄區塊自己的局部載入狀態——切換時間篩選只重抓這個區塊，不影響
  // 上方已經載入完成的即時警報／健康建議，也不觸發整頁滿版 loading（那
  // 會讓使用者失去目前的捲動位置）。
  bool _historyLoading = false;
  // 這次載入是否失敗。「這個時間範圍內沒有紀錄」與「載入失敗」在 UI 上
  // 必須長得不一樣（見 _buildHistoryError／_buildHistoryEmpty），不能都
  // 塌成同一個空清單。
  bool _historyLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  /// 依目前選取的時間範圍換算成後端 `days` 參數；`null` 代表「全部」或
  /// 「自訂範圍」（後者改用 `start_date`/`end_date`，見 `_loadHistoryAlerts`），
  /// 不套用 `days` 篩選（見 `routers/alert.py::get_alerts` 的 `days` 語意）。
  int? _daysForRange(_AlertTimeRange range) {
    switch (range) {
      case _AlertTimeRange.week:
        return 7;
      case _AlertTimeRange.month:
        return 30;
      case _AlertTimeRange.all:
      case _AlertTimeRange.custom:
        return null;
    }
  }

  /// 'YYYY-MM-DD'，供 `start_date`/`end_date` 查詢參數使用。
  String _formatDateForApi(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 開啟日期範圍選擇器；使用者確定選擇後切到 `custom` 篩選並重新載入。
  /// 取消（回傳 null）則完全不變動現有篩選——不會誤把 `_timeRange` 切到
  /// `custom` 卻沒有實際日期可用。
  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final initialRange = (_customStartDate != null && _customEndDate != null)
        ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
        : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);

    final picked = await showDateRangePicker(
      context: context,
      // 長輩帳號建立時間不可考，抓一個足夠寬鬆的下限；不開放選到未來。
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: '選擇警示紀錄查詢範圍',
      cancelText: '取消',
      confirmText: '確定',
      saveText: '確定',
    );
    if (picked == null || !mounted) return;

    HapticFeedback.selectionClick();
    setState(() {
      _timeRange = _AlertTimeRange.custom;
      _customStartDate = picked.start;
      _customEndDate = picked.end;
    });
    _loadHistoryAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    // 模擬健康數據
    final healthData = {
      'heartRate': 75,
      'bloodSugar': 95,
      'systolicBP': 125,
      'diastolicBP': 82,
      'dailySteps': 3500,
      'consecutiveLowActivityDays': 2,
      'sleepQualityTrend': 'stable',
      'callFrequencyTrend': 'stable',
    };

    final alerts = await _alertService.checkAllAlerts(
      healthData: healthData,
      lookbackDays: 7,
    );

    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _isLoading = false;
    });

    // ★ 第五十二輪 F2：警示紀錄改走獨立的局部載入狀態，不再共用上面的
    // `_isLoading`（原因見該欄位宣告處註解）。初次載入／下拉重新整理仍會
    // 一併重抓這個區塊，只是不再讓它卡住上面兩個區塊的顯示時機。
    await _loadHistoryAlerts();
  }

  /// 抓取並合併 family_home_tab.dart 預覽區另外兩個真實來源：
  /// `_realLogs`（`GET /activity/elder/{elder_id}`，活動流水）與
  /// `_emergencyAlerts`（`GET /alerts/{elder_id}`，持久化跌倒／異常警報）。
  /// 抓法逐一比照該檔 `_loadDynamicData`（:822-849）：user_id 讀不到就略過
  /// `_emergencyAlerts` 這一段抓取。
  ///
  /// ★ 第五十二輪 F2：改為自行管理 `_historyAlertItems`／`_historyLoading`／
  /// `_historyLoadFailed` 三個 State 欄位（不再是回傳值交給呼叫端
  /// setState）——現在有兩個呼叫時機：`_loadAlerts()`（整頁初次載入／下拉
  /// 重新整理）與使用者切換時間篩選 chip（只重抓這個區塊）。同時新增依
  /// [_timeRange] 決定的 `days`／`limit`：
  ///   - 送給後端 `GET /alerts/{elder_id}?days=` 只影響 `emergencyAlerts`
  ///     （持久化跌倒警報，見 `routers/alert.py::get_alerts` 的 `days`）。
  ///   - `logs`（活動流水）後端沒有對應的按天篩選端點，改在下方合併排序
  ///     後對整個 `combined` 清單再套一次以 `sortTs` 為準的用戶端篩選，
  ///     否則切到「本週」時仍會看到數月前的健康警示混在清單裡，篩選形同
  ///     虛設（見下方篩選區塊的完整說明）。
  /// ⚠️ 例外不再整段吞掉——`failed` 旗標會讓使用者看到明確的「載入失敗」
  /// 而不是被誤判成「這個範圍沒有紀錄」（見 _buildHistoryError／
  /// _buildHistoryEmpty 的不同呈現）。
  Future<void> _loadHistoryAlerts() async {
    if (_historyLoading) return; // 防止快速切換時間篩選造成的競態載入

    // 測試專用注入點（見 [AlertCenterScreen.historyAlertItemsOverride]）：
    // 提供時直接採用，略過下面的網路抓取與時間篩選——測試資料已經是
    // 呼叫端刻意準備好的最終清單。
    if (widget.historyAlertItemsOverride != null) {
      if (!mounted) return;
      setState(() {
        _historyAlertItems = widget.historyAlertItemsOverride!;
        _historyLoading = false;
        _historyLoadFailed = false;
      });
      return;
    }

    setState(() {
      _historyLoading = true;
      _historyLoadFailed = false;
    });

    final elderIdForApi = widget.elderRoomId ?? widget.elderId?.toString();
    if (elderIdForApi == null || elderIdForApi.isEmpty) {
      if (!mounted) return;
      setState(() {
        _historyAlertItems = [];
        _historyLoading = false;
      });
      return;
    }

    final int? days = _daysForRange(_timeRange);
    // ★ 第五十三輪 familyfix53：`custom` 範圍可能橫跨數月甚至數年（見
    // _selectCustomRange 的 firstDate），比照「全部」提高 limit，不要沿用
    // 30 筆讓長範圍的查詢結果被過早截斷。
    final bool isUnboundedRange =
        _timeRange == _AlertTimeRange.all || _timeRange == _AlertTimeRange.custom;
    final int fetchLimit = isUnboundedRange ? _kAllRangeLimit : 30;
    // 只有 `custom` 才會有值；後端優先採用這兩個參數、與 `days` 互斥（見
    // CctvAlertApi.getEmergencyAlerts／routers/alert.py::get_alerts 的說明）。
    final String? startDateForApi =
        _timeRange == _AlertTimeRange.custom && _customStartDate != null
            ? _formatDateForApi(_customStartDate!)
            : null;
    final String? endDateForApi =
        _timeRange == _AlertTimeRange.custom && _customEndDate != null
            ? _formatDateForApi(_customEndDate!)
            : null;

    List<dynamic> logs = [];
    List<dynamic> emergencyAlerts = [];
    bool failed = false;
    try {
      logs = await ApiService.getElderActivityLogs(elderIdForApi, limit: fetchLimit);
      final prefs = await SharedPreferences.getInstance();
      final familyUserId = prefs.getInt('caregiver_id');
      if (familyUserId != null) {
        emergencyAlerts = await CctvAlertApi.getEmergencyAlerts(
          elderIdForApi,
          userId: familyUserId,
          limit: fetchLimit,
          days: days,
          startDate: startDateForApi,
          endDate: endDateForApi,
          // ★ 第五十三輪 familyfix53：狀態篩選（見 [_AlertStatusFilter]）。
          // `all` 對應 null——不帶這個查詢參數，維持既有「不篩狀態」行為。
          status: _statusFilter.apiValue,
        );
      }
    } catch (e) {
      failed = true;
    }

    // dedupe：與即時警報（activeAlerts）同一筆的持久化跌倒警報不重複顯示，
    // 判準與 family_home_tab.dart 一致——後端對同一 elder+device+alert_type
    // 的 active 警報是 UPSERT、沿用同一個 alert_id。
    final liveAlertIds = widget.activeAlerts
        .map((a) => (a['alert_id'] ?? a['alertId'])?.toString())
        .whereType<String>()
        .toSet();

    // 這兩支 API 本身就是「單一 elder_id」的 REST 呼叫（後端逐一驗證
    // is_user_linked_to_elder），回傳內容天生已是這位長輩專屬，不像
    // activeAlerts（Socket 廣播）需要再做一次前端隔離過濾。
    final persistedItems = emergencyAlerts.whereType<Map>().where((row) {
      final rAlertId = (row['alert_id'] ?? row['alertId'])?.toString();
      if (rAlertId != null && liveAlertIds.contains(rAlertId)) return false;
      return true;
    }).map((row) {
      final type = (row['alert_type'] ?? row['alertType'] ?? 'fall').toString();
      final detectedAt = (row['detected_at'] ?? row['detectedAt'] ?? '').toString();
      String whenStr = '';
      if (detectedAt.length >= 16) {
        whenStr = '${detectedAt.substring(5, 7)}/${detectedAt.substring(8, 10)} ${detectedAt.substring(11, 16)}';
      }
      String title = '🚨 跌倒緊急警報';
      String desc = '監視機曾偵測到長輩疑似跌倒。';
      if (type == 'crawl') {
        title = '⚠️ 疑似爬行警報';
        desc = '監視機曾偵測到長輩異常爬行動作。';
      } else if (type == 'lying_down') {
        title = '⚠️ 久躺未起警報';
        desc = '長輩曾在監視區域久躺不起。';
      } else if (type == 'prolonged_inactivity') {
        title = '⚠️ 長時間無活動警報';
        desc = '長輩曾出現活動量異常偏低。';
      }
      if (whenStr.isNotEmpty) {
        desc = '$desc（發生於 $whenStr）';
      }
      final String? persistedAlertIdRaw = (row['alert_id'] ?? row['alertId'])?.toString();
      final persistedItemId = (persistedAlertIdRaw != null && persistedAlertIdRaw.isNotEmpty)
          ? 'alert:$persistedAlertIdRaw'
          : 'persisted:$type:$detectedAt';
      // ★ 第四十五輪：只有真正查得到 alert_id 的項目才能呼叫
      //   POST /alerts/{alert_id}/false-alarm；下方 logItems（活動流水）沒有
      //   對應的 emergency_alerts 列，_buildHistoryAlertCard 靠 alertId 是否
      //   為 null 決定要不要顯示「這是誤報」操作。
      final rawIsFalseAlarm = row['is_false_alarm'] ?? row['isFalseAlarm'];
      return <String, dynamic>{
        'id': persistedItemId,
        'title': title,
        'desc': desc,
        'level': 'high',
        'icon': Icons.warning_amber_rounded,
        'sortTs': DateTime.tryParse(detectedAt),
        'alertId': persistedAlertIdRaw != null ? int.tryParse(persistedAlertIdRaw) : null,
        'isFalseAlarm': rawIsFalseAlarm == true || rawIsFalseAlarm == 1,
        // ★ 第四十九輪 item 12：警報狀態機第三態（已完成）——
        //   `_buildResolveAction` 靠這個欄位決定顯示「回報已處理」按鈕
        //   還是「已回報處理完畢」徽章。
        'status': (row['status'] ?? '').toString(),
        // ★ 第四十九輪 item 12（收尾）：結案來源——'family'／'developer'／
        //   'false_alarm'／'legacy_auto'，`_buildResolveAction` 靠它把
        //   「已完成」徽章依來源分流文案，尤其 legacy_auto（舊警報上線時
        //   系統自動結案）不可顯示成家屬已處理。空字串（尚未結案，或後端
        //   未提供此欄位的舊快取）落入該函式的「其他」分支。
        'resolution_source': (row['resolution_source'] ?? '').toString(),
      };
    });

    final logItems = logs.whereType<Map>().where((log) {
      final text = log['content']?.toString() ?? '';
      final etype = log['event_type']?.toString() ?? '';
      return etype == 'alert' || text.contains('警示') || text.contains('提醒') || text.contains('未確認');
    }).map((log) {
      final desc = log['content']?.toString() ?? '';
      final title = desc.split('|').first.replaceAll(RegExp(r'【.*?】'), '').trim();
      final level = desc.contains('用藥') || desc.contains('未確認') ? 'high' : 'medium';
      final icon = desc.contains('用藥') ? Icons.medication_rounded : Icons.directions_walk_rounded;
      final String? logIdRaw = log['log_id']?.toString();
      final String? logTs = log['timestamp']?.toString();
      final logItemId = (logIdRaw != null && logIdRaw.isNotEmpty)
          ? 'log:$logIdRaw'
          : 'log-fallback:${logTs ?? ''}:${desc.hashCode}';
      return <String, dynamic>{
        'id': logItemId,
        'title': title.isNotEmpty ? title : '健康警示',
        'desc': desc,
        'level': level,
        'icon': icon,
        'sortTs': DateTime.tryParse(logTs ?? ''),
      };
    });

    // ★ 第五十三輪 familyfix53：狀態篩選只對有真實狀態機的持久化警報
    // （persistedItems）有意義——logItems（活動流水）沒有 status 欄位，
    // 見 [_AlertStatusFilter] enum 定義處的說明。選了非「全部狀態」時，
    // 不能讓 logItems 混進來變成一批看不出狀態的「未分類」項目。
    final bool statusFilterActive = _statusFilter != _AlertStatusFilter.all;
    final combined = statusFilterActive
        ? [...persistedItems]
        : [...persistedItems, ...logItems];
    // 其餘（跌倒歷史 + 活動警示）依時間新到舊排序；缺時間戳的排最後，
    // 不擠到最前面誤導使用者以為是最新事件。
    combined.sort((a, b) {
      final DateTime? tsA = a['sortTs'] as DateTime?;
      final DateTime? tsB = b['sortTs'] as DateTime?;
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      return tsB.compareTo(tsA);
    });

    // ★ 第五十二輪 F2：後端 `days` 篩選只涵蓋 emergencyAlerts（見本函式
    // 檔頭說明），這裡對合併後的完整清單再篩一次，確保 logItems 也遵守
    // 同一個時間範圍。缺時間戳的項目（sortTs == null，例如活動流水解析
    // 失敗）一律視為「無法確認是否落在範圍內」而排除，避免把時間不明的
    // 舊資料誤判成落在「本週／本月」範圍內；「全部」（days == null）不
    // 套用此篩選，維持原有全部顯示的行為。
    // ★ 第五十三輪 familyfix53：`custom` 比照辦理，改用選定的起訖日期
    // （含端點的當地曆日整天）當邊界。⚠️ 已知限制：這裡的 `sortTs` 是用
    // `DateTime.tryParse()` 解析後端回傳、未帶時區標記的 UTC 字串——Dart
    // 在字串沒有 'Z'／offset 標記時會當成「裝置本地時間」解讀，不是真的
    // 換算時區，因此日界前後 8 小時內的 logItems 可能被誤篩（emergencyAlerts
    // 的日期範圍是後端用 `tw_day_range_to_utc()` 正確換算，不受影響）。這是
    // round 41 就存在的既有解析方式，round 53 沿用同一套慣例、不在本輪修
    // 正——要修正得盤點全檔對時間字串的解析方式，範圍與風險都超出「新增
    // 自訂日期範圍」這個任務，留給之後專門一輪處理。
    List<Map<String, dynamic>> filtered = combined;
    if (_timeRange == _AlertTimeRange.custom &&
        _customStartDate != null &&
        _customEndDate != null) {
      final rangeStart = DateTime(
        _customStartDate!.year,
        _customStartDate!.month,
        _customStartDate!.day,
      );
      final rangeEndExclusive = DateTime(
        _customEndDate!.year,
        _customEndDate!.month,
        _customEndDate!.day,
      ).add(const Duration(days: 1));
      filtered = combined.where((item) {
        final ts = item['sortTs'] as DateTime?;
        return ts != null && !ts.isBefore(rangeStart) && ts.isBefore(rangeEndExclusive);
      }).toList();
    } else if (days != null) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      filtered = combined.where((item) {
        final ts = item['sortTs'] as DateTime?;
        return ts != null && !ts.isBefore(cutoff);
      }).toList();
    }

    if (!mounted) return;
    setState(() {
      _historyAlertItems = filtered;
      _historyLoading = false;
      _historyLoadFailed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: _isLoading ? _buildLoading() : _buildContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF1E293B)),
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
        },
      ),
      title: Text(
        '警示中心',
        style: GoogleFonts.notoSansTc(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1E293B),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E293B)),
          onPressed: () {
            HapticFeedback.lightImpact();
            _loadAlerts();
          },
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  /// 套用與 `family_home_tab.dart::_buildAlertPreview` 相同的「隔離不同長輩
  /// 警報」規則（比對 `elder_id`/`elderId` 與 [AlertCenterScreen.elderRoomId]），
  /// 維持兩邊過濾邏輯一致。
  /// ⚠️ 這裡優先用 `elderRoomId`（Socket 端 `elder_id` 送的是 4 位數房間代號
  /// 字串），只有它缺漏時才退回 `elderId`（DB 整數 id）——兩者是不同欄位，
  /// 誤用 `elderId` 會讓比對恆不相等，即時警報整段被錯誤濾空。
  List<Map<String, dynamic>> _filteredActiveAlerts() {
    final currentElderIdStr = widget.elderRoomId ?? widget.elderId?.toString();
    return widget.activeAlerts.where((a) {
      final aElderId = (a['elder_id'] ?? a['elderId'])?.toString();
      if (currentElderIdStr != null && aElderId != null && aElderId != currentElderIdStr) {
        return false; // 隔離不同長輩的警報
      }
      return true;
    }).toList();
  }

  Widget _buildContent() {
    final realtimeAlerts = _filteredActiveAlerts();
    // ★ 第五十二輪 F2：警示紀錄區塊（含時間篩選器）一律渲染在下方
    // ListView 裡，不再用「完全沒有警示」的整頁空狀態去頂替、隱藏它——
    // 否則使用者切到「本週」剛好沒有紀錄，若即時警報／健康建議恰好也
    // 都是空的，會被整頁空狀態蓋掉、連篩選器都看不到，等於走不出目前
    // 選到的空篩選範圍（正是這次「要找某筆記錄」問題的翻版）。
    // 改成：即時警報／健康建議兩個來源都空時，把原本的「🎉 目前沒有
    // 警示」卡片當成 ListView 的第一個項目（而不是整頁替換 body）——
    // `_buildEmptyState()` 內部只有 Container/SizedBox/Text，沒有
    // Expanded/Flexible，包進無界高度的 ListView item 不會有鐵律 #14
    // 那種 RenderFlex 例外，只是不再垂直置中，改成貼齊頂端顯示。
    // 警示紀錄區塊照樣接在後面，讓使用者能繼續切換到本月／全部查找
    // 較舊的紀錄。
    final bool otherSourcesEmpty = _alerts.isEmpty && realtimeAlerts.isEmpty;

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (otherSourcesEmpty) ...[
            _buildEmptyState(),
            const SizedBox(height: 20),
          ],
          // ★ 即時跌倒／CCTV 警報排最前面、視覺上更醒目：緊急事件不能被
          // 下方的健康建議淹沒。樣式與文案沿用 family_home_tab.dart 預覽區
          // 既有寫法（紅色系、🚨 標題、信心度百分比）。
          if (realtimeAlerts.isNotEmpty) ...[
            _buildRealtimeAlertsHeader(realtimeAlerts.length),
            const SizedBox(height: 12),
            ...realtimeAlerts.map(_buildRealtimeAlertCard),
            const SizedBox(height: 20),
          ],
          // ★ 第四十一輪（item 1 追加）：跌倒歷史 + 活動警示，依時間新到舊。
          // ★ 第五十二輪 F2：一律渲染（見上方註解），不再用 isNotEmpty 守門。
          _buildHistoryAlertsSection(_historyAlertItems),
          const SizedBox(height: 20),
          if (_alerts.isNotEmpty) ...[
            _buildSummaryCard(),
            const SizedBox(height: 20),
            _buildAlertsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryAlertsSection(List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📋 警示紀錄',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        // ★ 第五十二輪 F2：本週／本月／全部時間篩選器，取代原本「持續往下
        // 滑動」找舊紀錄的唯一方式。
        // ★ 第五十三輪 familyfix53：新增「自訂」日期範圍（見
        // _buildTimeRangeSelector／_selectCustomRange）。
        _buildTimeRangeSelector(),
        if (_timeRange == _AlertTimeRange.custom) _buildCustomRangeHint(),
        const SizedBox(height: 12),
        // ★ 第五十三輪 familyfix53：狀態篩選器（全部狀態／未處理／處理中／
        // 已結案），與時間範圍篩選器並列，讓家屬能同時縮小兩個維度查找。
        _buildStatusFilterSelector(),
        const SizedBox(height: 12),
        if (_historyLoading)
          _buildHistoryLoading()
        else if (_historyLoadFailed)
          _buildHistoryError()
        else if (items.isEmpty)
          _buildHistoryEmpty()
        else ...[
          ...items.map(_buildHistoryAlertCard),
          if (_timeRange == _AlertTimeRange.all || _timeRange == _AlertTimeRange.custom)
            _buildAllRangeHint(),
        ],
      ],
    );
  }

  /// ★ 第五十二輪 F2：警示紀錄的時間範圍篩選器（本週／本月／全部）。用
  /// `ChoiceChip`——與 `family_interaction_tab.dart::_buildCatChip` 既有的
  /// 分類篩選同一套元件，維持家屬端一致的篩選 UI 語言。三顆固定中文短
  /// 標籤（非後端動態內容），外層仍包一層 `Wrap` 防窄螢幕換行時溢位
  /// （鐵律 #14）。
  Widget _buildTimeRangeSelector() {
    Widget chip(_AlertTimeRange value, String label) {
      final bool isSel = _timeRange == value;
      return ChoiceChip(
        label: Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel ? Colors.white : const Color(0xFF475569),
          ),
        ),
        selected: isSel,
        selectedColor: const Color(0xFF59B294),
        backgroundColor: const Color(0xFFF1F5F9),
        side: BorderSide(
          color: isSel ? const Color(0xFF59B294) : const Color(0xFFCBD5E1),
        ),
        // 載入中不接受切換——避免快速連續點擊造成競態載入（見
        // _loadHistoryAlerts 開頭的 _historyLoading 重入防護）。
        onSelected: _historyLoading
            ? null
            : (_) {
                if (_timeRange == value) return;
                HapticFeedback.selectionClick();
                setState(() => _timeRange = value);
                _loadHistoryAlerts();
              },
      );
    }

    // ★ 第五十三輪 familyfix53：「自訂」與其餘三顆固定範圍不同——本身不是
    // 可以直接切換的固定值，而是開啟 [_selectCustomRange] 日期選擇器的
    // 入口，選完才會把 [_timeRange] 切到 custom。標籤刻意維持固定文字
    // 「自訂」、不隨已選日期變動（實際選了哪個範圍見 [_buildCustomRangeHint]），
    // 避免在 Wrap 裡的 ChoiceChip 標籤塞進長度不固定的日期字串。
    // ⚠️ 不像上面 chip() 會在「點擊目前已選中的那顆」時提早 return——已經
    // 是 custom 時再點一次仍要重新開啟選擇器，讓使用者能調整已選範圍。
    final bool isCustomSel = _timeRange == _AlertTimeRange.custom;
    final Widget customChip = ChoiceChip(
      avatar: Icon(
        Icons.date_range_rounded,
        size: 16,
        color: isCustomSel ? Colors.white : const Color(0xFF475569),
      ),
      label: Text(
        '自訂',
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          fontWeight: isCustomSel ? FontWeight.w800 : FontWeight.w600,
          color: isCustomSel ? Colors.white : const Color(0xFF475569),
        ),
      ),
      selected: isCustomSel,
      selectedColor: const Color(0xFF59B294),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(
        color: isCustomSel ? const Color(0xFF59B294) : const Color(0xFFCBD5E1),
      ),
      onSelected: _historyLoading ? null : (_) => _selectCustomRange(),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(_AlertTimeRange.week, '本週'),
        chip(_AlertTimeRange.month, '本月'),
        chip(_AlertTimeRange.all, '全部'),
        customChip,
      ],
    );
  }

  /// ★ 第五十三輪 familyfix53：目前自訂範圍實際選取的起訖日期——「自訂」
  /// chip 本身文字固定不變（見上方註解），改用這個獨立的 [Text] 顯示目前
  /// 生效的範圍，並提示可以再點一次「自訂」調整。純 [Text]（非 [Row]），
  /// 寬度不足時交由文字自動換行，不會有鐵律 #14 的 RenderFlex 溢位風險。
  Widget _buildCustomRangeHint() {
    if (_customStartDate == null || _customEndDate == null) {
      return const SizedBox.shrink();
    }
    String fmt(DateTime d) => '${d.year}/${d.month}/${d.day}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '已選取 ${fmt(_customStartDate!)} – ${fmt(_customEndDate!)}，可再次點擊「自訂」調整',
        style: GoogleFonts.notoSansTc(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  /// ★ 第五十三輪 familyfix53：警示紀錄狀態篩選器（全部狀態／未處理／處理
  /// 中／已結案），與時間範圍篩選器並列。只有真正查得到 `alertId` 的持久化
  /// 警報才有狀態機概念（見 [_AlertStatusFilter] enum 定義處的說明）；選了
  /// 非「全部狀態」時 [_loadHistoryAlerts] 會把沒有狀態概念的活動流水
  /// （logItems）整段排除，不會混進一批看不出狀態的「未分類」項目。用另一
  /// 個 selectedColor（藍）與時間範圍篩選器（綠）區分，避免兩排 chip 混淆
  /// 成同一組篩選。
  Widget _buildStatusFilterSelector() {
    Widget chip(_AlertStatusFilter value) {
      final bool isSel = _statusFilter == value;
      return ChoiceChip(
        label: Text(
          value.label,
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel ? Colors.white : const Color(0xFF475569),
          ),
        ),
        selected: isSel,
        selectedColor: const Color(0xFF3B82F6),
        backgroundColor: const Color(0xFFF1F5F9),
        side: BorderSide(
          color: isSel ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1),
        ),
        // 載入中不接受切換，理由同時間範圍篩選器（防競態載入）。
        onSelected: _historyLoading
            ? null
            : (_) {
                if (_statusFilter == value) return;
                HapticFeedback.selectionClick();
                setState(() => _statusFilter = value);
                _loadHistoryAlerts();
              },
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _AlertStatusFilter.values.map(chip).toList(),
    );
  }

  /// 警示紀錄局部載入中——只影響這個區塊，不是整頁滿版 loading（那會讓
  /// 使用者失去目前的捲動位置）。
  Widget _buildHistoryLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  /// ★ 第五十二輪 F2：警示紀錄載入失敗——刻意與「這個時間範圍內沒有紀錄」
  /// 的空狀態（見 [_buildHistoryEmpty]）做視覺區分（紅色系＋錯誤圖示＋
  /// 重試按鈕，而非中性灰階），使用者才能分辨「這個篩選範圍真的沒事」
  /// 與「其實可能有資料，只是這次沒抓到」。
  Widget _buildHistoryError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626), size: 32),
          const SizedBox(height: 8),
          Text(
            '警示紀錄載入失敗，請檢查網路後重試',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFB91C1C),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _loadHistoryAlerts(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('重新載入', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
          ),
        ],
      ),
    );
  }

  /// 目前所選時間範圍內沒有警示紀錄——中性提示，刻意與 [_buildHistoryError]
  /// 做視覺區分（見該函式註解）。
  Widget _buildHistoryEmpty() {
    // ★ 第五十三輪 familyfix53：新增 `custom` 分支——少了它會是編譯期的
    // non_exhaustive_switch_expression 錯誤（switch expression 必須窮舉）。
    final String rangeLabel = switch (_timeRange) {
      _AlertTimeRange.week => '本週',
      _AlertTimeRange.month => '本月',
      _AlertTimeRange.all => '',
      _AlertTimeRange.custom =>
        _customStartDate != null && _customEndDate != null
            ? '${_customStartDate!.month}/${_customStartDate!.day}–'
                '${_customEndDate!.month}/${_customEndDate!.day}'
            : '所選範圍',
    };
    // ★ 第五十三輪 familyfix53：狀態篩選啟用時一併說明「是在這個狀態下」
    // 沒有紀錄，避免使用者誤以為這個時間範圍完全沒有任何警示。
    final String statusSuffix =
        _statusFilter == _AlertStatusFilter.all ? '' : '（${_statusFilter.label}）';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, color: Color(0xFF94A3B8), size: 28),
          const SizedBox(height: 8),
          Text(
            '$rangeLabel沒有警示紀錄$statusSuffix',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  /// ★ 第五十二輪 F2：「全部」不套用時間篩選，但 limit 提高到
  /// [_kAllRangeLimit]——如實告知使用者這不是真的「無限」，避免以為漏了
  /// 更早的紀錄卻找不到原因。
  Widget _buildAllRangeHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '僅顯示最近 $_kAllRangeLimit 筆紀錄',
        style: GoogleFonts.notoSansTc(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  /// ★ 第四十五輪：把一筆已持久化的警報（有真實 `alert_id`）標記為誤報，
  /// 供管理端統計儀表板排除誤報。授權（`user_id` 需與該警報的長輩有關係）
  /// 與冪等行為完全交給後端 `POST /alerts/{alert_id}/false-alarm` 判斷，
  /// 前端只負責防重複點擊與樂觀更新畫面上的 `isFalseAlarm` 狀態。
  /// 這是與「確認」（acknowledge）完全獨立的動作——本畫面目前沒有任何地方
  /// 呼叫 acknowledge 端點，故不涉及互相覆蓋的問題。
  Future<void> _markFalseAlarm(String itemId, int alertId) async {
    if (_falseAlarmPending.contains(itemId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '標記為誤報？',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '確定要把這則警報標記為誤報嗎？標記後將從統計中排除。',
          style: GoogleFonts.notoSansTc(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '確定標記',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 沿用 _loadHistoryAlerts 既有慣例：家屬 user_id 讀 SharedPreferences 的
    // 'caregiver_id'，不額外要求呼叫端多傳一個 widget 參數。
    final prefs = await SharedPreferences.getInstance();
    final familyUserId = prefs.getInt('caregiver_id');
    if (familyUserId == null) {
      if (!mounted) return;
      // ★ 第五十輪（適老化）：讀不到家屬身分是可重試的狀況（重新登入即可
      // 解決），語意上是「警告」而非硬錯誤，改走 ErrorHandler.showWarning。
      ErrorHandler.showWarning(context, '無法確認家屬身分，請重新登入後再試');
      return;
    }

    setState(() => _falseAlarmPending.add(itemId));
    try {
      final result = await ApiService.markFalseAlarm(alertId: alertId, userId: familyUserId);
      if (!mounted) return;
      if (result.success) {
        setState(() {
          final idx = _historyAlertItems.indexWhere((it) => it['id'] == itemId);
          if (idx != -1) {
            _historyAlertItems[idx] = {
              ..._historyAlertItems[idx],
              'isFalseAlarm': true,
            };
          }
        });
        // ★ 第五十輪（適老化）：改用統一的大字級／高對比 SnackBar。
        ErrorHandler.showSuccess(context, '已標記為誤報');
      } else {
        // ★ 第五十一輪：改顯示後端實際原因（找不到這筆警報／尚未與這位長輩
        // 綁定／伺服器錯誤），不再全部塌成同一句「標記誤報失敗」。
        ErrorHandler.showWarning(context, '標記誤報失敗：${result.friendlyReason}');
      }
    } finally {
      if (mounted) setState(() => _falseAlarmPending.remove(itemId));
    }
  }

  /// ★ 第四十九輪 item 12：家屬主動回報一筆警報「已處理完畢」——警報狀態機
  /// 第三態。與 `_markFalseAlarm` 是完全獨立的動作（本畫面同時提供兩個
  /// 按鈕），冪等行為交給後端 `POST /alerts/{alert_id}/resolve` 判斷，
  /// 前端只負責防重複點擊與樂觀更新畫面上的 `status`。
  Future<void> _resolveAlertAction(String itemId, int alertId) async {
    if (_resolvePending.contains(itemId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '回報已處理？',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '確定這則警報已經處理完畢了嗎？標記後將不再收到相關的重複提醒。',
          style: GoogleFonts.notoSansTc(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '確定回報',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFF59B294),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 沿用 _loadHistoryAlerts／_markFalseAlarm 既有慣例：家屬 user_id 讀
    // SharedPreferences 的 'caregiver_id'，不額外要求呼叫端多傳一個
    // widget 參數。
    final prefs = await SharedPreferences.getInstance();
    final familyUserId = prefs.getInt('caregiver_id');
    if (familyUserId == null) {
      if (!mounted) return;
      // ★ 第五十輪（適老化）：同 _markFalseAlarm，可重試的狀況用 showWarning。
      ErrorHandler.showWarning(context, '無法確認家屬身分，請重新登入後再試');
      return;
    }

    setState(() => _resolvePending.add(itemId));
    try {
      final result = await ApiService.resolveAlert(alertId: alertId, userId: familyUserId);
      if (!mounted) return;
      if (result.success) {
        setState(() {
          final idx = _historyAlertItems.indexWhere((it) => it['id'] == itemId);
          if (idx != -1) {
            _historyAlertItems[idx] = {
              ..._historyAlertItems[idx],
              'status': 'resolved',
              // 家屬自己在本畫面回報，來源固定是 'family'——與後端
              // `resolve_alert_endpoint` 呼叫 `alert_state.resolve_alert()`
              // 時沿用的預設值一致（見該端點說明）。
              'resolution_source': 'family',
            };
          }
        });
        ErrorHandler.showSuccess(context, '已回報處理完畢');
      } else {
        // ★ 第五十一輪：同 _markFalseAlarm，顯示後端實際原因。
        ErrorHandler.showWarning(context, '回報失敗：${result.friendlyReason}');
      }
    } finally {
      if (mounted) setState(() => _resolvePending.remove(itemId));
    }
  }

  /// 跌倒歷史（`_emergencyAlerts`）與活動警示（`_realLogs`）合併後的單筆卡片。
  /// 視覺語言沿用本畫面既有的 `_buildAlertCard`（白底卡＋色框＋圖示徽章），
  /// 刻意比上方即時警報卡片內斂——那些是「正在發生」，這裡是「曾經發生」。
  Widget _buildHistoryAlertCard(Map<String, dynamic> item) {
    final level = item['level'] as String? ?? 'medium';
    final color = level == 'high' ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final icon = item['icon'] as IconData? ?? Icons.warning_amber_rounded;
    final String itemId = item['id'] as String? ?? '';
    final int? alertId = item['alertId'] as int?;
    final bool isFalseAlarm = item['isFalseAlarm'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] as String? ?? '警示',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['desc'] as String? ?? '',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ★ 第四十五輪：只有查得到真實 alert_id 的持久化警報才提供動作
          //   控制項——logItems（活動流水）沒有對應的 emergency_alerts
          //   列，alertId 恆為 null，不會顯示這個區塊。
          // ★ 第五十二輪 F2：原本「回報已處理」／「這是誤報」兩個並排
          //   按鈕收斂成單一控制項，見 [_buildAlertActionArea]。
          if (alertId != null) ...[
            const SizedBox(height: 10),
            _buildAlertActionArea(
              itemId,
              alertId,
              item['status'] as String?,
              item['resolution_source'] as String?,
              isFalseAlarm,
            ),
          ],
        ],
      ),
    );
  }

  /// ★ 第五十二輪 F2：警示紀錄卡片的動作區——取代原本各自獨立的
  /// `_buildResolveAction`／`_buildFalseAlarmAction` 兩個並排按鈕。
  ///
  /// 已結案（`status == 'resolved'`，`isFalseAlarm` 併入判斷以相容
  /// `alert_state.mark_false_alarm()` 尚未連動 status 之前寫入的極舊資料
  /// ——正常情況下兩者必然同步，見 `database.py` 開機時對這批舊資料的
  /// backfill）一律只顯示唯讀徽章＋一行「已結案的紀錄不能再更改」說明，
  /// 不提供任何可按動作（任務 A：已結案不得再有動作鍵）。
  ///
  /// 未結案（active／acknowledged）顯示單一 `PopupMenuButton`：本體按鈕
  /// 顯示目前狀態（待處理／處理中），展開後提供「回報已處理」／「標記為
  /// 誤報」兩個選項（任務 B）。**刻意不提供「退回待處理」**——`resolved`
  /// 是後端刻意鎖死的終態（見 `services/alert_state.py` 檔頭），提供一個
  /// 後端會拒絕的選項只會讓家屬以為壞掉；若日後要支援「誤按反悔」，應該
  /// 是撤銷視窗（例如 5 秒內可撤銷）而不是重新開放已結案紀錄。
  Widget _buildAlertActionArea(
    String itemId,
    int alertId,
    String? status,
    String? resolutionSource,
    bool isFalseAlarm,
  ) {
    final bool resolved = status == 'resolved' || isFalseAlarm;
    if (resolved) {
      // 舊資料相容：is_false_alarm=1 但 resolution_source 尚未連動寫入時
      // （理論上不會發生，見上方函式註解），仍讓徽章顯示成誤報而非落入
      // 語意較模糊的「已結案」預設分支。
      final String? effectiveSource =
          (isFalseAlarm && (resolutionSource == null || resolutionSource.isEmpty))
              ? 'false_alarm'
              : resolutionSource;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildResolvedBadgeForSource(effectiveSource),
          const SizedBox(height: 4),
          Text(
            '已結案的紀錄不能再更改',
            style: GoogleFonts.notoSansTc(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      );
    }

    final bool isPending = _resolvePending.contains(itemId) || _falseAlarmPending.contains(itemId);
    final String currentLabel = status == 'acknowledged' ? '處理中' : '待處理';
    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<_AlertMenuAction>(
        enabled: !isPending,
        tooltip: '警報動作選單',
        onSelected: (action) {
          switch (action) {
            case _AlertMenuAction.resolve:
              _resolveAlertAction(itemId, alertId);
              break;
            case _AlertMenuAction.falseAlarm:
              _markFalseAlarm(itemId, alertId);
              break;
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: _AlertMenuAction.resolve,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF59B294)),
                const SizedBox(width: 8),
                Text('回報已處理', style: GoogleFonts.notoSansTc(fontSize: 14)),
              ],
            ),
          ),
          PopupMenuItem(
            value: _AlertMenuAction.falseAlarm,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag_outlined, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Text('標記為誤報', style: GoogleFonts.notoSansTc(fontSize: 14)),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          // ★ 鐵律 #14：本體標籤雖是固定短字串（待處理／處理中／回報中…），
          // 仍包 Flexible+ellipsis 以防裝置字級被使用者調大時擠壓版面。
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPending ? Icons.hourglass_top_rounded : Icons.pending_actions_rounded,
                size: 15,
                color: const Color(0xFF475569),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isPending ? '處理中…' : currentLabel,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFF475569)),
            ],
          ),
        ),
      ),
    );
  }

  /// 已結案徽章依 [resolutionSource] 分流文案／顏色，供 [_buildAlertActionArea]
  /// 呼叫。四種來源沿用第四十九／五十輪既有分類：`family`（家屬自己回報）、
  /// `developer`（開發者主控台代為結案）、`false_alarm`（標記誤報連動結案，
  /// 圖示／顏色沿用原本 `_buildFalseAlarmAction` 的「已標記為誤報」外觀）、
  /// `legacy_auto`（舊警報上線時系統自動結案，中性灰色＋歷史圖示，刻意與
  /// 其餘「有人確認過」的綠色系徽章區分）；其餘（含 null／空字串，理論上
  /// 不會出現在已結案分支）落入「已結案」預設文案。
  Widget _buildResolvedBadgeForSource(String? resolutionSource) {
    switch (resolutionSource) {
      case 'family':
        return _buildResolvedBadge(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF59B294),
          label: '已回報處理完畢',
        );
      case 'developer':
        return _buildResolvedBadge(
          icon: Icons.verified_user_rounded,
          color: const Color(0xFF59B294),
          label: '已由 Uban 團隊結案',
        );
      case 'false_alarm':
        return _buildResolvedBadge(
          icon: Icons.flag_rounded,
          color: const Color(0xFF94A3B8),
          label: '已標記為誤報',
        );
      case 'legacy_auto':
        return _buildResolvedBadge(
          icon: Icons.history_rounded,
          color: const Color(0xFF94A3B8),
          label: '舊警報，系統已自動結案',
        );
      default:
        return _buildResolvedBadge(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF59B294),
          label: '已結案',
        );
    }
  }

  /// 「已結案」唯讀徽章的共用外觀，供 [_buildResolvedBadgeForSource] 呼叫。
  /// 維持既有的 `Row` + `Flexible` + `TextOverflow.ellipsis` 結構（鐵律
  /// #14：同列有圖示＋文字時，文字必須可收縮，避免 RenderFlex 溢位）。
  Widget _buildResolvedBadge({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRealtimeAlertsHeader(int count) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            '🚨 即時警報（$count）',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFDC2626),
            ),
          ),
        ),
      ],
    );
  }

  /// 單筆即時警報卡片。標題／描述文案與信心度格式沿用
  /// `family_home_tab.dart::_buildAlertPreview` 的 activeItems 迴圈
  /// （約 :3176-3190），刻意鏡射而非抽共用元件——同檔已有先例（見該檔
  /// `_buildMonitorDeviceStatus` 開頭註解的理由：兩邊互不 import，各自只從
  /// 父層拿處理好的資料）。
  Widget _buildRealtimeAlertCard(Map<String, dynamic> a) {
    final type = (a['alert_type'] ?? a['alertType'] ?? 'fall').toString();
    final conf = a['confidence'];
    final confText = conf != null ? ' (信心度 ${(conf * 100).toStringAsFixed(0)}%)' : '';
    String title = '🚨 跌倒緊急警報';
    String desc = '監視機偵測到長輩疑似跌倒$confText，請立即確認！';
    if (type == 'crawl') {
      title = '⚠️ 疑似爬行警報';
      desc = '監視機偵測到長輩異常爬行動作$confText，請多加留意。';
    } else if (type == 'lying_down') {
      title = '⚠️ 久躺未起警報';
      desc = '長輩在監視區域久躺不起$confText，建議關懷確認。';
    } else if (type == 'prolonged_inactivity') {
      title = '⚠️ 長時間無活動警報';
      desc = '長輩活動量異常偏低$confText，請留意長輩身體狀況。';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 80,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '目前沒有警示',
            style: GoogleFonts.notoSansTc(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.elderName} 的健康狀況良好',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final highPriorityCount = _alerts.where((a) => 
      a.priority == AlertPriority.high || a.priority == AlertPriority.urgent
    ).length;
    final actionRequiredCount = _alerts.where((a) => a.actionRequired).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '警示總覽',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '共 ${_alerts.length} 個警示項目',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  '重要警示',
                  '$highPriorityCount',
                  Icons.warning_amber_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _buildSummaryItem(
                  '需處理',
                  '$actionRequiredCount',
                  Icons.assignment_turned_in_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.notoSansTc(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '警示詳情',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        ..._alerts.asMap().entries.map((entry) {
          return _buildAlertCard(entry.value, entry.key);
        }),
      ],
    );
  }

  Widget _buildAlertCard(Alert alert, int index) {
    final priorityColor = _getPriorityColor(alert.priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alert.priority == AlertPriority.high || alert.priority == AlertPriority.urgent
              ? priorityColor.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getAlertIcon(alert.type),
                      size: 16,
                      color: priorityColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      alert.priorityLabel,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: priorityColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ★ 2026-08-10 第二十輪（需求 2）：警報型別標籤由後端下發，長度不可控。
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alert.typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.title,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            alert.description,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          if (alert.recommendedActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '建議行動',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...alert.recommendedActions.map((action) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Color(0xFF64748B))),
                        Expanded(
                          child: Text(
                            action,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: (index * 100).ms)
      .fadeIn(duration: 400.ms)
      .slideX(begin: 0.1, end: 0);
  }

  Color _getPriorityColor(AlertPriority priority) {
    switch (priority) {
      case AlertPriority.urgent:
        return const Color(0xFFDC2626);
      case AlertPriority.high:
        return const Color(0xFFEF4444);
      case AlertPriority.medium:
        return const Color(0xFFF59E0B);
      case AlertPriority.low:
        return const Color(0xFF3B82F6);
    }
  }

  IconData _getAlertIcon(AlertType type) {
    switch (type) {
      case AlertType.emotionAbnormal:
        return Icons.mood_bad_rounded;
      case AlertType.vitalSignAbnormal:
        return Icons.favorite_rounded;
      case AlertType.activityAbnormal:
        return Icons.directions_walk_rounded;
      case AlertType.trendPrediction:
        return Icons.trending_up_rounded;
      case AlertType.medicationReminder:
        return Icons.medication_rounded;
      case AlertType.appointmentReminder:
        return Icons.event_rounded;
    }
  }
}
