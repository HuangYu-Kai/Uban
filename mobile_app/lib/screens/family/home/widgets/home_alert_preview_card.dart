import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/alert_display.dart';
import '../../../../utils/server_time.dart';
import '../../widgets/fam_ui.dart';
import '../../alert_center_screen.dart';
import '../../elder_location_map_screen.dart';
import '../../placeholder_screens.dart';
import '../../health_reminder_screen.dart';

/// 🏠 最新警示預覽卡片與警示清單元件
class HomeAlertPreviewCard extends StatelessWidget {
  final Elder? currentElder;
  final List<Map<String, dynamic>> activeAlerts;
  final List<dynamic> realLogs;
  final List<dynamic> emergencyAlerts;
  final Set<String> dismissedAlertKeys;

  /// ★ 第五十二輪（任務一）：[dismissedAlertKeys] 是否已經載入完成（見
  /// `family_main_screen.dart::_dismissedKeysLoaded` 欄位宣告的完整根因）。
  /// 為 `false` 時，即使 [activeAlerts]／[realLogs]／[emergencyAlerts] 已經
  /// 有資料，也一律視為「還不能顯示」——[dismissedAlertKeys] 在這個時間點
  /// 不可信（可能還是空集合），照常渲染會讓使用者已經滑掉的警示重新閃現。
  /// 預設 `true`：維持既有呼叫端（含本檔既有測試）「一律照常渲染」的行為。
  final bool dismissedKeysLoaded;
  final VoidCallback? onNavigateToAlerts;
  final ValueChanged<String>? onAlertItemDismissed;
  final ValueChanged<String?>? onOpenMonitorView;
  final GlobalKey? alertPreviewKey;

  /// ★ 2026-10-02：目前登入的家屬 user id。語音求救（`sos_voice`）附有長輩最後位置時，
  /// 點擊項目會開 [ElderLocationMapScreen]，該畫面的 REST 需要 `userId` 做關係驗證；
  /// 為 `null`（既有呼叫端／測試未傳）時，求救項目一律不可點，不會誤跳到監視畫面。
  final int? userId;

