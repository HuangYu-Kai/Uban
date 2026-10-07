// ★ 2026-10-07 家庭步數挑戰（家屬端）：卡片各狀態、目標面板、無溢位、基準換算、通知解析／去重。
// 溢位以 360×640、textScaler 1.3 驗證（CLAUDE.md 規則 14），亮／暗各一次。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/widgets/family_step_challenge_card.dart';
import 'package:flutter_application_1/services/api/step_challenge_api.dart';
import 'package:flutter_application_1/services/checkin_notification.dart';
import 'package:flutter_application_1/services/family_step_sync.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Elder _elder() => Elder(id: 1, elderId: 'e1', name: '王大明爸爸這個名字故意取得很長很長很長');

StepChallenge _data(
        {bool achieved = false, int members = 6, bool lastWeek = true}) =>
    StepChallenge(
      weekStart: '2026-10-05',
      weekEnd: '2026-10-11',
      goalSteps: 50000,
      totalSteps: 32000,
      progress: 0.64,
      achieved: achieved,
      members: [
        const StepChallengeMember(
            role: 'elder',
            id: 'e1',
            name: '王大明爸爸這個名字故意取得很長很長很長',
            steps: 12000),
        for (var i = 0; i < members - 1; i++)
          StepChallengeMember(
              role: 'family',
              id: '$i',
              name: '璿OwO璿OwO璿OwO璿OwO$i',
              steps: 1000 * (i + 1)),
      ],
      daily: [
        for (var i = 0; i < 7; i++)
          StepChallengeDaily(date: '2026-10-0${i + 1}', steps: i * 1500),
      ],
      lastWeek: lastWeek
          ? const StepChallengeLastWeek(
              goalSteps: 35000, totalSteps: 36000, achieved: true)
          : null,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'caregiver_id': 7}));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Widget child, {bool dark = false}) => MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
        builder: (ctx, w) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: w!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(16), child: child),
        ),
      );

  Widget card({
    StepChallengeLoader? loader,
    StepChallengeGoalSetter? setter,
    StepCountingState counting = StepCountingState.on,
    Future<FamilyStepOptIn> Function(int?)? optIn,
    ValueNotifier<int?>? steps,
    Key? key,
  }) =>
      FamilyStepChallengeCard(
        key: key,
        currentElder: _elder(),
        loader: loader ?? (_, __) async => _data(),
        goalSetter: setter ?? (_, __, ___) async => true,
        countingStateReader: () async => counting,
        optInRunner: optIn ?? (_) async => FamilyStepOptIn.granted,
        todaySteps: steps ?? ValueNotifier<int?>(4321),
      );

  group('FamilyStepChallengeCard', () {
    for (final dark in [false, true]) {
      testWidgets('完整狀態：進度、前 4 名＋…、我今天、上週，無溢位 dark=$dark',
          (tester) async {
        await phone(tester);
        await tester.pumpWidget(harness(card(), dark: dark));
        await tester.pumpAndSettle();
        expect(find.text('全家一起走'), findsOneWidget);
        expect(find.textContaining('3.2 萬 / 5 萬步 · 64%'), findsOneWidget);
        expect(find.byKey(const ValueKey('step_card_more')), findsOneWidget);
        expect(find.textContaining('我今天走了 4,321 步'), findsOneWidget);
        expect(find.textContaining('上週：全家走了 3.6 萬步，達標了'), findsOneWidget);
        expect(find.text('調整目標'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('成員 ≤4 不顯示 …；達標顯示徽章；無上週不顯示該行', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(card(
        loader: (_, __) async =>
            _data(achieved: true, members: 3, lastWeek: false),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step_card_more')), findsNothing);
      expect(find.byKey(const ValueKey('step_card_achieved')), findsOneWidget);
      expect(find.byKey(const ValueKey('step_card_lastweek')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未同意：顯示開始計算按鈕，按下後改顯示今天步數', (tester) async {
      await phone(tester);
      var asked = 0;
      await tester.pumpWidget(harness(card(
        counting: StepCountingState.off,
        optIn: (_) async {
          asked++;
          return FamilyStepOptIn.granted;
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('開始計算我的步數'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step_card_optin')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.byKey(const ValueKey('step_card_mine')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拒絕權限：顯示溫和提示與再試一次', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(card(
        counting: StepCountingState.off,
        optIn: (_) async => FamilyStepOptIn.permanentlyDenied,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step_card_optin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step_card_denied')), findsOneWidget);
      expect(find.text('再試一次'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('讀取失敗與尚未配對：友善文字、沒有按鈕', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(card(loader: (_, __) async => null)));
      await tester.pumpAndSettle();
      expect(find.textContaining('暫時讀不到全家的步數'), findsOneWidget);
      expect(find.text('調整目標'), findsNothing);

      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(harness(card(key: const ValueKey('b'))));
      await tester.pumpAndSettle();
      expect(find.textContaining('還沒有可以一起走的家人'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('目標面板：五個選項、選擇後儲存呼叫 setter 並重讀', (tester) async {
      await phone(tester);
      int? saved;
      var loads = 0;
      await tester.pumpWidget(harness(card(
        loader: (_, __) async {
          loads++;
          return _data();
        },
        setter: (f, e, g) async {
          saved = g;
          return true;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step_card_goal')));
      await tester.pumpAndSettle();
      for (final g in kStepChallengeGoals) {
        expect(find.byKey(ValueKey('step_goal_$g')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('step_goal_70000')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('step_goal_save')));
      await tester.pumpAndSettle();
      expect(saved, 70000);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('目標面板：設定失敗顯示友善錯誤並留在面板', (tester) async {
      await phone(tester);
      await tester
          .pumpWidget(harness(card(setter: (_, __, ___) async => false)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step_card_goal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step_goal_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step_goal_error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('點卡片開 7 日長條圖面板，無溢位', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(card()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全家一起走'));
      await tester.pumpAndSettle();
      expect(find.text('這週每天的步數'), findsOneWidget);
      expect(find.byKey(const ValueKey('step_week_bar_2026-10-03')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('computeFamilySteps（每日基準／進位）', () {
    const d1 = '2026-10-07';
    const d2 = '2026-10-08';

    test('第一次安裝：基準＝目前值，今天 0 步', () {
      final r = computeFamilySteps(prev: null, todayDate: d1, counter: 5000);
      expect(r.today, 0);
      expect(
          r.state,
          const StepBaselineState(
              date: d1, baseline: 5000, carry: 0, lastToday: 0));
    });

    test('同日累加', () {
      const prev =
          StepBaselineState(date: d1, baseline: 5000, carry: 0, lastToday: 0);
      final r = computeFamilySteps(prev: prev, todayDate: d1, counter: 5800);
      expect(r.today, 800);
      expect(r.state.lastToday, 800);
    });

    test('跨日：回傳昨日最終值，基準重設', () {
      const prev = StepBaselineState(
          date: d1, baseline: 5000, carry: 0, lastToday: 800);
      final r = computeFamilySteps(prev: prev, todayDate: d2, counter: 6000);
      expect(r.today, 0);
      expect(r.yesterdayDate, d1);
      expect(r.yesterdaySteps, 800);
      expect(
          r.state,
          const StepBaselineState(
              date: d2, baseline: 6000, carry: 0, lastToday: 0));
    });

    test('跨多日：不補傳（伺服器只收今天／昨天）', () {
      const prev = StepBaselineState(
          date: '2026-10-05', baseline: 5000, carry: 0, lastToday: 800);
      final r = computeFamilySteps(prev: prev, todayDate: d2, counter: 6000);
      expect(r.yesterdayDate, isNull);
    });

    test('跨日跨月跨年的前一天', () {
      expect(previousDateString('2026-11-01'), '2026-10-31');
      expect(previousDateString('2027-01-01'), '2026-12-31');
      expect(previousDateString('2028-03-01'), '2028-02-29');
    });

    test('重開機：進位收進已走步數，之後繼續累加；連續兩次重開機也不遺失', () {
      const prev = StepBaselineState(
          date: d1, baseline: 5000, carry: 0, lastToday: 800);
      final r1 = computeFamilySteps(prev: prev, todayDate: d1, counter: 120);
      expect(r1.state.carry, 800);
      expect(r1.state.baseline, 0);
      expect(r1.today, 920);
      final r2 =
          computeFamilySteps(prev: r1.state, todayDate: d1, counter: 300);
      expect(r2.today, 1100);
      final r3 =
          computeFamilySteps(prev: r2.state, todayDate: d1, counter: 50);
      expect(r3.state.carry, 1100);
      expect(r3.today, 1150);
    });

    test('負值計數器夾成 0', () {
      final r = computeFamilySteps(prev: null, todayDate: d1, counter: -5);
      expect(r.state.baseline, 0);
    });
  });

  group('shouldUploadSteps（節流）', () {
    final now = DateTime(2026, 10, 7, 12);
    test('今天第一次且有步數就傳；0 步不傳', () {
      expect(shouldUploadSteps(steps: 10, date: 'd'), isTrue);
      expect(shouldUploadSteps(steps: 0, date: 'd'), isFalse);
    });
    test('變化小於 50 且未滿 15 分鐘不傳；50 以上傳', () {
      final at = now.subtract(const Duration(minutes: 3));
      expect(
          shouldUploadSteps(
              steps: 130,
              date: 'd',
              lastUploadedDate: 'd',
              lastUploadedSteps: 100,
              lastUploadedAt: at,
              now: now),
          isFalse);
      expect(
          shouldUploadSteps(
              steps: 150,
              date: 'd',
              lastUploadedDate: 'd',
              lastUploadedSteps: 100,
              lastUploadedAt: at,
              now: now),
          isTrue);
    });
    test('滿 15 分鐘且有增加才傳；沒變不傳', () {
      final at = now.subtract(const Duration(minutes: 16));
      expect(
          shouldUploadSteps(
              steps: 110,
              date: 'd',
              lastUploadedDate: 'd',
              lastUploadedSteps: 100,
              lastUploadedAt: at,
              now: now),
          isTrue);
      expect(
          shouldUploadSteps(
              steps: 100,
              date: 'd',
              lastUploadedDate: 'd',
              lastUploadedSteps: 100,
              lastUploadedAt: at,
              now: now),
          isFalse);
    });
    test('換日：即使上次是昨天也重新傳', () {
      expect(
          shouldUploadSteps(
              steps: 5,
              date: 'd2',
              lastUploadedDate: 'd1',
              lastUploadedSteps: 9000),
          isTrue);
    });
  });

  group('FamilyStepSync.syncNow（注入計步器與上傳）', () {
    test('首次不上傳；之後變化 100 上傳，+20 被節流；偏好鍵寫入', () async {
      SharedPreferences.setMockInitialValues({FamilyStepSync.kConsent: true});
      final sync = FamilyStepSync.instance;
      final uploads = <String>[];
      var counter = 1000;
      sync.counterOverride = () async => counter;
      sync.uploaderOverride = (f, d, s) async {
        uploads.add('$f|$d|$s');
        return true;
      };
      addTearDown(() {
        sync.counterOverride = null;
        sync.uploaderOverride = null;
        sync.stop();
      });
      await sync.start(familyId: 7);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      sync.stop();
      expect(uploads, isEmpty);
      counter = 1100;
      final t = await sync.syncNow();
      expect(t, 100);
      expect(uploads.length, 1);
      expect(uploads.single, startsWith('7|'));
      expect(uploads.single, endsWith('|100'));
      counter = 1120;
      await sync.syncNow();
      expect(uploads.length, 1);
      final p = await SharedPreferences.getInstance();
      expect(p.getInt(FamilyStepSync.kBaselineCounter), 1000);
      expect(p.getInt(FamilyStepSync.kLastToday), 120);
    });
  });

  group('step-challenge 通知', () {
    setUp(CheckinNotification.resetDedupe);

    test('文字：half／achieved／未知 kind', () {
      final h = CheckinNotification.stepChallengeText(
          kind: 'half',
          elderName: '阿公',
          totalSteps: '25000',
          goalSteps: '50000');
      expect(h!.title, '全家這週已經走了一半囉！');
      expect(h.body, '25000/50000 步，繼續加油');
      final a = CheckinNotification.stepChallengeText(
          kind: 'achieved',
          elderName: '阿公',
          totalSteps: '50000',
          goalSteps: '50000',
          rewardFoodName: '蘋果');
      expect(a!.title, '全家達標了！🎉');
      expect(a.body, '這週一起走了 50000 步，阿公的小豬得到一份蘋果');
      expect(
          CheckinNotification.stepChallengeText(
              kind: 'x', elderName: '', totalSteps: '1', goalSteps: '2'),
          isNull);
    });

    test('名字為空退回「長輩」；沒有獎勵名稱不出現「一份」', () {
      final a = CheckinNotification.stepChallengeText(
          kind: 'achieved', elderName: ' ', totalSteps: '1', goalSteps: '2');
      expect(a!.body, contains('長輩的小豬'));
      expect(a.body, isNot(contains('一份')));
    });

    test('週別鍵：台灣週一為起點、跨週不同', () {
      // 2026-10-07 為週三 → 週一 2026-10-05。
      expect(CheckinNotification.twWeekKey(DateTime.utc(2026, 10, 7, 4)),
          '2026-10-05');
      // 週日 23:30 台灣（UTC 15:30）仍同週；週一 00:30 台灣（UTC 16:30）換週。
      expect(CheckinNotification.twWeekKey(DateTime.utc(2026, 10, 11, 15, 30)),
          '2026-10-05');
      expect(CheckinNotification.twWeekKey(DateTime.utc(2026, 10, 11, 16, 30)),
          '2026-10-12');
    });

    test('去重：同 elderId+kind+週別只一次；不同 kind 或 elder 各自獨立', () {
      final wk = CheckinNotification.twWeekKey();
      final k = 'step-challenge|e1|half|$wk';
      expect(CheckinNotification.seenRecently(k), isFalse);
      expect(CheckinNotification.seenRecently(k), isTrue);
      expect(CheckinNotification.seenRecently('step-challenge|e1|achieved|$wk'),
          isFalse);
      expect(
          CheckinNotification.seenRecently('step-challenge|e2|half|$wk'),
          isFalse);
    });

    test('偏好鍵預設 true、可關閉', () async {
      SharedPreferences.setMockInitialValues({});
      expect(CheckinNotification.stepChallengePrefKey,
          'step_challenge_notify_enabled');
      expect(await CheckinNotification.isStepChallengeEnabled(), isTrue);
      await CheckinNotification.setStepChallengeEnabled(false);
      expect(await CheckinNotification.isStepChallengeEnabled(), isFalse);
    });
  });
}
