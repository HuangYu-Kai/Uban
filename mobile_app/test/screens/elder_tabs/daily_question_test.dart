// ★ 2026-10-07 每日一問（長輩端）：聊天分頁小紅點、回答面板（送出啟用／送出中／失敗）、
// 360x640 ＋ textScale 1.3 無 RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
//
// 全程只用 pump() 固定次數；平台物件（語音辨識、錄音、播放）在面板內延後建立，
// 測試不觸發按住說話，所以不需要平台通道。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/daily_question_answer_sheet.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_layout.dart';
import 'package:flutter_application_1/services/api/elder_daily_question_api.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/ui/ui.dart';

const _bank = DailyQuestion(id: 1, question: '您小時候最喜歡吃什麼？');
const _family = DailyQuestion(
    id: 2, question: '您年輕時住在哪裡呢？', source: 'family', askedByName: '璿OwO');
const _answered = DailyQuestion(
  id: 3,
  question: '您小時候最喜歡吃什麼？',
  answered: true,
  answerText: '我最愛吃媽媽做的蛋炒飯',
);

Widget _app(Widget child, {double textScale = 1.0}) => MaterialApp(
      home: Builder(
        builder: (context) => Theme(
          data: buildAppTheme(context),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ★ 2026-10-07 每日一問改留聊天：首頁不再有卡片，改在底部導覽「聊天」分頁顯示小紅點
  //（ElderHomeScreen 無法在 widget test pump，故以 buildElderNavItems＋UbanGlassNavBar 驗證，
  // 外殼的 _buildFloatingNavBar 就是這樣組出來的）。
  group('聊天分頁小紅點', () {
    Widget navApp(bool hasUnanswered) => MaterialApp(
          theme: ThemeData(extensions: [UbanColors.light]),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: UbanGlassNavBar(
                items: buildElderNavItems(const [], hasUnanswered),
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
          ),
        );

    testWidgets('hasUnanswered=true：聊天顯示紅點與無障礙標籤，360x640 x1.3 無溢位',
        (tester) async {
      _phone(tester, const Size(360, 640));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(navApp(true));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav_badge_dot')), findsOneWidget);
      expect(find.bySemanticsLabel('聊天，有一個新問題'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('hasUnanswered=false：沒有紅點', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(navApp(false));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav_badge_dot')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('hasUnanswered 預設為 false', () {
      expect(ElderDailyQuestionApi.hasUnanswered.value, isFalse);
    });
  });

  group('DailyQuestionAnswerSheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      DailyAnswerSender? sender,
      DailyQuestion q = _family,
      double scale = 1.0,
    }) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(
        DailyQuestionAnswerSheet(question: q, elderId: 'e1', sender: sender),
        textScale: scale,
      ));
      await tester.pump();
    }

    bool submitEnabled(WidgetTester tester) {
      final w = tester.widget(find.byKey(const ValueKey("daily_submit"))) as dynamic;
      return w.onPressed != null;
    }

    testWidgets('一開始送出停用；打字後啟用；清空後再停用', (tester) async {
      await pumpSheet(tester);
      expect(submitEnabled(tester), false);
      await tester.enterText(
          find.byKey(const ValueKey('daily_answer_text')), '蛋炒飯');
      await tester.pump();
      expect(submitEnabled(tester), true);
      await tester.enterText(
          find.byKey(const ValueKey('daily_answer_text')), '  ');
      await tester.pump();
      expect(submitEnabled(tester), false);
    });

    testWidgets('改一下：已回答時預填原本的答案且可直接送出', (tester) async {
      await pumpSheet(tester, q: _answered);
      expect(find.text('我最愛吃媽媽做的蛋炒飯'), findsOneWidget);
      expect(submitEnabled(tester), true);
    });

    testWidgets('送出中停用按鈕與輸入；成功後關閉並回傳 true', (tester) async {
      final done = Completer<DailyAnswerResult>();
      String? sentText;
      bool? result;
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDailyQuestionAnswerSheet(
              context,
              question: _bank,
              elderId: 'e1',
              sender: ({required questionId, text, audioPath}) {
                sentText = text;
                return done.future;
              },
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const ValueKey('daily_answer_text')), '蛋炒飯');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('daily_submit')));
      await tester.pump();
      expect(submitEnabled(tester), false); // 送出中
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('daily_answer_text')))
              .enabled,
          false);
      done.complete(const DailyAnswerResult(true, 'ok'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(sentText, '蛋炒飯');
      expect(result, true);
    });

    testWidgets('送出失敗：顯示連不上伺服器訊息並恢復可再送', (tester) async {
      await pumpSheet(
        tester,
        sender: ({required questionId, text, audioPath}) async =>
            const DailyAnswerResult(false, 'x'),
      );
      await tester.enterText(
          find.byKey(const ValueKey('daily_answer_text')), '蛋炒飯');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('daily_submit')));
      await tester.pump();
      await tester.pump();
      expect(find.text('目前連不上伺服器，請稍後再試一次'), findsOneWidget);
      expect(submitEnabled(tester), true);
    });

    testWidgets('360x640 textScale 1.3 無溢位', (tester) async {
      await pumpSheet(tester, scale: 1.3);
      await tester.enterText(
          find.byKey(const ValueKey('daily_answer_text')), '這是一段比較長的回答' * 8);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
