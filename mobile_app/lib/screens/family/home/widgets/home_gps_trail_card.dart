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

  /// 今日摘要（`LocationApi.getSummary`），僅 [_CardState.ready] 時有值。
  Map<String, dynamic>? _summary;

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

    // 今日摘要已含 sharing_enabled 與 last_update，不必再額外呼叫 getCurrentLocation。
    final result = await LocationApi.getSummary(elderId: elderId, userId: userId);
    if (!mounted) return;

    if (result == null) {
      setState(() => _state = _CardState.unavailable);
      return;
    }
    if (result['sharing_enabled'] != true) {
      setState(() => _state = _CardState.sharingDisabled);
      return;
    }
    setState(() {
      _state = _CardState.ready;
      _summary = result;
    });
  }

  /// 距離顯示：未滿 1 公里用「公尺」，其餘用「x.x 公里」。
  static String formatDistance(num meters) {
    if (meters < 1000) return '${meters.round()} 公尺';
    return '${(meters / 1000).toStringAsFixed(1)} 公里';
  }

  /// 「最後更新」相對時間文字（與舊版同一套分級：剛剛／分鐘／小時／天）。
  static String? _lastUpdateText(DateTime? at) {
    if (at == null) return null;
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '最後更新 剛剛';
    if (diff.inMinutes < 60) return '最後更新 ${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '最後更新 ${diff.inHours} 小時前';
    return '最後更新 ${diff.inDays} 天前';
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

    // 第一行（主要資訊）與第二行（狀態＋最後更新）。
    String subtitle;
    String? detail;
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
        final sm = _summary ?? const <String, dynamic>{};
        final lastUpdate = LocationApi.parseRecordedAt(sm['last_update']);
        final pointCount = (sm['point_count'] as num?)?.toInt() ?? 0;
        final distance = formatDistance((sm['distance_m'] as num?) ?? 0);
        final outingCount = (sm['outing_count'] as num?)?.toInt();
        if (pointCount == 0 && lastUpdate == null) {
          subtitle = '今天尚無定位資料';
        } else if (outingCount != null) {
          subtitle = '今天外出 $outingCount 次・$distance';
        } else {
          // 沒設定「家」就無法計算外出次數，只顯示移動距離。
          subtitle = '今天移動 $distance';
        }
        final String status;
        if (sm['has_home'] != true) {
          status = '到地圖設定家的位置，就能看到外出次數';
        } else if (sm['at_home'] == true) {
          status = '目前在家';
        } else if (sm['at_home'] == false) {
          status = '目前外出中';
        } else {
          status = '';
        }
        final updated = _lastUpdateText(lastUpdate);
        detail = [
          if (status.isNotEmpty) status,
          if (updated != null) updated,
        ].join('・');
        if (detail.isEmpty) detail = null;
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
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: _state == _CardState.ready ? FontWeight.w800 : FontWeight.w500,
                color: _state == _CardState.ready ? cs.onSurface : cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 第二行是動態字串（含「設定家」提示），放寬到 2 行並保留 ellipsis，避免溢位（鐵律 #14）。
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: GoogleFonts.notoSansTc(fontSize: 13, color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
