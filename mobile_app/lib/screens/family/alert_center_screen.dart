import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/predictive_alert_service.dart';
import '../../services/api_service.dart';
import '../../utils/error_handler.dart';

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

  const AlertCenterScreen({
    super.key,
    required this.elderName,
    this.elderId,
    this.elderRoomId,
    this.activeAlerts = const [],
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

  @override
  void initState() {
    super.initState();
    _loadAlerts();
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
    final historyItems = await _loadHistoryAlerts();

    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _historyAlertItems = historyItems;
      _isLoading = false;
    });
  }

  /// 抓取並合併 family_home_tab.dart 預覽區另外兩個真實來源：
  /// `_realLogs`（`GET /activity/elder/{elder_id}`，活動流水）與
  /// `_emergencyAlerts`（`GET /alerts/{elder_id}`，持久化跌倒／異常警報）。
  /// 抓法與寬容失敗處理逐一比照該檔 `_loadDynamicData`（:822-849）：
  /// user_id 讀不到就略過 `_emergencyAlerts` 這一段抓取，任何例外都吞掉——
  /// 警示中心只是少一批資料，不得整頁擲出例外或空白。
  Future<List<Map<String, dynamic>>> _loadHistoryAlerts() async {
    final elderIdForApi = widget.elderRoomId ?? widget.elderId?.toString();
    if (elderIdForApi == null || elderIdForApi.isEmpty) return [];

    List<dynamic> logs = [];
    List<dynamic> emergencyAlerts = [];
    try {
      logs = await ApiService.getElderActivityLogs(elderIdForApi, limit: 30);
      final prefs = await SharedPreferences.getInstance();
      final familyUserId = prefs.getInt('caregiver_id');
      if (familyUserId != null) {
        emergencyAlerts = await ApiService.getEmergencyAlerts(
          elderIdForApi,
          userId: familyUserId,
          limit: 30,
        );
      }
    } catch (e) {
      // 沿用 family_home_tab.dart 既有慣例：任何失敗都吞掉，不擲出例外。
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

    final combined = [...persistedItems, ...logItems];
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
    return combined;
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
    if (_alerts.isEmpty && realtimeAlerts.isEmpty && _historyAlertItems.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (_historyAlertItems.isNotEmpty) ...[
            _buildHistoryAlertsSection(_historyAlertItems),
            const SizedBox(height: 20),
          ],
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
        ...items.map(_buildHistoryAlertCard),
      ],
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
          // ★ 第四十五輪：只有查得到真實 alert_id 的持久化警報才提供「這是
          //   誤報」／「回報已處理」操作——logItems（活動流水）沒有對應的
          //   emergency_alerts 列，alertId 恆為 null，不會顯示這個區塊。
          // ★ 第四十九輪 item 12：兩個動作用 Wrap（不是 Row）並排——兩者
          //   都是後端動態決定要不要顯示、寬度不固定的按鈕／徽章，Wrap 在
          //   空間不足時會自動換行，避免 RenderFlex 溢位（鐵律 #14）。
          if (alertId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 6,
              children: [
                _buildResolveAction(
                  itemId,
                  alertId,
                  item['status'] as String?,
                  item['resolution_source'] as String?,
                  isFalseAlarm,
                ),
                _buildFalseAlarmAction(itemId, alertId, isFalseAlarm),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ★ 第四十九輪 item 12：「回報已處理」操作區——未回報時是可點擊按鈕，
  /// 已回報則依 [resolutionSource] 顯示對應的唯讀徽章。與
  /// [_buildFalseAlarmAction] 並排顯示（見 `_buildHistoryAlertCard` 的
  /// `Wrap`）。
  ///
  /// ★ 第四十九輪 item 12（收尾）：結案來源分流——不能讓「舊警報上線時
  /// 系統自動結案」（`legacy_auto`）或「開發者主控台代為結案」
  /// （`developer`）顯示成家屬自己回報的『已回報處理完畢』，那會誤導家屬
  /// 以為有人（甚至自己）已經確認過這則警報。
  Widget _buildResolveAction(
    String itemId,
    int alertId,
    String? status,
    String? resolutionSource,
    bool isFalseAlarm,
  ) {
    // 誤報已經有「已標記為誤報」徽章，後端 mark_false_alarm 也會自動把
    // status 連動轉成 resolved（見 routers/alert.py），這裡不重複顯示第二
    // 個語意重疊的「已完成」徽章。
    if (isFalseAlarm) return const SizedBox.shrink();

    if (status == 'resolved') {
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
        case 'legacy_auto':
          // 中性灰色＋歷史圖示：刻意與其餘「有人確認過」的綠色徽章區分，
          // 避免看起來像家屬處理過——這筆是系統上線時自動結案的舊警報，
          // 從來沒有人真的看過。
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

    final isPending = _resolvePending.contains(itemId);
    return SizedBox(
      height: 30,
      child: TextButton.icon(
        onPressed: isPending ? null : () => _resolveAlertAction(itemId, alertId),
        icon: Icon(
          isPending ? Icons.hourglass_top_rounded : Icons.check_circle_outline_rounded,
          size: 15,
        ),
        label: Text(
          isPending ? '回報中…' : '回報已處理',
          style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF59B294),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// 「已結案」唯讀徽章的共用外觀，供 [_buildResolveAction] 依
  /// `resolutionSource` 分流呼叫。維持既有的 `Row` + `Flexible` +
  /// `TextOverflow.ellipsis` 結構（鐵律 #14：同列有圖示＋文字時，文字必須
  /// 可收縮，避免 RenderFlex 溢位）。
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

  /// 「這是誤報」操作區：未標記時是可點擊按鈕，已標記則顯示唯讀徽章。
  /// 按鈕文案為固定短字串（非後端動態內容），不受 RenderFlex 溢位規則的
  /// 「動態字串」情境約束，但仍以 Flexible+ellipsis 包住徽章文字以求保險。
  Widget _buildFalseAlarmAction(String itemId, int alertId, bool isFalseAlarm) {
    if (isFalseAlarm) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_rounded, size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '已標記為誤報',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansTc(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      );
    }

    final isPending = _falseAlarmPending.contains(itemId);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        height: 30,
        child: TextButton.icon(
          onPressed: isPending ? null : () => _markFalseAlarm(itemId, alertId),
          icon: Icon(
            isPending ? Icons.hourglass_top_rounded : Icons.flag_outlined,
            size: 15,
          ),
          label: Text(
            isPending ? '標記中…' : '這是誤報',
            style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
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
