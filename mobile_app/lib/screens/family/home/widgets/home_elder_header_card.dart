import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../services/api_service.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';

/// 長輩總覽卡（設計稿 `.elderhero`）：頭像、名字、年齡地區、狀態與今日步數。
///
/// 原卡片沒有「打電話／視訊」按鈕、也沒有吃藥打卡資料，所以這裡不放（不新增 API）。
class HomeElderHeaderCard extends StatefulWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final List<dynamic> realLogs;
  final GlobalKey? headerKey;

  /// ★ 2026-10-07 交接 D2：父層刷新訊號（遞增即重讀今日步數）。
  final int refreshToken;

  /// 測試注入點：回傳今日步數（null＝沒資料）；null 時走真實 API。
  final Future<int?> Function(String elderId)? stepsLoader;

  const HomeElderHeaderCard({
    super.key,
    this.currentElder,
    this.isElderOnline = false,
    this.realLogs = const [],
    this.headerKey,
    this.refreshToken = 0,
    this.stepsLoader,
  });

  @override
  State<HomeElderHeaderCard> createState() => _HomeElderHeaderCardState();
}

class _HomeElderHeaderCardState extends State<HomeElderHeaderCard> {
  /// 今日步數；null＝沒有資料（整格不顯示，不當成 0 步）。
  int? _todaySteps;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  @override
  void didUpdateWidget(covariant HomeElderHeaderCard old) {
    super.didUpdateWidget(old);
    if (old.currentElder?.elderId != widget.currentElder?.elderId ||
        old.currentElder?.id != widget.currentElder?.id ||
        old.refreshToken != widget.refreshToken) {
      _loadSteps();
    }
  }

  /// ★ 2026-10-07 交接 D2：今日步數改讀 `GET /api/family_insight/steps/{id}`，
  /// 不再用正規式從聊天文字抓「N 步」（長輩隨口說的數字會被當成步數）。
  /// 後端 days 下限 7，所以取回 7 天序列的最後一筆（＝台灣今天）；沒有值就不顯示。
  Future<void> _loadSteps() async {
    final elderId = widget.currentElder?.elderId;
    if (elderId == null || elderId.isEmpty) {
      if (mounted) setState(() => _todaySteps = null);
      return;
    }
    int? steps;
    try {
      if (widget.stepsLoader != null) {
        steps = await widget.stepsLoader!(elderId);
      } else {
        final res = await ApiService.getStepsTrend(elderId, days: 7);
        final data = res['data'];
        if (res['status'] == 'success' && data is Map && data['available'] != false) {
          final series = data['series'];
          if (series is List && series.isNotEmpty && series.last is Map) {
            final v = (series.last as Map)['steps'];
            steps = v is num ? v.toInt() : null;
          }
        }
      }
    } catch (_) {
      steps = null;
    }
    if (!mounted) return;
    // 切換長輩期間舊請求回來：以目前長輩為準
    if (widget.currentElder?.elderId != elderId) return;
    setState(() => _todaySteps = (steps != null && steps > 0) ? steps : null);
  }

  @override
  Widget build(BuildContext context) {
    final currentElder = widget.currentElder;
    final headerKey = widget.headerKey;
    final c = UbanColors.of(context);
    final online = widget.isElderOnline;
    final name = currentElder?.displayName ?? '長輩';
    final totalSteps = _todaySteps ?? 0;

    final age = currentElder?.age;
    final loc = currentElder?.location;
    final meta = [
      if (age != null) '$age 歲',
      if (loc != null && loc.isNotEmpty && loc != '未知') loc,
    ].join('・');

    return FamCard(
      key: headerKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FamAvatar(name: name, size: 64),
              const SizedBox(width: 14),
              // ★ 鐵律 #14：名字／所在地長度不可控，皆可收縮。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 22, weight: FontWeight.w900),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text2, 13.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FamStat(label: '裝置狀態', value: online ? '在線' : '離線'),
              ),
              if (totalSteps > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FamStat(label: '今天步數', value: _formatSteps(totalSteps)),
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  static String _formatSteps(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
