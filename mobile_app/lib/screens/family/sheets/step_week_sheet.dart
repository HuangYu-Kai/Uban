import 'package:flutter/material.dart';

import '../../../services/api/step_challenge_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_sheet.dart';
import '../widgets/fam_ui.dart';

/// ★ 2026-10-07 家庭步數挑戰：本週每天的全家步數（7 日迷你長條圖）。
class StepWeekSheet extends StatelessWidget {
  final List<StepChallengeDaily> daily;

  const StepWeekSheet({super.key, required this.daily});

  static Future<void> show(BuildContext context,
      {required List<StepChallengeDaily> daily}) {
    return showUbanSheet<void>(context, (ctx) => StepWeekSheet(daily: daily));
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final days = daily.length > 7 ? daily.sublist(daily.length - 7) : daily;
    var maxSteps = 0;
    for (final d in days) {
      if (d.steps > maxSteps) maxSteps = d.steps;
    }
    const barArea = 96.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('這週每天的步數',
            style: famText(c.text, 18, weight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('全家（含長輩）每天合計', style: famText(c.text2, 13, height: 1.45)),
        const SizedBox(height: 16),
        if (days.isEmpty)
          Text('這週還沒有步數紀錄，走走就有了',
              key: const ValueKey('step_week_empty'),
              style: famText(c.text2, 14, height: 1.5))
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 數值與日期都以 FittedBox 縮放，窄螢幕／大字級不溢位（規則 14）。
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(formatStepsNum(d.steps),
                            maxLines: 1,
                            style: famText(c.text2, 11, tabular: true)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        key: ValueKey('step_week_bar_${d.date}'),
                        width: 16,
                        height: maxSteps <= 0
                            ? 4
                            : (barArea * d.steps / maxSteps).clamp(4.0, barArea),
                        decoration: BoxDecoration(
                          color: d.steps > 0 ? c.brandFill : c.surface2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(d.shortDate,
                            maxLines: 1, style: famText(c.text3, 11.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
