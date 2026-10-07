import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/uban_glass_nav_bar.dart';
import 'home/widgets/home_elder_header_card.dart';
import 'home/widgets/home_checkin_card.dart';
import 'home/widgets/home_analysis_card.dart';
import 'home/widgets/home_zone_card.dart';
import 'home/widgets/home_gps_trail_card.dart';
import 'home/widgets/home_monitor_device_card.dart';
import 'home/widgets/home_ai_mood_radar_card.dart';
import 'home/widgets/home_alert_preview_card.dart';
import 'home/widgets/home_elder_life_feed.dart';
import 'widgets/elder_question_inbox.dart';

/// 🏠 子女端首頁 Tab (模組化架構：極光玻璃、AI 情緒氣象台、IPS 室內位置、生活時光牆與最新警示)
class FamilyHomeTab extends StatefulWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final VoidCallback? onNavigateToAlerts;

  /// ★ 2026-08-10 第十九輪（需求 4）：「撥打電話聊聊 → 開始撥號」的實際動作。
  /// 由父層 `FamilyMainScreen` 注入 `VideoCallScreen` 路徑。
  final List<Map<String, dynamic>> activeAlerts;

  /// 💬 長輩提問收件匣的重新整理訊號：父層收到 Socket `elder-question` 時遞增。
  /// 本分頁在 IndexedStack 底下會被保活、initState 只跑一次，因此必須靠這個
  /// 訊號才能即時反映新問題。
  final int questionRefreshToken;

  /// ★ 2026-10-07 打卡雙向互動：長輩打卡／漏打卡事件到達時由父層遞增，打卡卡片即重讀。
  final int checkinRefreshToken;
  final VoidCallback? onStartVideoCall;

  /// ★ 2026-08-18 IPS prototype：長輩目前所在區域卡片所需資料，由父層提供。
  final List<dynamic> monitorDevices;
  final Map<String, dynamic>? elderZone;
  final int? userId;

  /// ★ 2026-08-24（首頁「最新警示」互動化）：已被使用者滑掉／按下已讀鍵的警示複合鍵集合。
  final Set<String> dismissedAlertKeys;

  /// ★ 第五十二輪（任務一）：[dismissedAlertKeys] 是否已經從 SharedPreferences
  /// 讀取完成（見 `family_main_screen.dart::_dismissedKeysLoaded` 欄位宣告）。
  /// 預設 `true`：其他尚未接上這個旗標的呼叫端（例如未來新增的測試或畫面）
  /// 維持原本「一律照常渲染」的行為，只有目前唯一的正式呼叫端
  /// （`family_main_screen.dart`）會在冷啟動讀取完成前傳入 `false`。
  final bool dismissedKeysLoaded;

  /// 使用者滑掉或按下關閉鍵時回呼，通知父層把該複合鍵加入集合。
  final ValueChanged<String>? onAlertItemDismissed;

  /// 點擊「最新警示」清單中 CCTV／跌倒類警示時，開啟該監視機的監控檢視。
  final ValueChanged<String?>? onOpenMonitorView;

  // ★ 第四十一輪 item 2（第二階段）：新手指引用的高光目標 GlobalKey。
  final GlobalKey? elderHeaderKey;
  final GlobalKey? monitorStatusKey;
  final GlobalKey? aiMoodRadarKey;
  final GlobalKey? alertPreviewKey;

  const FamilyHomeTab({
    super.key,
    this.questionRefreshToken = 0,
    this.checkinRefreshToken = 0,
    this.currentElder,
    this.isElderOnline = false,
    this.activeAlerts = const [],
    this.monitorDevices = const [],
    this.elderZone,
    this.userId,
    this.onNavigateToAlerts,
    this.onStartVideoCall,
    this.dismissedAlertKeys = const {},
    this.dismissedKeysLoaded = true,
    this.onAlertItemDismissed,
    this.onOpenMonitorView,
    this.elderHeaderKey,
    this.monitorStatusKey,
    this.aiMoodRadarKey,
    this.alertPreviewKey,
  });

  @override
  State<FamilyHomeTab> createState() => _FamilyHomeTabState();
}

