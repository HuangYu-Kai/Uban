import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../alert_center_screen.dart';
import '../../placeholder_screens.dart';
import '../../health_reminder_screen.dart';

/// 🏠 最新警示預覽卡片與警示清單元件
class HomeAlertPreviewCard extends StatelessWidget {
  final Elder? currentElder;
  final List<Map<String, dynamic>> activeAlerts;
  final List<dynamic> realLogs;
  final List<dynamic> emergencyAlerts;
  final Set<String> dismissedAlertKeys;
  final VoidCallback? onNavigateToAlerts;
  final ValueChanged<String>? onAlertItemDismissed;
  final ValueChanged<String?>? onOpenMonitorView;
  final GlobalKey? alertPreviewKey;

  const HomeAlertPreviewCard({
    super.key,
    this.currentElder,
    this.activeAlerts = const [],
    this.realLogs = const [],
    this.emergencyAlerts = const [],
    this.dismissedAlertKeys = const {},
    this.onNavigateToAlerts,
    this.onAlertItemDismissed,
    this.onOpenMonitorView,
    this.alertPreviewKey,
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
        'icon': Icons.warning_amber_rounded,
        'routeType': 'monitor',
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
        'icon': Icons.warning_amber_rounded,
        'routeType': 'monitor',
        'deviceId': persistedDeviceId,
      };
    }).toList();

    final allCombinedAlerts = [...activeItems, ...persistedAlertItems, ...alertItems];
    final visibleAlerts = allCombinedAlerts
        .where((item) => !dismissedAlertKeys.contains(item['id']))
        .toList();
    final displayAlerts = visibleAlerts.take(30).toList();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: alertPreviewKey,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.error,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.error.withValues(alpha: isDark ? 0.25 : 0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outline, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '最新警示',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outline, width: 1.2),
                      ),
                      child: Text(
                        '${displayAlerts.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
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
                        ),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Text(
                      '查看全部',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 13, color: cs.primary),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (displayAlerts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.verified_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.4), size: 44),
                    const SizedBox(height: 8),
                    Text(
                      '目前沒有任何警示',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
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
                padding: EdgeInsets.only(bottom: e.key < displayAlerts.length - 1 ? 12 : 0),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Icon(Icons.done_all_rounded, color: cs.onSurfaceVariant, size: 24),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color levelColor;
    Color iconBgColor;
    Color cardBgColor;
    Color titleColor;
    Color descColor;
    BorderSide borderSide;

    switch (data['level'] as String) {
      case 'high':
        levelColor = const Color(0xFFF87171);
        iconBgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        cardBgColor = isDark ? const Color(0xFF231012) : const Color(0xFFFEF2F2);
        titleColor = isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B);
        descColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
        borderSide = BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.2);
        break;
      case 'medium':
        levelColor = const Color(0xFFFBBF24);
        iconBgColor = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        cardBgColor = isDark ? const Color(0xFF221A08) : const Color(0xFFFFFBEB);
        titleColor = isDark ? const Color(0xFFFEF08A) : const Color(0xFF92400E);
        descColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
        borderSide = BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.2);
        break;
      default:
        levelColor = cs.primary;
        iconBgColor = cs.primaryContainer;
        cardBgColor = cs.surfaceContainerLow;
        titleColor = cs.onSurface;
        descColor = cs.onSurfaceVariant;
        borderSide = BorderSide(color: cs.primary.withValues(alpha: 0.4), width: 1.2);
    }

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.fromBorderSide(borderSide),
        boxShadow: [
          BoxShadow(
            color: levelColor.withValues(alpha: 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              data['icon'] as IconData,
              color: (data['level'] == 'high' && !isDark)
                  ? const Color(0xFFDC2626)
                  : ((data['level'] == 'medium' && !isDark)
                      ? const Color(0xFFD97706)
                      : (data['level'] != 'high' && data['level'] != 'medium' && !isDark
                          ? cs.primary
                          : levelColor)),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data['desc'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13.5,
                    color: descColor,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: levelColor,
              size: 22,
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  color: descColor.withValues(alpha: 0.7),
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
