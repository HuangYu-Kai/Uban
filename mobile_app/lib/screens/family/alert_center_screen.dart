import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/predictive_alert_service.dart';
import '../../services/api_service.dart';

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
      return <String, dynamic>{
        'id': persistedItemId,
        'title': title,
        'desc': desc,
        'level': 'high',
        'icon': Icons.warning_amber_rounded,
        'sortTs': DateTime.tryParse(detectedAt),
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

  /// 跌倒歷史（`_emergencyAlerts`）與活動警示（`_realLogs`）合併後的單筆卡片。
  /// 視覺語言沿用本畫面既有的 `_buildAlertCard`（白底卡＋色框＋圖示徽章），
  /// 刻意比上方即時警報卡片內斂——那些是「正在發生」，這裡是「曾經發生」。
  Widget _buildHistoryAlertCard(Map<String, dynamic> item) {
    final level = item['level'] as String? ?? 'medium';
    final color = level == 'high' ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final icon = item['icon'] as IconData? ?? Icons.warning_amber_rounded;

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
      child: Row(
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
