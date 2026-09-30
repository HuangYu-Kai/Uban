import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../services/api/location_api.dart';
import '../../elder_location_map_screen.dart';

/// 長輩戶外 GPS 定位 / 每日移動軌跡卡片。
///
/// ★ 刻意與 [HomeZoneCard]（標題「長輩所在位置」，室內攝影機式 IPS 定位）
///   用不同標題與圖示，避免家屬把「戶外 GPS」與「室內房間偵測」搞混——
///   這是兩個完全獨立的子系統。
class HomeGpsTrailCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;

  const HomeGpsTrailCard({
    super.key,
    this.currentElder,
    this.userId,
  });

  @override
  State<HomeGpsTrailCard> createState() => _HomeGpsTrailCardState();
}

enum _CardState { loading, ready, sharingDisabled, unavailable }

class _HomeGpsTrailCardState extends State<HomeGpsTrailCard> {
  _CardState _state = _CardState.loading;
  DateTime? _recordedAt;

  String? get _elderId => widget.currentElder?.elderId ?? widget.currentElder?.id.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeGpsTrailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentElder?.elderId != widget.currentElder?.elderId ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final elderId = _elderId;
    final userId = widget.userId;
    if (elderId == null || userId == null) {
      if (mounted) setState(() => _state = _CardState.unavailable);
      return;
    }

    final result = await LocationApi.getCurrentLocation(elderId: elderId, userId: userId);
    if (!mounted) return;

    if (result == null) {
      setState(() => _state = _CardState.unavailable);
      return;
    }
    if (result['sharing_enabled'] != true) {
      setState(() => _state = _CardState.sharingDisabled);
      return;
    }
    final point = result['point'] as Map<String, dynamic>?;
    setState(() {
      _state = _CardState.ready;
      _recordedAt =
          point != null ? DateTime.tryParse(point['recorded_at'] as String) : null;
    });
  }

  void _openMap() {
    final elderId = _elderId;
    final userId = widget.userId;
    if (elderId == null || userId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ElderLocationMapScreen(
          elderId: elderId,
          userId: userId,
          elderName: widget.currentElder?.displayName ?? '長輩',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget header() {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.route_rounded, color: cs.onSecondary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'GPS 移動軌跡',
              style: GoogleFonts.notoSansTc(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      );
    }

    String subtitle;
    switch (_state) {
      case _CardState.loading:
        subtitle = '讀取中…';
        break;
      case _CardState.unavailable:
        subtitle = '尚無法讀取，點此查看詳情';
        break;
      case _CardState.sharingDisabled:
        subtitle = '長輩尚未開啟位置分享';
        break;
      case _CardState.ready:
        final recordedAt = _recordedAt;
        if (recordedAt == null) {
          subtitle = '尚無定位資料';
        } else {
          final diff = DateTime.now().difference(recordedAt);
          if (diff.inMinutes < 1) {
            subtitle = '最後更新：剛剛';
          } else if (diff.inMinutes < 60) {
            subtitle = '最後更新：${diff.inMinutes} 分鐘前';
          } else if (diff.inHours < 24) {
            subtitle = '最後更新：${diff.inHours} 小時前';
          } else {
            subtitle = '最後更新：${diff.inDays} 天前';
          }
        }
        break;
    }

    return GestureDetector(
      onTap: _openMap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outline, width: 1.5),
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
            header(),
            const SizedBox(height: 14),
            Text(
              subtitle,
              style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '點此查看目前位置與每日移動軌跡',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }
}
