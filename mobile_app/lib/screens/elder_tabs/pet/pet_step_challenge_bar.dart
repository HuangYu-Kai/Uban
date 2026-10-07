import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../services/api/step_challenge_api.dart';

/// ★ 2026-10-07 家庭步數挑戰：小豬分頁的「全家一起走」精簡進度條。
///
/// 監聽 [StepChallengeApi.elderState]；null（讀取失敗／尚未讀到）時整塊不佔位，
/// 長輩端不顯示任何錯誤。點一下開底部面板看成員、近 7 天與上週結果。
/// 長輩大字、文字可換行、無固定高度，360 寬 + 放大字級不溢出。
class PetStepChallengeBar extends StatelessWidget {
  final ValueListenable<StepChallenge?>? listenable;
  const PetStepChallengeBar({super.key, this.listenable});

  static const _ink = Color(0xFF14532D);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StepChallenge?>(
      valueListenable: listenable ?? StepChallengeApi.elderState,
      builder: (context, c, _) {
        if (c == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            button: true,
            label: '${c.titleText}。${c.summaryText}',
            excludeSemantics: true,
            child: Material(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('step_challenge_bar'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => showStepChallengeSheet(context, c),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('👣 ${c.titleText}',
                          style: const TextStyle(
                              fontSize: 18,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: c.progress,
                          minHeight: 12,
                          backgroundColor: const Color(0xFFDCFCE7),
                          color: c.achieved
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          c.achieved
                              ? '🎉 目標達成了！${c.summaryText}'
                              : c.summaryText,
                          style: const TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: _ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 詳情底部面板：每位成員步數（大字）、近 7 天迷你長條、上週結果。
Future<void> showStepChallengeSheet(BuildContext context, StepChallenge c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => StepChallengeSheetBody(challenge: c),
  );
}

class StepChallengeSheetBody extends StatelessWidget {
  final StepChallenge challenge;
  const StepChallengeSheetBody({super.key, required this.challenge});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    const body = TextStyle(fontSize: 20, height: 1.4, color: Color(0xFF14532D));
    final maxDaily = c.daily.fold<int>(0, (m, d) => d.steps > m ? d.steps : m);
    final last = c.lastWeek;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.titleText,
                style: body.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('完成度 ${formatProgressPercent(c.progress)}', style: body),
            const SizedBox(height: 14),
            for (final m in c.members)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(m.isElder ? '${m.name}（您）' : m.name,
                            style: body)),
                    const SizedBox(width: 8),
                    Text(formatStepsWan(m.steps),
                        style: body.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            if (c.daily.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('最近 7 天',
                  style: body.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in c.daily.take(7))
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: maxDaily == 0
                                  ? 4
                                  : 4 + 56 * (d.steps / maxDaily),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(d.shortDate,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF166534))),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (last != null) ...[
              const SizedBox(height: 14),
              Text(
                  '上週：${formatStepsNum(last.totalSteps)} / ${formatStepsWan(last.goalSteps)}，${last.achieved ? '達成了 🎉' : '沒有達成，這週再加油'}',
                  style: body),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('關閉', style: TextStyle(fontSize: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
