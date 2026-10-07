import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../services/api/location_api.dart';
import '../../../../services/location_device_status.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';
import '../../elder_location_map_screen.dart';

/// 長輩戶外 GPS 定位 / 每日移動軌跡卡片。
///
/// ★ 刻意與 [HomeZoneCard]（標題「長輩所在位置」，室內攝影機式 IPS 定位）
///   用不同標題與圖示，避免家屬把「戶外 GPS」與「室內房間偵測」搞混——
///   這是兩個完全獨立的子系統。
class HomeGpsTrailCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;

  /// ★ 2026-10-07 交接 D6：父層下拉刷新／切回分頁時遞增，卡片即重讀（同 HomeCheckinCard）。
  final int refreshToken;

  const HomeGpsTrailCard({
    super.key,
    this.currentElder,
    this.userId,
    this.refreshToken = 0,
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
        oldWidget.userId != widget.userId ||
        oldWidget.refreshToken != widget.refreshToken) {
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

  /// 距離拆成「數字＋單位」給三格數字用（規則同 [formatDistance]）。
  static (String, String) _distanceParts(num meters) {
    if (meters < 1000) return ('${meters.round()}', '公尺');
    return ((meters / 1000).toStringAsFixed(1), '公里');
  }

  /// 在外時間：滿 1 小時用「H:MM 小時」，否則「N 分鐘」。
  static (String, String) _durationParts(int minutes) {
    if (minutes < 60) return ('$minutes', '分鐘');
    return ('${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}', '小時');
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);

    // 第一行（主要資訊）與第二行（狀態）；最後更新放右上小標籤。
    String subtitle;
    String? statusLine;
    String? updatedChip;
    // 長輩手機定位有問題時，警示優先於「目前在家／外出中」（那個狀態此時不可信）。
    String? deviceWarning;
    // 三格數字（僅有資料時）。
    List<(String, String, String?)>? kv;
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
        deviceWarning = LocationDeviceStatus.shortLabel(sm['device_status']);
        final String status;
        if (deviceWarning != null) {
          status = deviceWarning;
        } else if (sm['has_home'] != true) {
          status = '到地圖設定家的位置，就能看到外出次數';
        } else if (sm['at_home'] == true) {
          status = '目前在家';
        } else if (sm['at_home'] == false) {
          status = '目前外出中';
        } else {
          status = '';
        }
        statusLine = status.isEmpty ? null : status;
        updatedChip = _lastUpdateText(lastUpdate);
        if (!(pointCount == 0 && lastUpdate == null)) {
          final dist = _distanceParts((sm['distance_m'] as num?) ?? 0);
          final outMin = (sm['outside_minutes'] as num?)?.toInt();
          kv = [
            ('移動距離', dist.$1, dist.$2),
            if (outMin != null)
              ('在外時間', _durationParts(outMin).$1, _durationParts(outMin).$2),
            if (outingCount != null) ('外出次數', '$outingCount', '次'),
          ];
        }
        break;
    }

    final bool ready = _state == _CardState.ready;

    return FamCard(
      onTap: _openMap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ★ 刻意與 HomeZoneCard（室內 IPS）用不同標題：GPS 是戶外，兩個是獨立子系統。
          Row(
            children: [
              Expanded(
                child: Text(
                  'GPS 移動軌跡',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1.2),
                ),
              ),
              Text('查看地圖', style: famText(c.brandStrong, 13, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: ready
                ? famText(c.text, 18, weight: FontWeight.w900, height: 1.35)
                : famText(c.text2, 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // 狀態行是動態字串（含「設定家」提示），放寬到 2 行並保留 ellipsis（鐵律 #14）。
          if (statusLine != null) ...[
            const SizedBox(height: 4),
            Text(
              statusLine,
              style: deviceWarning != null
                  ? famText(c.warm, 13.5, weight: FontWeight.w700)
                  : famText(c.text2, 13.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (kv != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < kv.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: FamKv(label: kv[i].$1, value: kv[i].$2, unit: kv[i].$3),
                  ),
                ],
              ],
            ),
          ],
          if (updatedChip != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FamChip(label: updatedChip, tone: FamTone.brand, dot: true),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