class _FamilyHomeTabState extends State<FamilyHomeTab>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _moodInsightData;
  List<dynamic> _realLogs = [];
  List<dynamic> _emergencyAlerts = [];
  int _checkinRefresh = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDynamicData();
  }

  // ── 切回此分頁／App 回前景的重新整理（下拉刷新沿用同一個入口）──
  // 本分頁在 IndexedStack 底下被保活；離屏時 TickerMode 為 false，用它判斷可見性。
  // _loadDynamicData 開頭會遞增 _checkinRefresh，今日打卡卡片的 refreshToken
  // 因此一併重讀（與下拉刷新走同一條路）。
  /// null 代表第一次 didChangeDependencies（initState 已載入，不重複載）。
  bool? _wasVisible;
  bool _visible = true;
  bool _isRefreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final was = _wasVisible;
    _wasVisible = _visible;
    // 不可見 → 可見：切回就重讀（不節流，由 _isRefreshing 擋重複請求）
    if (was == false && _visible) _refreshAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible && mounted) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing || !mounted) return;
    _isRefreshing = true;
    try {
      await _loadDynamicData();
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void didUpdateWidget(FamilyHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id) {
      _loadDynamicData();
    }
  }

  Future<void> _loadDynamicData() async {
    if (mounted) setState(() => _checkinRefresh++);
    if (widget.currentElder == null) return;
    final elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();

    try {
      final insight = await ApiService.getElderMoodInsight(elderIdStr);
      final logs = await ApiService.getElderActivityLogs(elderIdStr, limit: 30);
      final prefs = await SharedPreferences.getInstance();
      final familyUserId = prefs.getInt('caregiver_id');
      final emergencyAlerts = familyUserId != null
          ? await ApiService.getEmergencyAlerts(elderIdStr, userId: familyUserId, limit: 30, days: 30)
          : <dynamic>[];
      if (mounted) {
        setState(() {
          _moodInsightData = insight;
          _realLogs = logs;
          _emergencyAlerts = emergencyAlerts;
        });
      }
    } catch (e) {
      // 保持靜默處理，避免破壞性異常
    }
  }

  void _handleCareMessageSent(String contentMsg) {
    if (!mounted) return;
    setState(() {
      _realLogs.insert(0, {
        'log_id': DateTime.now().millisecondsSinceEpoch,
        'event_type': 'interaction',
        'content': contentMsg,
        // ★ 2026-10-07 交接 C1：後端時間為 UTC，樂觀插入必須帶 Z，否則被當台灣時間而晚 8 小時
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTabletLandscape = constraints.maxWidth >= 900;
        final c = UbanColors.of(context);
        // 底部留白 = 懸浮導覽列高度 + 安全區 + 16（導覽列浮在內容上方，見 FamilyMainScreen）。
        final double bottomPad =
            UbanGlassNavBar.totalHeight + MediaQuery.paddingOf(context).bottom + 16;

        if (isTabletLandscape) {
          return RefreshIndicator(
            color: c.brandFill,
            backgroundColor: c.surface,
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 👈 左欄：即時狀態、AI 情緒氣象台、健康警報 (佔比 42%)
                  Expanded(
                    flex: 42,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 💬 長輩提問收件匣：沒有待回覆問題時自動隱藏不佔位
                        if (widget.userId != null)
                          ElderQuestionInbox(
                            familyId: widget.userId!,
                            refreshToken: widget.questionRefreshToken,
                          ),
                        HomeElderHeaderCard(
                          headerKey: widget.elderHeaderKey,
                          currentElder: widget.currentElder,
                          isElderOnline: widget.isElderOnline,
                          realLogs: _realLogs,
                          refreshToken: _checkinRefresh,
                        ),
                        const SizedBox(height: 16),
                        HomeCheckinCard(
                          currentElder: widget.currentElder,
                          refreshToken: _checkinRefresh + widget.checkinRefreshToken,
                          userId: widget.userId,
                          onStartVideoCall: widget.onStartVideoCall,
                        ),
                        const SizedBox(height: 16),
                        HomeAnalysisCard(
                          currentElder: widget.currentElder,
                          userId: widget.userId,
                          refreshToken: _checkinRefresh + widget.checkinRefreshToken,
                        ),
                        const SizedBox(height: 16),
                        HomeZoneCard(
                          monitorDevices: widget.monitorDevices,
                          elderZone: widget.elderZone,
                        ),
                        const SizedBox(height: 16),
                        HomeGpsTrailCard(
                          currentElder: widget.currentElder,
                          userId: widget.userId,
                          // ★ 2026-10-07 交接 D6：接上下拉刷新／切回分頁訊號
                          refreshToken: _checkinRefresh,
                        ),
                        const SizedBox(height: 16),
                        HomeMonitorDeviceCard(
                          monitorStatusKey: widget.monitorStatusKey,
                          monitorDevices: widget.monitorDevices,
                          activeAlerts: widget.activeAlerts,
                          elderZone: widget.elderZone,
                          currentElder: widget.currentElder,
                        ),
                        const SizedBox(height: 16),
                        HomeAiMoodRadarCard(
                          aiMoodRadarKey: widget.aiMoodRadarKey,
                          currentElder: widget.currentElder,
                          moodInsightData: _moodInsightData,
                          realLogs: _realLogs,
                          onStartVideoCall: widget.onStartVideoCall,
                          onCareMessageSent: _handleCareMessageSent,
                        ),
                        const SizedBox(height: 16),
                        HomeAlertPreviewCard(
                          alertPreviewKey: widget.alertPreviewKey,
                          currentElder: widget.currentElder,
                          activeAlerts: widget.activeAlerts,
                          realLogs: _realLogs,
                          emergencyAlerts: _emergencyAlerts,
                          dismissedAlertKeys: widget.dismissedAlertKeys,
                          dismissedKeysLoaded: widget.dismissedKeysLoaded,
                          onNavigateToAlerts: widget.onNavigateToAlerts,
                          onAlertItemDismissed: widget.onAlertItemDismissed,
                          onOpenMonitorView: widget.onOpenMonitorView,
                          // ★ 2026-10-02：語音求救附位置時，點擊項目開 GPS 地圖需要 userId。
                          userId: widget.userId,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // 👉 右欄：動態生活時光牆 (佔比 58%)
                  Expanded(
                    flex: 58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HomeElderLifeFeed(
                          currentElder: widget.currentElder,
                          realLogs: _realLogs,
                          moodInsightData: _moodInsightData,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 📱 手機模式：單欄流式佈局
        return RefreshIndicator(
          color: c.brandFill,
          backgroundColor: c.surface,
          onRefresh: _refreshAll,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ★ 2026-10-07 交接 C2：長輩提問收件匣原本只在平板橫向版面，手機版補上
                    //   （沒有待回覆問題時自動隱藏不佔位）。
                    if (widget.userId != null)
                      ElderQuestionInbox(
                        familyId: widget.userId!,
                        refreshToken: widget.questionRefreshToken,
                      ),
                    // 1. 長輩頂部極光卡片與在線狀態
                    HomeElderHeaderCard(
                      headerKey: widget.elderHeaderKey,
                      currentElder: widget.currentElder,
                      isElderOnline: widget.isElderOnline,
                      realLogs: _realLogs,
                      refreshToken: _checkinRefresh,
                    ),
                    const SizedBox(height: 16),

                    // 1.2 ✅ 今日打卡進度（含長輩自建目標）
                    HomeCheckinCard(
                      currentElder: widget.currentElder,
                      refreshToken: _checkinRefresh + widget.checkinRefreshToken,
                      userId: widget.userId,
                      onStartVideoCall: widget.onStartVideoCall,
                    ),
                    const SizedBox(height: 16),
                    HomeAnalysisCard(
                      currentElder: widget.currentElder,
                      userId: widget.userId,
                      refreshToken: _checkinRefresh + widget.checkinRefreshToken,
                    ),
                    const SizedBox(height: 16),

                    // 1.5 📍 IPS prototype：長輩目前所在區域
                    HomeZoneCard(
                      monitorDevices: widget.monitorDevices,
                      elderZone: widget.elderZone,
                    ),
                    const SizedBox(height: 16),

                    // 1.55 🛰️ 戶外 GPS 定位／每日移動軌跡（與上面的 IPS 是不同子系統）
                    HomeGpsTrailCard(
                      currentElder: widget.currentElder,
                      userId: widget.userId,
                      // ★ 2026-10-07 交接 D6：接上下拉刷新／切回分頁訊號
                      refreshToken: _checkinRefresh,
                    ),
                    const SizedBox(height: 16),

                    // 1.6 📷 監控設備狀態（含跌倒警報高亮）
                    HomeMonitorDeviceCard(
                      monitorStatusKey: widget.monitorStatusKey,
                      monitorDevices: widget.monitorDevices,
                      activeAlerts: widget.activeAlerts,
                      elderZone: widget.elderZone,
                      currentElder: widget.currentElder,
                    ),
                    const SizedBox(height: 16),

                    // 2. 🤖 AI 長輩情緒氣象台 & 破冰金句卡片
                    HomeAiMoodRadarCard(
                      aiMoodRadarKey: widget.aiMoodRadarKey,
                      currentElder: widget.currentElder,
                      moodInsightData: _moodInsightData,
                      realLogs: _realLogs,
                      onStartVideoCall: widget.onStartVideoCall,
                      onCareMessageSent: _handleCareMessageSent,
                    ),
                    const SizedBox(height: 16),

                    // 3. 📸 長輩生活動態時光牆 (Elder Life Feed)
                    HomeElderLifeFeed(
                      currentElder: widget.currentElder,
                      realLogs: _realLogs,
                      moodInsightData: _moodInsightData,
                    ),
                    const SizedBox(height: 16),

                    // 4. 警示預覽
                    HomeAlertPreviewCard(
                      alertPreviewKey: widget.alertPreviewKey,
                      currentElder: widget.currentElder,
                      activeAlerts: widget.activeAlerts,
                      realLogs: _realLogs,
                      emergencyAlerts: _emergencyAlerts,
                      dismissedAlertKeys: widget.dismissedAlertKeys,
                      dismissedKeysLoaded: widget.dismissedKeysLoaded,
                      onNavigateToAlerts: widget.onNavigateToAlerts,
                      onAlertItemDismissed: widget.onAlertItemDismissed,
                      onOpenMonitorView: widget.onOpenMonitorView,
                      // ★ 2026-10-02：同上（語音求救附位置 → 開 GPS 地圖）。
                      userId: widget.userId,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
