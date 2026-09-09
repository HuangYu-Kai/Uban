import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/elder.dart';
import '../../services/api_service.dart';
import 'home/widgets/home_elder_header_card.dart';
import 'home/widgets/home_zone_card.dart';
import 'home/widgets/home_monitor_device_card.dart';
import 'home/widgets/home_ai_mood_radar_card.dart';
import 'home/widgets/home_alert_preview_card.dart';
import 'home/widgets/home_elder_life_feed.dart';

/// 🏠 子女端首頁 Tab (模組化架構：極光玻璃、AI 情緒氣象台、IPS 室內位置、生活時光牆與最新警示)
class FamilyHomeTab extends StatefulWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final VoidCallback? onNavigateToAlerts;

  /// ★ 2026-08-10 第十九輪（需求 4）：「撥打電話聊聊 → 開始撥號」的實際動作。
  /// 由父層 `FamilyMainScreen` 注入 `VideoCallScreen` 路徑。
  final List<Map<String, dynamic>> activeAlerts;
  final VoidCallback? onStartVideoCall;

  /// ★ 2026-08-18 IPS prototype：長輩目前所在區域卡片所需資料，由父層提供。
  final List<dynamic> monitorDevices;
  final Map<String, dynamic>? elderZone;
  final int? userId;

  /// ★ 2026-08-24（首頁「最新警示」互動化）：已被使用者滑掉／按下已讀鍵的警示複合鍵集合。
  final Set<String> dismissedAlertKeys;

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
    this.currentElder,
    this.isElderOnline = false,
    this.activeAlerts = const [],
    this.monitorDevices = const [],
    this.elderZone,
    this.userId,
    this.onNavigateToAlerts,
    this.onStartVideoCall,
    this.dismissedAlertKeys = const {},
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

class _FamilyHomeTabState extends State<FamilyHomeTab> {
  Map<String, dynamic>? _moodInsightData;
  List<dynamic> _realLogs = [];
  List<dynamic> _emergencyAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadDynamicData();
  }

  @override
  void didUpdateWidget(FamilyHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentElder?.id != oldWidget.currentElder?.id) {
      _loadDynamicData();
    }
  }

  Future<void> _loadDynamicData() async {
    if (widget.currentElder == null) return;
    final elderIdStr = widget.currentElder!.elderId ?? widget.currentElder!.id.toString();

    try {
      final insight = await ApiService.getElderMoodInsight(elderIdStr);
      final logs = await ApiService.getElderActivityLogs(elderIdStr, limit: 30);
      final prefs = await SharedPreferences.getInstance();
      final familyUserId = prefs.getInt('caregiver_id');
      final emergencyAlerts = familyUserId != null
          ? await ApiService.getEmergencyAlerts(elderIdStr, userId: familyUserId, limit: 30)
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
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTabletLandscape = constraints.maxWidth >= 900;

        if (isTabletLandscape) {
          return RefreshIndicator(
            color: const Color(0xFF38BDF8),
            backgroundColor: const Color(0xFF1E293B),
            onRefresh: _loadDynamicData,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 👈 左欄：即時狀態、AI 情緒氣象台、健康警報 (佔比 42%)
                  Expanded(
                    flex: 42,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HomeElderHeaderCard(
                          headerKey: widget.elderHeaderKey,
                          currentElder: widget.currentElder,
                          isElderOnline: widget.isElderOnline,
                          realLogs: _realLogs,
                        ),
                        const SizedBox(height: 16),
                        HomeZoneCard(
                          monitorDevices: widget.monitorDevices,
                          elderZone: widget.elderZone,
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
                          onNavigateToAlerts: widget.onNavigateToAlerts,
                          onAlertItemDismissed: widget.onAlertItemDismissed,
                          onOpenMonitorView: widget.onOpenMonitorView,
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
          color: const Color(0xFF38BDF8),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: _loadDynamicData,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. 長輩頂部極光卡片與在線狀態
                    HomeElderHeaderCard(
                      headerKey: widget.elderHeaderKey,
                      currentElder: widget.currentElder,
                      isElderOnline: widget.isElderOnline,
                      realLogs: _realLogs,
                    ),
                    const SizedBox(height: 16),

                    // 1.5 📍 IPS prototype：長輩目前所在區域
                    HomeZoneCard(
                      monitorDevices: widget.monitorDevices,
                      elderZone: widget.elderZone,
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
                      onNavigateToAlerts: widget.onNavigateToAlerts,
                      onAlertItemDismissed: widget.onAlertItemDismissed,
                      onOpenMonitorView: widget.onOpenMonitorView,
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
