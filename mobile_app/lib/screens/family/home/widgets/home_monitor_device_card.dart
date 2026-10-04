import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';

/// 監控設備狀態（含跌倒警報高亮與長輩在此高亮；設計稿 `.cam`／`.devrow`）。
///
/// 原卡片沒有即時縮圖也沒有按鈕，所以不放縮圖（不畫假畫面）；每台監視機一列：
/// 狀態色點＋名稱＋說明，警報時整列換 danger 底，長輩在此時換淡海灣藍底。
class HomeMonitorDeviceCard extends StatelessWidget {
  final List<dynamic> monitorDevices;
  final List<Map<String, dynamic>> activeAlerts;
  final Map<String, dynamic>? elderZone;
  final Elder? currentElder;
  final GlobalKey? monitorStatusKey;

  const HomeMonitorDeviceCard({
    super.key,
    this.monitorDevices = const [],
    this.activeAlerts = const [],
    this.elderZone,
    this.currentElder,
    this.monitorStatusKey,
  });

  @override
  Widget build(BuildContext context) {
    final List<dynamic> monitors = monitorDevices;
    if (monitors.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (final d in monitors) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(_buildMonitorStatusCard(context, d));
    }

    return FamCard(
      key: monitorStatusKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FamSecHead(title: '監控設備狀態'),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMonitorStatusCard(BuildContext context, dynamic device) {
    if (device is! Map) return const SizedBox.shrink();
    final c = UbanColors.of(context);
    final String name = (device['deviceName'] ?? 'Unnamed').toString();
    final bool isOnline = device['isOnline'] == true;
    final dynamic deviceId = device['deviceId'] ?? device['id'];

    final deviceAlerts = activeAlerts
        .where((a) => (a['device_id'] ?? a['deviceId'])?.toString() == deviceId?.toString())
        .toList();
    final bool hasActiveAlert = deviceAlerts.isNotEmpty;
    final Map<String, dynamic>? mostSevereAlert = hasActiveAlert ? deviceAlerts.first : null;
    final String elderName = currentElder?.displayName ?? '長輩';
    final String alertType =
        (mostSevereAlert?['alert_type'] ?? mostSevereAlert?['alertType'] ?? 'fall').toString();

    final String? presentDeviceId = elderZone?['deviceId']?.toString();
    final bool isElderPresent = !hasActiveAlert &&
        elderZone?['present'] == true &&
        presentDeviceId != null &&
        presentDeviceId == deviceId?.toString();
    final String? presentZoneName =
        isElderPresent ? (elderZone?['zone'])?.toString() : null;
    final bool showZoneName = presentZoneName != null && presentZoneName != 'unknown';

    final Color rowBg = hasActiveAlert
        ? c.dangerContainer
        : (isElderPresent ? c.brandSoft : c.surface2);
    final Color dotColor = hasActiveAlert
        ? c.danger
        : (isOnline ? c.brand : c.text3);
    final Color subColor = hasActiveAlert
        ? c.danger
        : (isElderPresent ? c.brandStrong : c.text2);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          FamDot(color: dotColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOnline ? name : '(離線) $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(isOnline ? c.text : c.text2, 15.5,
                            weight: FontWeight.w700),
                      ),
                    ),
                    if (hasActiveAlert) ...[
                      const SizedBox(width: 8),
                      FamChip(label: _shortAlertTypeLabel(alertType), tone: FamTone.danger),
                    ] else if (isElderPresent) ...[
                      const SizedBox(width: 8),
                      const FamChip(label: '長輩在此', tone: FamTone.brand),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasActiveAlert
                      ? '$elderName ${_shortAlertTypeLabel(alertType)}，請立即查看監視畫面'
                      : (isElderPresent
                          ? '目前長輩所在此處${showZoneName ? '・$presentZoneName' : ''}'
                          : (isOnline ? '線上監控中' : '離線')),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: famText(subColor, 13,
                      weight: (hasActiveAlert || isElderPresent)
                          ? FontWeight.w600
                          : FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortAlertTypeLabel(String type) {
    const map = {
      'fall': '跌倒',
      'prolonged_inactivity': '久未活動',
      'lying_down': '倒地',
      'crawl': '爬行',
    };
    return map[type] ?? type;
  }
}
