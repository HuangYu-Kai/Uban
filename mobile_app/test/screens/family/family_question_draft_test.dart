// ★ 2026-10-07 交接 A2：出題草稿、轉告回答純函式，以及秘書的出題卡／轉告訊息。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/family_ai_copilot_screen.dart';
import 'package:flutter_application_1/screens/family/family_question_draft.dart';
import 'package:flutter_application_1/services/api/daily_question_api.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

DailyQuestionItem _item(int id, {bool answered = true, String text = '紅燒肉', String? audio, DateTime? at}) =>
    DailyQuestionItem(
      id: id,
      question: '最愛吃的菜 $id',
      answered: answered,
      answerText: text,
      answerAudioUrl: audio,
      answeredAt: (at ?? DateTime.now().toUtc()).toIso8601String(),
    );

void main() {
  group('QuestionDraft.tryParse', () {
    test('缺席、null、空白回 null', () {
      expect(QuestionDraft.tryParse(null), isNull);
      expect(QuestionDraft.tryParse({'text': '  '}), isNull);
      expect(QuestionDraft.tryParse('x'), isNull);
    });
    test('有文字成立（去頭尾空白）', () {
      expect(QuestionDraft.tryParse({'text': ' 小時候住哪 '})!.text, '小時候住哪');
    });
  });

  test('canSendQuestion：空白、送出中不可送', () {
    expect(canSendQuestion(text: ' ', sending: false), isFalse);
    expect(canSendQuestion(text: '小時候住哪', sending: false), isTrue);
    expect(canSendQuestion(text: '小時候住哪', sending: true), isFalse);
  });

  group('selectUnseenAnswers', () {
    final now = DateTime.now();
    test('只留已回答、7 天內、沒看過的；舊→新排序', () {
      final items = [
        _item(5, at: now.toUtc()),
        _item(4, answered: false),
        _item(3, at: now.subtract(const Duration(days: 8)).toUtc()),
        _item(2, at: now.subtract(const Duration(days: 1)).toUtc()),
        _item(1, at: now.subtract(const Duration(days: 2)).toUtc()),
      ];
      final r = selectUnseenAnswers(items, {'2'}, now: now);
      expect(r.map((e) => e.id).toList(), [1, 5]);
    });
  });

  test('answerRelayText 格式', () {
    expect(answerRelayText('媽媽', _item(1)), '媽媽回答了『最愛吃的菜 1』：紅燒肉');
  });

  Future<void> pumpScreen(WidgetTester tester, FamilyAiCopilotScreen screen) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: FamilyTheme.buildTheme(_FakeContext(), isDark: false),
      builder: (ctx, w) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: w!,
      ),
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  final elder = Elder(id: 7, elderId: 'e7', name: '王媽媽');

  testWidgets('打開秘書：轉告未看過的回答並記入本機；再開不重複', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9});
    Future<List<DailyQuestionItem>?> loader(String e, int f) async =>
        [_item(11, audio: 'http://x/a.mp3')];
    await pumpScreen(tester, FamilyAiCopilotScreen(currentElder: elder, historyLoader: loader));
    expect(find.textContaining('回答了『最愛吃的菜 11』：紅燒肉'), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_audio_btn')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(copilotSeenAnswersKey('e7')), ['11']);

    await tester.pumpWidget(const SizedBox()); // 卸載舊畫面，讓下一次重新 initState
    await pumpScreen(tester, FamilyAiCopilotScreen(currentElder: elder, historyLoader: loader));
    expect(find.textContaining('回答了『最愛吃的菜 11』'), findsNothing);
  });

  testWidgets('出題卡：失敗顯示真實原因、成功顯示小嘎會在…下次聊天時問', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9});
    var calls = 0;
    await pumpScreen(
      tester,
      FamilyAiCopilotScreen(
        currentElder: elder,
        historyLoader: (e, f) async => [],
        asker: ({required String question, String? category}) async {
          calls++;
          return calls == 1
              ? const DailyAskResult(false, '待答的題目太多了')
              : const DailyAskResult(true, 'ok', scheduledFor: 'later');
        },
      ),
    );
    final state = tester.state(find.byType(FamilyAiCopilotScreen)) as dynamic;
    state.testInjectBotReply({
      'reply_text': '好的，幫您擬了題目',
      'intent': 'ASK_DAILY_QUESTION',
      'question_draft': {'text': '小時候住哪裡'},
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('交給小嘎問'), 300,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('交給小嘎問'));
    await tester.pumpAndSettle();
    expect(find.text('待答的題目太多了'), findsOneWidget);
    await tester.tap(find.text('交給小嘎問'));
    await tester.pumpAndSettle();
    expect(find.text('小嘎會在${elder.displayName}下次聊天時問'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
