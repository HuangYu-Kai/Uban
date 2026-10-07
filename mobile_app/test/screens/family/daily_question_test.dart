// ★ 2026-10-07 每日一問（家屬端）：卡片、DailyQuestionScreen、出題對話框、API 模型與通知 payload。
//
// 純 UI／純函式測試：不打網路、不碰平台通道（播放器延後到按下播放才建立，測試不按）。
// 溢位以 360×640、textScaler 1.3 驗證（CLAUDE.md 規則 14）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/daily_question_screen.dart';
import 'package:flutter_application_1/screens/family/widgets/daily_question_card.dart';
import 'package:flutter_application_1/services/api/daily_question_api.dart';
import 'package:flutter_application_1/services/checkin_notification.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Elder _elder() => Elder(id: 1, elderId: 'e1', name: '王大明爸爸這個名字故意取得很長很長很長');

DailyQuestionItem _q(int id,
        {bool answered = false,
        String text = '',
        String? audio,
        bool cheered = false,
        String by = ''}) =>
    DailyQuestionItem(
      id: id,
      question: '您小時候最喜歡吃的一道菜或點心是什麼？現在還吃得到嗎？這是一道很長很長的題目 $id',
      assignedDate: '2026-10-0$id',
      askedByName: by,
      answered: answered,
      answerText: text,
      answerAudioUrl: audio,
      cheeredByMe: cheered,
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
          data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: w!,
        ),
        home: child,
      );

  Widget cardHarness(DailyQuestionCard card) => harness(Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: card),
      ));

  group('DailyQuestionCard', () {
    testWidgets('未回答：顯示題目與「未回答」，兩顆按鈕，無溢位', (tester) async {
      await phone(tester);
      await tester.pumpWidget(cardHarness(DailyQuestionCard(
        currentElder: _elder(),
        loader: (_) async => _q(1),
      )));
      await tester.pumpAndSettle();
      expect(find.text('每日一問'), findsOneWidget);
      expect(find.text('未回答'), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_card_question')), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_card_answer')), findsNothing);
      expect(find.text('出一題給長輩'), findsOneWidget);
      expect(find.text('看全部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已回答含語音：顯示摘要與 🔊，深色也無溢位', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyQuestionCard(
              currentElder: _elder(),
              loader: (_) async => _q(2,
                  answered: true,
                  text: '小時候最愛吃外婆做的蘿蔔糕，每年過年都吃不膩。' * 3,
                  audio: 'http://x/a.m4a'),
            ),
          ),
        ),
        dark: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('已回答'), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_card_answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_card_audio')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('讀取失敗：顯示友善訊息（不含例外字串）', (tester) async {
      await phone(tester);
      await tester.pumpWidget(cardHarness(DailyQuestionCard(
        currentElder: _elder(),
        loader: (_) async => null,
      )));
      await tester.pumpAndSettle();
      expect(find.text('暫時讀不到今天的小問題，稍後再試一次'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refreshToken 變動會重讀', (tester) async {
      await phone(tester);
      var calls = 0;
      Widget build(int token) => cardHarness(DailyQuestionCard(
            currentElder: _elder(),
            refreshToken: token,
            loader: (_) async {
              calls++;
              return _q(1, answered: calls > 1, text: '回答');
            },
          ));
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(find.text('未回答'), findsOneWidget);
      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('已回答'), findsOneWidget);
    });
  });

  group('DailyQuestionScreen', () {
    testWidgets('列表：已回答可回覆／已回覆／等待長輩回答／語音鈕，無溢位', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(DailyQuestionScreen(
        elderId: 'e1',
        elderName: _elder().name,
        historyLoader: (_, fid) async {
          expect(fid, 7); // 來自 caregiver_id
          return [
            _q(1, answered: true, text: '蘿蔔糕', audio: 'http://x/a.m4a'),
            _q(2, answered: true, text: '粽子', cheered: true, by: '小明'),
            _q(3, by: '小美'),
          ];
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('每日一問'), findsOneWidget);
      expect(find.text('出一題'), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_reply_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_reply_2')), findsNothing);
      expect(find.text('已回覆'), findsOneWidget);
      expect(find.text('等待長輩回答'), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_audio_btn')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空狀態與錯誤狀態為友善中文', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(DailyQuestionScreen(
        elderId: 'e1',
        elderName: '王爸爸',
        historyLoader: (_, __) async => [],
      )));
      await tester.pumpAndSettle();
      expect(find.text('還沒有每日一問的紀錄'), findsOneWidget);

      await tester.pumpWidget(harness(DailyQuestionScreen(
        key: const ValueKey('err'),
        elderId: 'e1',
        elderName: '王爸爸',
        historyLoader: (_, __) async => null,
      )));
      await tester.pumpAndSettle();
      expect(find.text('暫時讀不到每日一問'), findsOneWidget);
      expect(find.text('重新載入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('出一題：長度檢查、成功顯示對應提示並重讀', (tester) async {
      await phone(tester);
      var loads = 0;
      String? asked;
      await tester.pumpWidget(harness(DailyQuestionScreen(
        elderId: 'e1',
        elderName: '王大明爸爸這個名字故意取得很長很長很長',
        historyLoader: (_, __) async {
          loads++;
          return [];
        },
        asker: ({required question, category}) async {
          asked = question;
          return DailyAskResult(true, DailyQuestionApi.askSuccessMessage('later'),
              scheduledFor: 'later');
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dq_ask_open')));
      await tester.pumpAndSettle();

      // 太短：本機擋下，不呼叫 API。
      await tester.enterText(find.byKey(const ValueKey('dq_ask_text')), '嗨');
      await tester.ensureVisible(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      expect(find.text('題目至少要 4 個字喔'), findsOneWidget);
      expect(asked, isNull);

      // 點推薦題後送出。
      await tester.tap(find.textContaining('您小時候最喜歡吃的一道菜').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      expect(asked, contains('最喜歡吃的一道菜'));
      expect(find.text('已排入，長輩明天會看到'), findsOneWidget);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('出題失敗：對話框保留並顯示後端友善訊息', (tester) async {
      await phone(tester);
      await tester.pumpWidget(harness(DailyQuestionScreen(
        elderId: 'e1',
        elderName: '王爸爸',
        historyLoader: (_, __) async => [],
        asker: ({required question, category}) async =>
            const DailyAskResult(false, '待回答的題目太多了，請等長輩回答後再出題'),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dq_ask_open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dq_ask_text')), '您最喜歡哪一個節日？');
      await tester.ensureVisible(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dq_ask_send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dq_ask_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('dq_ask_send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('模型與通知 payload', () {
    test('fromJson：相對音檔補上伺服器網域、摘要規則', () {
      final it = DailyQuestionItem.fromJson({
        'id': 5,
        'question': 'Q',
        'answered': true,
        'answerText': '',
        'answerAudioUrl': '/uploads/a.m4a',
        'cheeredByMe': true,
      });
      expect(it.answerAudioUrl, startsWith('http'));
      expect(it.answerAudioUrl, endsWith('/uploads/a.m4a'));
      expect(it.answerSnippet, '（語音回答）');
      expect(it.cheeredByMe, isTrue);
      expect(DailyQuestionItem.fromJson({'id': 1}).hasAudio, isFalse);
    });

    test('askSuccessMessage 依 scheduled_for 區分', () {
      expect(DailyQuestionApi.askSuccessMessage('today'), '已送出，長輩今天就會看到');
      expect(DailyQuestionApi.askSuccessMessage('later'), '已排入，長輩明天會看到');
    });

    test('ask 本機長度檢查（不連網）', () async {
      final short = await DailyQuestionApi.ask(
          familyId: 1, elderId: 'e', question: '嗨');
      expect(short.ok, isFalse);
      final long = await DailyQuestionApi.ask(
          familyId: 1, elderId: 'e', question: '長' * 81);
      expect(long.ok, isFalse);
    });

    test('parseDailyTap 只認 daily-answer，且不被打卡 parseTap 認領', () {
      const p =
          '{"type":"daily-answer","elderId":"e1","elderName":"","questionId":"9","question":"Q"}';
      final t = CheckinNotification.parseDailyTap(p)!;
      expect(t.elderId, 'e1');
      expect(t.elderName, '長輩');
      expect(t.questionId, 9);
      expect(CheckinNotification.parseTap(p), isNull);
      expect(
          CheckinNotification.parseDailyTap(
              '{"type":"elder-checkin","elderId":"e1"}'),
          isNull);
      expect(CheckinNotification.parseDailyTap('不是 json'), isNull);
    });
  });
}