  const HomeAlertPreviewCard({
    super.key,
    this.currentElder,
    this.activeAlerts = const [],
    this.realLogs = const [],
    this.emergencyAlerts = const [],
    this.dismissedAlertKeys = const {},
    this.dismissedKeysLoaded = true,
    this.onNavigateToAlerts,
    this.onAlertItemDismissed,
    this.onOpenMonitorView,
    this.alertPreviewKey,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    // ★ 整合即時跌倒／異常警報（activeAlerts）至首頁「最新警示」
    final List<Map<String, dynamic>> activeItems = [];
    final currentElderIdStr = currentElder?.elderId ?? currentElder?.id.toString();
    for (final a in activeAlerts) {
      final aElderId = (a['elder_id'] ?? a['elderId'])?.toString();
      if (currentElderIdStr != null && aElderId != null && aElderId != currentElderIdStr) {
        continue; // 隔離不同長輩的警報
      }
      final type = (a['alert_type'] ?? a['alertType'] ?? 'fall').toString();
      final conf = a['confidence'];
      final confText = conf != null ? ' (信心度 ${(conf * 100).toStringAsFixed(0)}%)' : '';
      // ★ 2026-10-02（G196）：文案集中到 AlertDisplay；`sos_voice` 不再被寫成跌倒，
      //   未知型別退回中性的「異常狀況」。
      final String title = AlertDisplay.title(type);
      String desc = AlertDisplay.liveDesc(type, confText: AlertDisplay.isSos(type) ? '' : confText);
      // 語音求救附帶的最後位置（後端只在有位置時才帶；沒有就什麼都不顯示）。
      final loc = AlertDisplay.isSos(type) ? AlertDisplay.parseLocation(a) : null;
      if (loc != null) {
        final String? locText = AlertDisplay.lastLocationText(AlertDisplay.parseLocationAt(a));
        desc = locText != null ? '$desc $locText，點擊查看' : '$desc 點擊查看最後位置';
      }
      final String? liveDeviceId = (a['device_id'] ?? a['deviceId'])?.toString();
      final String? liveAlertIdRaw = (a['alert_id'] ?? a['alertId'])?.toString();
      final String? liveTs = (a['timestamp'] ?? a['ts'])?.toString();
      final String liveItemId = (liveAlertIdRaw != null && liveAlertIdRaw.isNotEmpty)
          ? 'alert:$liveAlertIdRaw'
          : 'live:$type:${liveDeviceId ?? ''}:${liveTs ?? ''}';
      activeItems.add({
        'id': liveItemId,
        'title': title,
        'desc': desc,
        'level': 'high',
        'icon': AlertDisplay.icon(type),
        // 求救沒有監視畫面：有位置 → 開地圖；沒位置 → 不可點（不可導向監視畫面）
        'routeType': AlertDisplay.isSos(type) ? (loc != null ? 'location' : null) : 'monitor',
        'deviceId': liveDeviceId,
      });
    }

    final alertItems = realLogs.where((log) {
      final text = log['content']?.toString() ?? '';
      final etype = log['event_type']?.toString() ?? '';
      return etype == 'alert' || text.contains('警示') || text.contains('提醒') || text.contains('未確認');
    }).map((log) {
      final desc = log['content']?.toString() ?? '';
      final title = desc.split('|').first.replaceAll(RegExp(r'【.*?】'), '').trim();
      final level = desc.contains('用藥') || desc.contains('未確認') ? 'high' : 'medium';
      final icon = desc.contains('用藥') ? Icons.medication_rounded : Icons.directions_walk_rounded;
      String? routeType;
      if (desc.contains('用藥') || desc.contains('服藥') || desc.contains('醫囑')) {
        routeType = 'health';
      } else if (desc.contains('提醒') || desc.contains('排程') || desc.contains('行程')) {
        routeType = 'schedule';
      }
      final String? logIdRaw = log['log_id']?.toString();
      final String? logTs = log['timestamp']?.toString();
      final String logItemId = (logIdRaw != null && logIdRaw.isNotEmpty)
          ? 'log:$logIdRaw'
          : 'log-fallback:${logTs ?? ''}:${desc.hashCode}';
      return {
        'id': logItemId,
        'title': title.isNotEmpty ? title : '健康警示',
        'desc': desc,
        'level': level,
        'icon': icon,
        'routeType': routeType,
      };
    }).toList();

    final Set<String> liveAlertIds = activeAlerts
        .map((a) => (a['alert_id'] ?? a['alertId'])?.toString())
        .whereType<String>()
        .toSet();

    final persistedAlertItems = emergencyAlerts.where((row) {
      final rElderId = (row['elder_id'] ?? row['elderId'])?.toString();
      if (currentElderIdStr != null && rElderId != null && rElderId != currentElderIdStr) {
        return false;
      }
      final rAlertId = (row['alert_id'] ?? row['alertId'])?.toString();
      if (rAlertId != null && liveAlertIds.contains(rAlertId)) {
        return false;
      }
      return true;
    }).map((row) {
      final type = (row['alert_type'] ?? row['alertType'] ?? 'fall').toString();
      final detectedAt = (row['detected_at'] ?? row['detectedAt'] ?? '').toString();
      // ★ 2026-10-07：detected_at 是沒帶 Z 的 UTC，換成本地時間再顯示。
      final detectedLocal = ServerTime.parse(detectedAt);
      String whenStr = '';
      if (detectedLocal != null) {
        final dk = ServerTime.dateKey(detectedLocal);
        whenStr = '${dk.substring(5, 7)}/${dk.substring(8, 10)} ${ServerTime.clock(detectedLocal)}';
      }
      final String title = AlertDisplay.title(type);
      String desc = AlertDisplay.pastDesc(type);
      if (whenStr.isNotEmpty) {
        desc = '$desc（發生於 $whenStr）';
      }
      // 歷史求救若附有位置：點擊開地圖並直接顯示警報當天的軌跡。
      final loc = AlertDisplay.isSos(type) ? AlertDisplay.parseLocation(row as Map) : null;
      DateTime? locDate;
      if (loc != null) {
        desc = '$desc 點擊查看最後位置';
        locDate = AlertDisplay.parseLocationAt(row) ?? detectedLocal;
      }
      final String? persistedDeviceId = (row['device_id'] ?? row['deviceId'])?.toString();
      final String? persistedAlertIdRaw = (row['alert_id'] ?? row['alertId'])?.toString();
      final String persistedItemId = (persistedAlertIdRaw != null && persistedAlertIdRaw.isNotEmpty)
          ? 'alert:$persistedAlertIdRaw'
          : 'persisted:$type:${persistedDeviceId ?? ''}:$detectedAt';
      return {
        'id': persistedItemId,
        'title': title,
        'desc': desc,
        'level': 'high',
        'icon': AlertDisplay.icon(type),
        'routeType': AlertDisplay.isSos(type) ? (loc != null ? 'location' : null) : 'monitor',
        'deviceId': persistedDeviceId,
        'locationDate': locDate,
      };
    }).toList();

    final allCombinedAlerts = [...activeItems, ...persistedAlertItems, ...alertItems];
    final visibleAlerts = allCombinedAlerts
        .where((item) => !dismissedAlertKeys.contains(item['id']))
        .toList();
    // ★ 第五十二輪（任務一）：dismissedKeysLoaded 為 false 時 dismissedAlertKeys
    //   不可信（見欄位宣告），一律當作「沒有可顯示的項目」，不使用上面算出的
    //   visibleAlerts——旗標翻正後才會用真正過濾過的結果重新計算一次。
    final displayAlerts = dismissedKeysLoaded
        ? visibleAlerts.take(30).toList()
        : const <Map<String, dynamic>>[];
    final c = UbanColors.of(context);

    // 設計稿 `.card`＋`.sec-head`；待處理（嚴重）才用 danger 色點，其餘不染色。
    return FamCard(
      key: alertPreviewKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ★ 鐵律 #14：標題可收縮（FamSecHead 內為 Expanded＋ellipsis），
          //   計數徽章與「查看全部」固定在右側。
          FamSecHead(
            title: '最新警示',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FamChip(
                  label: '${displayAlerts.length}',
                  tone: displayAlerts.isEmpty ? FamTone.neutral : FamTone.danger,
                ),
                const SizedBox(width: 4),
                FamMore(
                  label: '查看全部',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (onNavigateToAlerts != null) {
                      onNavigateToAlerts!();
                    } else if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => AlertCenterScreen(
                            elderName: currentElder?.displayName ?? '長輩',
                            elderId: currentElder?.id,
                            elderRoomId: currentElder?.elderId ?? currentElder?.id.toString(),
                            activeAlerts: activeAlerts,
                            userId: userId,
                            dismissedAlertKeys: dismissedAlertKeys,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (!dismissedKeysLoaded)
            // ★ 第五十二輪（任務一）：沿用「目前沒有任何警示」同一副版面
            //   （置中 + 說明文字），只換掉文字——當下還不知道濾掉已讀警示後
            //   是否真的沒有項目，不可以宣稱「目前沒有任何警示」。
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: c.text3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '警示讀取中…',
                      style: famText(c.text2, 14, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else if (displayAlerts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FamDot(color: c.brand),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        '目前沒有任何警示',
                        style: famText(c.text2, 14.5, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...displayAlerts.asMap().entries.map((e) {
              final Map<String, dynamic> item = e.value;
              final String itemId = item['id'] as String;
              void handleDismiss() {
                HapticFeedback.lightImpact();
                onAlertItemDismissed?.call(itemId);
              }
              return Padding(
                padding: EdgeInsets.only(bottom: e.key < displayAlerts.length - 1 ? 10 : 0),
                child: Dismissible(
                  key: ValueKey(itemId),
                  direction: DismissDirection.endToStart,
                  background: _buildAlertDismissBackground(context),
                  onDismissed: (_) => handleDismiss(),
                  child: HomeAlertItem(
                    data: item,
                    index: e.key,
                    onDismiss: handleDismiss,
                    onTap: _navigationForAlertItem(item, context),
                  ),
                ),
              );
            }),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }

  Widget _buildAlertDismissBackground(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface3,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text('已讀', style: famText(c.text2, 14, weight: FontWeight.w700)),
    );
  }

  VoidCallback? _navigationForAlertItem(Map<String, dynamic> item, BuildContext context) {
    final String? routeType = item['routeType'] as String?;
    switch (routeType) {
      case 'monitor':
        final String? deviceId = item['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty || onOpenMonitorView == null) {
          return null;
        }
        return () {
          HapticFeedback.lightImpact();
          onOpenMonitorView!(deviceId);
        };
      case 'location':
        // ★ 2026-10-02：語音求救附帶位置 → 開長輩 GPS 地圖。elderId 與
        //   HomeGpsTrailCard 同一套算法（`elderId ?? id.toString()`，4 位數房間代號）。
        final elder = currentElder;
        final int? uid = userId;
        if (elder == null || uid == null || uid <= 0) return null;
        final DateTime? date = item['locationDate'] as DateTime?;
        return () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ElderLocationMapScreen(
                elderId: elder.elderId ?? elder.id.toString(),
                userId: uid,
                elderName: elder.displayName,
                initialDate: date,
              ),
            ),
          );
        };
      case 'schedule':
        final elder = currentElder;
        if (elder == null) return null;
        return () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DailyScheduleScreen(elderId: elder.id)),
          );
        };
      case 'health':
        final elder = currentElder;
        if (elder == null) return null;
        return () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HealthReminderScreen(
                elderId: elder.elderId ?? elder.id.toString(),
                elderName: elder.displayName,
              ),
            ),
          );
        };
      default:
        return null;
    }
  }
}

/// 最新警示單一項目卡片
class HomeAlertItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;

  const HomeAlertItem({
    super.key,
    required this.data,
    required this.index,
    this.onDismiss,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);

    // `.sev`：嚴重度用 10px 色點表達（取代圖示方塊）。
    // high → danger；medium → warm（待處理）；其餘 → 品牌色。
    final String level = data['level'] as String;
    final Color sev = level == 'high'
        ? c.danger
        : (level == 'medium' ? c.warm : c.brand);

    // 設計稿 `.alert`：surface2 底、圓角 18、padding 12/14。
    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FamDot(color: sev),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text, 15, weight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  data['desc'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text2, 13, height: 1.4),
                ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  color: c.text3,
                  size: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    ).animate(delay: (index * 80).ms).fadeIn().slideX(begin: 0.05);
  }
}
