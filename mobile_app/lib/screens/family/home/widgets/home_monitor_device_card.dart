import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';

/// 監控設備狀態（含跌倒警報高亮與長輩在此高亮）
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<dynamic> monitors = monitorDevices;
    if (monitors.isEmpty) return const SizedBox.shrink();

    return Container(
      key: monitorStatusKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
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
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.videocam_rounded, color: cs.onPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                '監控設備狀態',
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...monitors.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildMonitorStatusCard(context, d),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }

  Widget _buildMonitorStatusCard(BuildContext context, dynamic device) {
    if (device is! Map) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: hasActiveAlert
            ? (isDark ? const Color(0xFF3F1D1D) : const Color(0xFFFEF2F2))
            : (isElderPresent
                ? (isDark ? const Color(0xFF083344) : cs.primaryContainer)
                : cs.surfaceContainerLow),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasActiveAlert
              ? const Color(0xFFF87171)
              : (isElderPresent
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.4)),
          width: (hasActiveAlert || isElderPresent) ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasActiveAlert
                ? Colors.red.withValues(alpha: 0.22)
                : (isElderPresent
                    ? cs.primary.withValues(alpha: 0.15)
                    : (isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04))),
            blurRadius: (hasActiveAlert || isElderPresent) ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF34D399) : const Color(0xFF475569),
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: const Color(0xFF34D399).withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOnline ? name : '(離線) $name',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOnline ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (hasActiveAlert) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _shortAlertTypeLabel(alertType),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ] else if (isElderPresent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF06B6D4) : cs.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '長輩在此',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white : cs.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasActiveAlert
                      ? '⚠️ $elderName ${_shortAlertTypeLabel(alertType)}，請立即查看監視畫面'
                      : (isElderPresent
                          ? '📍 目前長輩所在此處${showZoneName ? ' · $presentZoneName' : ''}'
                          : (isOnline ? '線上監控中' : '離線')),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActiveAlert
                        ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626))
                        : (isElderPresent ? (isDark ? const Color(0xFF7DD3FC) : cs.primary) : cs.onSurfaceVariant),
                    fontWeight: (hasActiveAlert || isElderPresent)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
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
