// ★ 2026-10-15 對話紀錄：AI 照護秘書開啟時還原本機對話、清除對話紀錄的畫面測試。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/family_ai_copilot_screen.dart';
import 'package:flutter_application_1/screens/family/family_copilot_history.dart';
import 'package:flutter_application_1/screens/family/family_question_draft.dart';
import 'package:flutter_application_1/services/api/daily_question_api.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final elder = Elder(id: 7, elderId: 'e7', name: '王媽媽');
  final key = copilotHistoryKey(9, 'e7');

  String seededHistory() => encodeCopilotHistory([
        {'isUser': true, 'text': '王媽媽今天過得怎麼樣？', 'ts': '2026-10-14T08:00:00.000'},
        {
          'isUser': false,
          'text': '她今天狀況不錯',
          'ts': '2026-10-14T08:00:05.000',
          'statusSummary': {'mood_status': '心情平穩'},
        },
        {
          'isUser': false,
          'text': '幫您擬了題目',
          'ts': '2026-10-14T09:00:00.000',
          'questionPhase': QuestionCardPhase.draft,
          'questionController': TextEditingController(text: '小時候住哪裡'),
        },
      ], elderName: '王媽媽');

  Future<void> pumpScreen(WidgetTester tester, FamilyAiCopilotScreen screen) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: FamilyTheme.buildTheme(_FakeContext(), isDark: false),
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  FamilyAiCopilotScreen screenFor(Elder e) =>
      FamilyAiCopilotScreen(currentElder: e, historyLoader: (id, f) async => []);

  testWidgets('有歷史：顯示歷史、不顯示歡迎詞；未送出的出題草稿變純文字且沒有按鈕', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9, key: seededHistory()});
    await pumpScreen(tester, screenFor(elder));

    expect(find.text('王媽媽今天過得怎麼樣？'), findsOneWidget);
    expect(find.text('她今天狀況不錯'), findsOneWidget);
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsNothing);
    expect(find.text('未送出的出題草稿：小時候住哪裡'), findsOneWidget);
    expect(find.text('交給小嘎問'), findsNothing);
    expect(find.textContaining('查詢的近況'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有歷史：顯示歡迎詞', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9});
    await pumpScreen(tester, screenFor(elder));
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsOneWidget);
  });

  testWidgets('讀不到家屬身分：停用存檔、照常顯示歡迎詞', (tester) async {
    SharedPreferences.setMockInitialValues({key: seededHistory()});
    await pumpScreen(tester, screenFor(elder));
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsOneWidget);
    expect(find.text('她今天狀況不錯'), findsNothing);
  });

  testWidgets('歷史損毀：不當機、顯示歡迎詞', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9, key: 'not json{'});
    await pumpScreen(tester, screenFor(elder));
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新訊息會寫進本機；重開仍在（歡迎詞不存）', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9});
    await pumpScreen(tester, screenFor(elder));
    final state = tester.state(find.byType(FamilyAiCopilotScreen)) as dynamic;
    state.testInjectBotReply({'reply_text': '這是新的回覆'});
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key)!;
    expect(stored, contains('這是新的回覆'));
    expect(stored, isNot(contains('您好！我是您的 AI 照護秘書')));

    await tester.pumpWidget(const SizedBox()); // 卸載，下一次重新 initState
    await pumpScreen(tester, screenFor(elder));
    expect(find.text('這是新的回覆'), findsOneWidget);
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsNothing);
  });

  testWidgets('清除對話紀錄：確認後刪除存檔並回到歡迎詞；取消則保留', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9, key: seededHistory()});
    await pumpScreen(tester, screenFor(elder));
    final prefs = await SharedPreferences.getInstance();

    // 先取消
    await tester.tap(find.byTooltip('清除對話紀錄'));
    await tester.pumpAndSettle();
    expect(find.text('清除對話紀錄？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('她今天狀況不錯'), findsOneWidget);
    expect(prefs.getString(key), isNotNull);

    // 再確認
    await tester.tap(find.byTooltip('清除對話紀錄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('她今天狀況不錯'), findsNothing);
    expect(find.textContaining('您好！我是您的 AI 照護秘書'), findsOneWidget);
    expect(find.text('已清除對話紀錄'), findsOneWidget);
    expect(prefs.getString(key), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清除不動「已看過的長輩回答」清單，舊回答不會再被轉告', (tester) async {
    SharedPreferences.setMockInitialValues({'caregiver_id': 9});
    DailyQuestionItem item() => DailyQuestionItem(
          id: 11,
          question: '最愛吃的菜',
          answered: true,
          answerText: '紅燒肉',
          answeredAt: DateTime.now().toUtc().toIso8601String(),
        );
    await pumpScreen(
      tester,
      FamilyAiCopilotScreen(currentElder: elder, historyLoader: (id, f) async => [item()]),
    );
    expect(find.textContaining('回答了『最愛吃的菜』'), findsOneWidget);

    await tester.tap(find.byTooltip('清除對話紀錄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(copilotSeenAnswersKey('e7')), ['11']);
    expect(prefs.getString(key), isNull);
  });
}
