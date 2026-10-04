import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';

/// 長輩總覽卡（設計稿 `.elderhero`）：頭像、名字、年齡地區、狀態與今日步數。
///
/// 原卡片沒有「打電話／視訊」按鈕、也沒有吃藥打卡資料，所以這裡不放（不新增 API）。
class HomeElderHeaderCard extends StatelessWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final List<dynamic> realLogs;
  final GlobalKey? headerKey;

  const HomeElderHeaderCard({
    super.key,
    this.currentElder,
    this.isElderOnline = false,
    this.realLogs = const [],
    this.headerKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final online = isElderOnline;
    final name = currentElder?.displayName ?? '長輩';

    // 步數：沿用既有解析（從活動紀錄文字找「N 步」取最大值）。
    // 舊版沒有紀錄時會顯示寫死的 3850 步——那是假資料，改成沒有就不顯示這格。
    int totalSteps = 0;
    for (final item in realLogs) {
      final text = item['content']?.toString() ?? '';
      final m = RegExp(r'(\d{1,3}(?:,\d{3})*|\d+)\s*步').firstMatch(text);
      if (m != null) {
        final parsed = int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
        if (parsed > totalSteps) totalSteps = parsed;
      }
    }

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
