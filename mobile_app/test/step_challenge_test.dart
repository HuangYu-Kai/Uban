import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_step_challenge_bar.dart';
import 'package:flutter_application_1/services/api/step_challenge_api.dart';

// ★ 2026-10-07 家庭步數挑戰：格式化、解析、長輩端進度條與面板（360x640、字級 1.3）。
const _json = {
  'week_start': '2026-10-05',
  'week_end': '2026-10-11',
  'goal_steps': 50000,
  'total_steps': 32000,
  'progress': 0.64,
  'achieved': false,
  'members': [
    {'role': 'elder', 'id': '1', 'name': '王奶奶', 'steps': 12000},
    {'role': 'family', 'id': '2', 'name': '璿OwO 很長很長很長的暱稱測試', 'steps': 20000},
  ],
  'daily': [
    {'date': '2026-10-05', 'steps': 5000},
    {'date': '2026-10-06', 'steps': 9000},
    {'date': '2026-10-07', 'steps': 0},
  ],
  'last_week': {'goal_steps': 35000, 'total_steps': 36000, 'achieved': true},
};

Widget _wrap(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  test('格式化', () {
    expect(formatStepsWan(32000), '3.2 萬步');
    expect(formatStepsWan(50000), '5 萬步');
    expect(formatStepsWan(8500), '8,500 步');
    expect(formatStepsNum(32000), '3.2 萬');
    expect(formatProgressPercent(0.649), '64%');
    expect(formatProgressPercent(2), '100%');
    expect(formatProgressPercent(double.nan), '0%');
  });

  test('模型解析', () {
    final c = StepChallenge.tryParse(_json)!;
    expect(c.elderSteps, 12000);
    expect(c.familySteps, 20000);
    expect(c.titleText, '全家一起走：本週 3.2 萬 / 5 萬步');
    expect(c.summaryText, '您走了 1.2 萬步，家人走了 2 萬步');
    expect(c.daily.first.shortDate, '10/5');
    expect(c.lastWeek!.achieved, true);
    expect(StepChallenge.tryParse(null), isNull);
    expect(StepChallenge.tryParse({'goal_steps': 0}), isNull);
    expect(StepChallenge.tryParse({'goal_steps': 20000})!.lastWeek, isNull);
  });

  testWidgets('進度條與面板不溢位；null 時隱藏', (tester) async {
    final n = ValueNotifier<StepChallenge?>(null);
    await tester.pumpWidget(_wrap(PetStepChallengeBar(listenable: n)));
    expect(find.byKey(const ValueKey('step_challenge_bar')), findsNothing);

    n.value = StepChallenge.tryParse(_json);
    await tester.pump();
    expect(find.textContaining('全家一起走'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('step_challenge_bar')));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(find.textContaining('上週'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
