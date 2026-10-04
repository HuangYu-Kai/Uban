// 長輩端「我的」「聊天」換新設計後的 UI 迴歸測試。
//
// 涵蓋：
//   1. 連勝卡（火焰、連續 N 天、本週 7 天）與任務卡（進度環＋下一件）。
//   2. 整頁 ElderProfileTab（以 debugInitialRemindersForTest 注入假資料，不連網）：
//      連勝卡、任務卡、家人綁定／語音助理／位置分享／導覽／切換身分列都在，
//      GPS 權限提示橫幅出現時整列寬、可換行，在 360x640、textScaler 1.3、淡色／深色
//      都沒有 RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
//   3. 連勝慶祝覆蓋層：360x640、1.3、深色無溢位；reduceMotion 直接顯示最終畫面；
//      「去餵小豬」「好」按鈕高度 ≥60 並呼叫對應回呼。
//   4. 聊天抽出的元件：泡泡、國語／台語分段、輸入列、橡皮筋公式。
//
// 全程只用 pump() 固定次數，不用 pumpAndSettle（有循環動畫）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/chat/chat_widgets.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_profile_tab.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/profile_greet_row.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/profile_location_hint.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/profile_task_card.dart';
import 'package:flutter_application_1/screens/elder_tabs/streak/streak_celebration.dart';
import 'package:flutter_application_1/screens/elder_tabs/streak/streak_service.dart';
import 'package:flutter_application_1/screens/elder_tabs/streak/streak_widgets.dart';
import 'package:flutter_application_1/services/elder_location_service.dart';
import 'package:flutter_application_1/services/location_device_status.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/ui/ui.dart';

List<Map<String, dynamic>> _fakeReminders() => [
      for (var i = 1; i <= 3; i++)
        <String, dynamic>{
          'id': i,
          'title': '測試提醒$i',
          'time_str': '00:0$i',
          'category': i == 1 ? 'medication' : (i == 2 ? 'water' : 'exercise'),
          'repeat_days': '每天',
        },
    ];

