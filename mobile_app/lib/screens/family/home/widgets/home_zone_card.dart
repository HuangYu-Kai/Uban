import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 長輩目前所在區域 / 監視機前偵測卡片
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<dynamic> monitors = monitorDevices;
    final dynamic firstMonitor = monitors.isNotEmpty ? monitors.first : null;
    final int? deviceId = firstMonitor is Map
        ? int.tryParse((firstMonitor['deviceId'] ?? firstMonitor['id'])?.toString() ?? '')
        : null;
    final String deviceName =
        firstMonitor is Map ? (firstMonitor['deviceName']?.toString() ?? '監視機') : '監視機';

    Widget header() {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.my_location_rounded, color: cs.onPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            '長輩所在位置',
            style: GoogleFonts.notoSansTc(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ],
      );
    }

    Widget shell(Widget child) {
      return Container(
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
        child: child,
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
    }

    // 狀態 1：尚未綁定監視機——不呼叫任何 API，純粹依清單是否為空判斷。
    if (monitors.isEmpty || deviceId == null) {
      return shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 14),
            Text(
              '尚未綁定監視機',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '綁定監視機後即可查看長輩目前所在的區域',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final Map<String, dynamic>? zone = elderZone;
    final bool present = zone != null && zone['present'] == true;

    // 狀態 2：裝置已綁定，但目前沒有偵測到長輩。
    if (!present) {
      final DateTime? lastUpdatedAt = zone?['updatedAt'] as DateTime?;
      return shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 14),
            Text(
              '目前未偵測到長輩',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '「$deviceName」目前鏡頭前沒有偵測到人',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (lastUpdatedAt != null) ...[
              const SizedBox(height: 10),
              _buildZoneUpdatedHint(lastUpdatedAt),
            ],
          ],
        ),
      );
    }

    final Map<String, dynamic> zoneData = zone;
    final DateTime? enteredAt = zoneData['enteredAt'] as DateTime?;
    final DateTime? updatedAt = zoneData['updatedAt'] as DateTime?;

    // 狀態 3：目前偵測到長輩
    return shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF34D399)),
                ),
                child: Text(
                  '偵測到長輩',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF006C4C),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已持續 ${_formatZoneDwell(enteredAt)}',
                  style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 10),
            _buildZoneUpdatedHint(updatedAt),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneUpdatedHint(DateTime updatedAt) {
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
      style: GoogleFonts.notoSansTc(fontSize: 11, color: const Color(0xFF64748B)),
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
