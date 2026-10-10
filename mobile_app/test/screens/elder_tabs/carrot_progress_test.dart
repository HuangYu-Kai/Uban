import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/carrot_progress.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_carrot_hint.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('規則來自 carrot 欄位', () {
    final p = CarrotProgress(steps: 0);
    expect(p.stepsPerCarrot, 500);
    expect(p.checkinsPerCarrot, 1);
    expect(p.dailyCap, 5);
  });

  test('earnedToday／stepsToNext', () {
    final p = CarrotProgress(steps: 1200, checkins: 1);
    expect(p.earnedToday, 3); // 2 + 1
    expect(p.stepsToNext, 300);
    expect(CarrotProgress(steps: 0).stepsToNext, 500);
    expect(CarrotProgress(steps: 500).stepsToNext, 500);
    expect(CarrotProgress(steps: 499).stepsToNext, 1);
  });

  test('每日上限', () {
    expect(CarrotProgress(steps: 2400, checkins: 0).isCapped, isFalse);
    expect(CarrotProgress(steps: 2500, checkins: 0).isCapped, isTrue);
    final p = CarrotProgress(steps: 10000, checkins: 9);
    expect(p.earnedToday, 5);
    expect(p.isCapped, isTrue);
  });

  test('提示文案', () {
    expect(CarrotProgress(steps: 1200).hintText, '再走 300 步，或打一次卡，就多 1 根');
    expect(CarrotProgress(steps: 3000).hintText, '今天的胡蘿蔔都拿到了，明天再來 🌙');
    expect(CarrotProgress(steps: null).hintText, '走路或打卡就能拿到胡蘿蔔');
    expect(CarrotProgress(steps: null, checkins: 9).hintText,
        '走路或打卡就能拿到胡蘿蔔');
  });

  test('零根提示', () {
    expect(CarrotProgress(steps: 100).emptyToast,
        '走路每 500 步，或打卡一次，就能拿到 1 根胡蘿蔔（每天最多 5 根）');
    expect(CarrotProgress(steps: 2500).emptyToast,
        '今天的 5 根胡蘿蔔都吃完了，明天再來 🌙');
    expect(CarrotProgress.rules.tutorialRulesText,
        '走路、打卡都能拿到胡蘿蔔，每天最多 5 根');
  });

  test('打卡是否多 1 根', () {
    expect(CarrotProgress(steps: 100, checkins: 1).lastCheckinGainedCarrot,
        isTrue);
    expect(CarrotProgress(steps: 2500, checkins: 1).lastCheckinGainedCarrot,
        isFalse); // 原本已滿 5
    expect(CarrotProgress(steps: 2000, checkins: 1).lastCheckinGainedCarrot,
        isTrue); // 4 -> 5
    expect(CarrotProgress(steps: 100, checkins: 0).lastCheckinGainedCarrot,
        isFalse);
  });

  test('跨 500 步門檻只在跨過時提示', () {
    expect(CarrotProgress(steps: 520).stepMilestoneMessage(480),
        '走到 500 步了！小豬多了 1 根胡蘿蔔 🥕');
    expect(CarrotProgress(steps: 700).stepMilestoneMessage(520), isNull);
    expect(CarrotProgress(steps: 480).stepMilestoneMessage(520), isNull);
    expect(CarrotProgress(steps: null).stepMilestoneMessage(0), isNull);
    // 已達上限：不提示
    expect(
        CarrotProgress(steps: 3000, checkins: 5).stepMilestoneMessage(2900),
        isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('進度提示在 360dp、1.5 倍字、${dark ? '深' : '淺'}色不溢位', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            extensions: [dark ? UbanColors.dark : UbanColors.light]),
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: w!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PetCarrotHint(text: CarrotProgress(steps: 1200).hintText),
          ),
        ),
      ));
      expect(find.textContaining('再走 300 步'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
