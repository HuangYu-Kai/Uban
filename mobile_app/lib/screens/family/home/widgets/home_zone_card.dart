import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';

/// 長輩目前所在區域 / 監視機前偵測卡片（設計稿 `.zone`，不放房間圖示）。
class HomeZoneCard extends StatelessWidget {
  final List<dynamic> monitorDevices;
  final Map<String, dynamic>? elderZone;

  const HomeZoneCard({
    super.key,
    this.monitorDevices = const [],
    this.elderZone,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final List<dynamic> monitors = monitorDevices;
    final dynamic firstMonitor = monitors.isNotEmpty ? monitors.first : null;
    final int? deviceId = firstMonitor is Map
        ? int.tryParse((firstMonitor['deviceId'] ?? firstMonitor['id'])?.toString() ?? '')
        : null;
    final String deviceName =
        firstMonitor is Map ? (firstMonitor['deviceName']?.toString() ?? '監視機') : '監視機';

    Widget shell({
      required String title,
      required String subtitle,
      DateTime? updatedAt,
      bool active = false,
    }) {
      return FamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('長輩所在位置',
                style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Row(
              children: [
                FamDot(color: active ? c.brand : c.text3),
                const SizedBox(width: 10),
                // ★ 鐵律 #14：標題／副標含動態字串（監視機名稱），皆可收縮。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text, 16.5, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text2, 13.5, height: 1.4),
                      ),
                      if (updatedAt != null) ...[
                        const SizedBox(height: 4),
                        _buildZoneUpdatedHint(c, updatedAt),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms);
    }

    // 狀態 1：尚未綁定監視機——不呼叫任何 API，純粹依清單是否為空判斷。
    if (monitors.isEmpty || deviceId == null) {
      return shell(
        title: '尚未綁定監視機',
        subtitle: '綁定監視機後即可查看長輩目前所在的區域',
      );
    }

    final Map<String, dynamic>? zone = elderZone;
    final bool present = zone != null && zone['present'] == true;

    // 狀態 2：裝置已綁定，但目前沒有偵測到長輩。
    if (!present) {
      return shell(
        title: '目前未偵測到長輩',
        subtitle: '「$deviceName」目前鏡頭前沒有偵測到人',
        updatedAt: zone?['updatedAt'] as DateTime?,
      );
    }

    final Map<String, dynamic> zoneData = zone;
    final DateTime? enteredAt = zoneData['enteredAt'] as DateTime?;
    final DateTime? updatedAt = zoneData['updatedAt'] as DateTime?;

    // 狀態 3：目前偵測到長輩
    return shell(
      title: '偵測到長輩',
      subtitle: '已持續 ${_formatZoneDwell(enteredAt)}',
      updatedAt: updatedAt,
      active: true,
    );
  }

  Widget _buildZoneUpdatedHint(UbanColors c, DateTime updatedAt) {
    final Duration diff = DateTime.now().difference(updatedAt);
    final String text;
    if (diff.inMinutes < 1) {
      text = '最後更新：剛剛';
    } else if (diff.inMinutes < 60) {
      text = '最後更新：${diff.inMinutes} 分鐘前';
    } else if (diff.inHours < 24) {
      text = '最後更新：${diff.inHours} 小時前';
    } else {
      text = '最後更新：${diff.inDays} 天前';
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: famText(c.text3, 12),
    );
  }

  String _formatZoneDwell(DateTime? enteredAt) {
    if (enteredAt == null) return '剛剛';
    final int seconds = DateTime.now().difference(enteredAt).inSeconds;
    if (seconds < 90) return '剛剛';
    final int minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分鐘';
    final int hours = minutes ~/ 60;
    final int remMinutes = minutes % 60;
    if (remMinutes == 0) return '$hours 小時';
    return '$hours 小時 $remMinutes 分';
  }
}
