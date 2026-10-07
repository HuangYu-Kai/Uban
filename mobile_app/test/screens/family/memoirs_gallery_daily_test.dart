// ★ 2026-10-07 每日一問：人生故事畫廊合併後端每日一問、委託提問改走後端 /ask。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';
import 'package:flutter_application_1/services/api/daily_question_api.dart';
import 'package:flutter_application_1/services/memoir_service.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({'caregiver_id': 7}));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('每日一問已回答題目與本機故事合併，未回答的不顯示', (tester) async {
    await phone(tester);
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_local_1',
      elderId: 'e_dq',
      title: '本機的老故事',
      tag: '經典回憶',
      preview: 'p',
      fullStory: 'f',
      promptQuestion: 'q',
      recordedDate: DateTime(2020, 1, 1),
    ));
    await tester.pumpWidget(MaterialApp(
      home: MemoirsGalleryScreen(
        elderId: 'e_dq',
        elderName: '王阿公',
        dailyLoader: (_, fid) async => [
          const DailyQuestionItem(
              id: 3, question: '最難忘的旅行？', answered: true, answerText: '去過日月潭'),
          const DailyQuestionItem(id: 4, question: '還沒回答的題目', answered: false),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本機的老故事'), findsOneWidget);
    expect(find.text('最難忘的旅行？'), findsOneWidget);
    expect(find.text('還沒回答的題目'), findsNothing);
    expect(find.text('珍藏 2 篇口述回憶・世代傳承'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('委託提問改走後端：成功顯示「已送出」，不再寫本機委託', (tester) async {
    await phone(tester);
    String? asked;
    await tester.pumpWidget(MaterialApp(
      home: MemoirsGalleryScreen(
        elderId: 'e_dq2',
        elderName: '王阿公',
        dailyLoader: (_, __) async => [],
        dailyAsker: ({required question, category}) async {
          asked = question;
          return DailyAskResult(true, DailyQuestionApi.askSuccessMessage('today'),
              scheduledFor: 'today');
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('委託提問'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('您小時候最喜歡吃的一道菜').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('託付給小豬'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('託付給小豬'));
    await tester.pumpAndSettle();
    expect(asked, contains('最喜歡吃的一道菜'));
    expect(find.text('已送出，長輩今天就會看到'), findsOneWidget);
    expect(await MemoirService.instance.getPendingPrompts('e_dq2'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