Widget _app({
  required Widget child,
  bool dark = false,
  double textScale = 1.0,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Theme(
        data: dark ? buildAppDarkTheme(context) : buildAppTheme(context),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

StreakSnapshot _snap({int days = 6, bool todayDone = false}) {
  final done = <String>{
    for (var i = 1; i <= days; i++)
      StreakService.dayKey(DateTime(2026, 10, 1 - i)),
    if (todayDone) '2026-10-01',
  };
  return StreakService.buildSnapshot(done, DateTime(2026, 10, 1, 9));
}

StreakCelebration _celebration({int from = 6, int carrots = 5}) {
  final done = <String>{
    for (var i = 1; i <= from; i++)
      StreakService.dayKey(DateTime(2026, 10, 1 - i)),
    '2026-10-01',
  };
  final week =
      StreakService.buildSnapshot(done, DateTime(2026, 10, 1, 9)).week;
  return StreakCelebration(
    fromDays: from,
    toDays: from + 1,
    weekAfter: week,
    earnedCarrots: carrots,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('連勝卡', () {
    testWidgets('顯示連續天數與一～日、本週完成數', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(child: StreakCard(snapshot: _snap())));
      await tester.pump();

      expect(find.text('6 天', findRichText: true), findsOneWidget);
      expect(find.text('連續把每天的事都做完'), findsOneWidget);
      for (final d in StreakService.weekLabels) {
        expect(find.text(d), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      testWidgets('360x640、1.3 倍、${dark ? "深色" : "淡色"}、三位數天數無溢位',
          (tester) async {
        _phone(tester, const Size(360, 640));
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          child: SingleChildScrollView(
              child: StreakCard(snapshot: _snap(days: 365, todayDone: true))),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('任務卡', () {
    testWidgets('進度環 1/3、下一件、打卡鈕呼叫 onCheckIn', (tester) async {
      _phone(tester, const Size(412, 915));
      Map<String, dynamic>? checked;
      await tester.pumpWidget(_app(
        child: ProfileTaskCard(
          reminders: _fakeReminders(),
          completedIds: const {1},
          isLoading: false,
          hasLoadError: false,
          onCheckIn: (r) => checked = r,
          onOpenSheet: () {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('1/3', findRichText: true), findsOneWidget);
      expect(find.text('測試提醒2'), findsOneWidget);
      await tester.tap(find.text('打卡'));
      expect(checked?['id'], 2);
    });

    testWidgets('讀取失敗與沒有提醒是兩種畫面', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(
        child: ProfileTaskCard(
          reminders: const [],
          completedIds: const {},
          isLoading: false,
          hasLoadError: true,
          onCheckIn: (_) {},
          onOpenSheet: () {},
        ),
      ));
      expect(find.text('提醒暫時讀不到，請確認網路連線'), findsOneWidget);

      await tester.pumpWidget(_app(
        child: ProfileTaskCard(
          reminders: const [],
          completedIds: const {},
          isLoading: false,
          hasLoadError: false,
          onCheckIn: (_) {},
          onOpenSheet: () {},
        ),
      ));
      expect(find.text('今天沒有要做的事'), findsOneWidget);
    });
  });

  group('頁首問候', () {
    test('年齡地區只在有資料時組出', () {
      expect(
          ProfileGreetRow.buildDetail(
              {'age': 76, 'residence_city': '臺北市', 'residence_district': '萬華區'}),
          '76 歲・臺北市萬華區');
      expect(ProfileGreetRow.buildDetail({'age': '80'}), '80 歲');
      expect(ProfileGreetRow.buildDetail({'residence_city': '高雄市'}), '高雄市');
      expect(ProfileGreetRow.buildDetail({}), isNull);
      expect(ProfileGreetRow.buildDetail(null), isNull);
    });

    testWidgets('超長名字可收縮，不溢位', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(
        textScale: 1.3,
        child: const ProfileGreetRow(
          name: '這是一個非常非常非常非常非常長的長輩稱呼名字',
          detail: '76 歲・臺北市萬華區非常長的地區名稱非常長的地區名稱',
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('整頁 ElderProfileTab', () {
    Widget page() => ElderProfileTab(
          userId: 1,
          userName: '測試長輩',
          tasksKey: GlobalKey(),
          familyPairingKey: GlobalKey(),
          aiAssistantKey: GlobalKey(),
          debugInitialRemindersForTest: _fakeReminders(),
          debugInitialCompletedIdsForTest: const {1},
        );

    tearDown(() => ElderLocationService.instance.deviceStatus.value = null);

    testWidgets('版面元素齊全（連勝卡、任務卡、各 action 列）', (tester) async {
      _phone(tester, const Size(412, 1400));
      await tester.pumpWidget(_app(child: page()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('測試長輩'), findsOneWidget);
      expect(find.byType(StreakCard), findsOneWidget);
      expect(find.byType(ProfileTaskCard), findsOneWidget);
      expect(find.byType(UbanProgressRing), findsOneWidget);
      expect(find.text('家人綁定'), findsOneWidget);
      expect(find.text('語音助理'), findsOneWidget);
      expect(find.text('分享我的位置'), findsOneWidget);
      expect(find.byType(UbanSwitch), findsOneWidget);
      expect(find.text('重新觀看新手導覽'), findsOneWidget);
      expect(find.text('切換身分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('點任務卡開抽屜（重用 ElderTaskSheetBody）', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(child: page()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.byType(UbanProgressRing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('今天要做的事'), findsOneWidget);
      expect(find.text('現在要做（2）'), findsOneWidget);
      expect(find.text('已完成（1）'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final status in [
        null,
        LocationDeviceStatus.serviceDisabled,
        LocationDeviceStatus.foregroundOnly,
        LocationDeviceStatus.permissionDenied,
      ]) {
        testWidgets(
            '360x640、1.3 倍、${dark ? "深色" : "淡色"}、定位狀態 $status 無溢位',
            (tester) async {
          _phone(tester, const Size(360, 640));
          ElderLocationService.instance.deviceStatus.value = status;
          await tester.pumpWidget(_app(dark: dark, textScale: 1.3, child: page()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));

          if (status != null) {
            expect(find.byType(LocationStatusHint), findsOneWidget,
                reason: '手機沒開定位時開關下方要出現提示橫幅');
          } else {
            expect(find.byType(LocationStatusHint), findsNothing);
          }
          expect(tester.takeException(), isNull);

          // 往下捲到底再確認一次（底部列也不溢位）。
          await tester.drag(find.byType(SingleChildScrollView).first,
              const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('連勝慶祝覆蓋層', () {
    testWidgets('顯示天數、胡蘿蔔數與兩顆按鈕；按鈕高度 ≥60 並呼叫回呼', (tester) async {
      _phone(tester, const Size(412, 915));
      var closed = 0;
      var fed = 0;
      await tester.pumpWidget(_app(
        child: StreakCelebrationOverlay(
          data: _celebration(),
          onClose: () => closed++,
          onFeedPig: () => fed++,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5)); // 跑完全部動畫與彩紙

      expect(find.text('連續 7 天全部完成！'), findsOneWidget);
      expect(find.text('今天打卡賺到 5 根胡蘿蔔'), findsOneWidget);
      expect(tester.getSize(find.text('去餵小豬').hitTestable()).height, greaterThan(0));
      final feedBtn = find.ancestor(
          of: find.text('去餵小豬'), matching: find.byType(PressableScale));
      final okBtn = find.ancestor(
          of: find.text('好'), matching: find.byType(PressableScale));
      expect(tester.getSize(feedBtn.first).height, greaterThanOrEqualTo(60));
      expect(tester.getSize(okBtn.first).height, greaterThanOrEqualTo(60));

      await tester.tap(find.text('去餵小豬'));
      await tester.tap(find.text('好'));
      expect(fed, 1);
      expect(closed, 1);
    });

    testWidgets('reduceMotion：不放動畫，第一幀就是最終畫面（獎勵卡已顯示）', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(
        disableAnimations: true,
        child: StreakCelebrationOverlay(
          data: _celebration(),
          onClose: () {},
          onFeedPig: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('今天打卡賺到 5 根胡蘿蔔'), findsOneWidget);
      final opacity = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity < 1);
      expect(opacity, isEmpty);
    });

    for (final dark in [false, true]) {
      testWidgets('360x640、1.3 倍、${dark ? "深色" : "淡色"}無溢位', (tester) async {
        _phone(tester, const Size(360, 640));
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          child: StreakCelebrationOverlay(
            data: _celebration(from: 99, carrots: 5),
            onClose: () {},
            onFeedPig: () {},
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('showStreakCelebration：「好」關閉、「去餵小豬」關閉並呼叫回呼', (tester) async {
      _phone(tester, const Size(412, 915));
      var fed = 0;
      await tester.pumpWidget(_app(
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showStreakCelebration(context, _celebration(),
                  onFeedPig: () => fed++),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(StreakCelebrationOverlay), findsOneWidget);

      await tester.tap(find.text('去餵小豬'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StreakCelebrationOverlay), findsNothing);
      expect(fed, 1);
    });
  });

  group('聊天抽出的元件', () {
    testWidgets('國語／台語分段：點選回呼 index，按鈕高 ≥48', (tester) async {
      _phone(tester, const Size(360, 640));
      var idx = 0;
      await tester.pumpWidget(_app(
        textScale: 1.3,
        child: StatefulBuilder(
          builder: (context, setState) => ChatLangSeg(
            labels: const ['國語', '台語'],
            index: idx,
            onChanged: (i) => setState(() => idx = i),
          ),
        ),
      ));
      await tester.tap(find.text('台語'));
      await tester.pump();
      expect(idx, 1);
      expect(tester.getSize(find.byType(ChatLangSeg)).height,
          greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      testWidgets('泡泡＋再聽一次＋輸入列（語音／文字）360x640、1.3、${dark ? "深色" : "淡色"}無溢位',
          (tester) async {
        _phone(tester, const Size(360, 640));
        var replay = 0;
        var holdStart = 0;
        var holdEnd = 0;
        var voiceMode = true;
        final ctrl = TextEditingController();
        addTearDown(ctrl.dispose);
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const ChatBubbleFrame(
                          isUser: true,
                          child: Text('睡得不錯，就是半夜起來一次，然後又睡著了，早上很精神')),
                      const SizedBox(height: 12),
                      ChatBubbleFrame(
                        isUser: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('那很正常喔，年紀大了比較淺眠。白天記得多走動、曬點太陽。'),
                            ChatReplayButton(
                              isPlaying: false,
                              languageLabel: '台語',
                              onTap: () => replay++,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const ChatBubbleFrame(
                        isUser: false,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ChatThinkingDots(),
                            SizedBox(width: 10),
                            Flexible(child: Text('小嘎想想…')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ChatInputBar(
                  voiceMode: voiceMode,
                  isListening: false,
                  onToggleMode: () => setState(() => voiceMode = !voiceMode),
                  onHoldStart: () => holdStart++,
                  onHoldEnd: () => holdEnd++,
                  controller: ctrl,
                  onSend: () {},
                  bottomPadding: 16,
                ),
              ],
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('再聽一次'));
        expect(replay, 1);
        expect(find.text('按住　說話'), findsOneWidget);

        // 長按開始／結束仍會呼叫原函式。
        final g = await tester.startGesture(tester.getCenter(find.text('按住　說話')));
        await tester.pump(const Duration(seconds: 1));
        await g.up();
        await tester.pump();
        expect(holdStart, 1);
        expect(holdEnd, 1);

        // 切到文字輸入。
        await tester.tap(find.byIcon(Icons.keyboard_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byIcon(Icons.send_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test('橡皮筋公式與 ui.js 一致', () {
      // MAX_PULL 26、RESIST 90：over=0 → 0；over=90 → 13；over→∞ 逼近 26。
      expect(ChatRubberBand.magnitude(0), 0);
      expect(ChatRubberBand.magnitude(90), closeTo(13, 1e-9));
      expect(ChatRubberBand.magnitude(100000), lessThan(26));
      expect(ChatRubberBand.magnitude(100000), greaterThan(25.9));

      // 頂端往下拉：第 0 顆位移 = pull*0.3、最後一顆 = pull*1.25（離邊越遠位移越多）。
      expect(
          ChatRubberBand.offsetFor(index: 0, count: 5, pull: 10, edge: -1),
          closeTo(3, 1e-9));
      expect(
          ChatRubberBand.offsetFor(index: 4, count: 5, pull: 10, edge: -1),
          closeTo(12.5, 1e-9));
      // 底端往上拉（pull 為負）：最後一顆 = pull*0.3、第 0 顆 = pull*1.25。
      expect(
          ChatRubberBand.offsetFor(index: 4, count: 5, pull: -10, edge: 1),
          closeTo(-3, 1e-9));
      expect(
          ChatRubberBand.offsetFor(index: 0, count: 5, pull: -10, edge: 1),
          closeTo(-12.5, 1e-9));
      // 沒有拉伸時一律 0。
      expect(ChatRubberBand.offsetFor(index: 2, count: 5, pull: 0, edge: -1), 0);
    });

    test('只有超出邊界才有拉伸，正常捲動為 (0, 0)', () {
      final mid = ChatRubberBand.fromMetrics(
          pixels: 120, minScrollExtent: 0, maxScrollExtent: 400);
      expect(mid.pull, 0);
      expect(mid.edge, 0);
      final atTop = ChatRubberBand.fromMetrics(
          pixels: 0, minScrollExtent: 0, maxScrollExtent: 400);
      expect(atTop.edge, 0, reason: '剛好在邊界上、沒有超出');

      final top = ChatRubberBand.fromMetrics(
          pixels: -30, minScrollExtent: 0, maxScrollExtent: 400);
      expect(top.edge, -1);
      expect(top.pull, greaterThan(0));

      final bottom = ChatRubberBand.fromMetrics(
          pixels: 430, minScrollExtent: 0, maxScrollExtent: 400);
      expect(bottom.edge, 1);
      expect(bottom.pull, lessThan(0));
    });

    testWidgets('ChatPullItem：pull=0 不加 Transform；有拉伸才位移', (tester) async {
      _phone(tester, const Size(360, 640));
      final n = ValueNotifier<({double pull, int edge})>((pull: 0.0, edge: 0));
      addTearDown(n.dispose);
      await tester.pumpWidget(_app(
        child: ChatPullItem(
            index: 4, count: 5, pull: n, child: const Text('bubble')),
      ));
      final base = tester.getTopLeft(find.text('bubble'));
      n.value = (pull: 10.0, edge: -1);
      await tester.pump();
      expect(tester.getTopLeft(find.text('bubble')).dy - base.dy,
          closeTo(12.5, 1e-6));
      n.value = (pull: 0.0, edge: 0);
      await tester.pump();
      expect(tester.getTopLeft(find.text('bubble')), base);
    });
  });
}
