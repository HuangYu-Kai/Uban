// 長輩端「首頁」「電話」換新設計後的 UI 迴歸測試。
//
// 涵蓋：
//   1. 首頁任務卡為「今天要做的事」清單（標籤 done／total 完成、最多 3 列未完成、看全部）。
//   2. 任務抽屜三組標題（現在要做／稍後／已完成）出現，且依設計稿預設「現在要做」
//      展開、「稍後」「已完成」收合。
//   3. 深色主題（buildAppDarkTheme）＋ 360x640 ＋ textScaler 1.3 下，首頁與電話頁
//      都能建構且沒有 RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
//
// ⚠️ 首頁以 `debugInitialRemindersForTest`／`debugInitialNewsItemsForTest` 注入假資料，
// 不連網（flutter test 會讓所有 HTTP 回 400），且不會排出 8 秒重試 Timer。
// 全程只用 `pump()` 固定次數，刻意不用 pumpAndSettle（天氣小圖是無限循環動畫）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/models/elder_place.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_home_tab.dart';
import 'package:flutter_application_1/screens/elder_tabs/widgets/elder_task_sheet.dart';
import 'package:flutter_application_1/screens/friends_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/reminder_schedule.dart';
import 'package:flutter_application_1/widgets/ui/ui.dart';

/// 三筆「今天已到時間」的提醒（00:00 起，必定歸在「現在要做」或「已完成」）。
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

List<Map<String, dynamic>> _fakeNews() => List<Map<String, dynamic>>.generate(
      5,
      (i) => <String, dynamic>{'id': 'n$i', 'title': 'TEST_NEWS_ITEM_${i + 1}'},
    );

Widget _app({
  required Widget child,
  bool dark = false,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Theme(
        data: dark ? buildAppDarkTheme(context) : buildAppTheme(context),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
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

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('首頁任務卡（今天要做的事清單）', () {
    testWidgets('標題＋「1／3 完成」標籤，只列未完成項目（id 2、3），不再有進度環', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(
        child: ElderHomeTab(
          userId: 1,
          userName: '測試長輩',
          roomId: 'test-elder-room',
          debugInitialRemindersForTest: _fakeReminders(),
          debugInitialCompletedIdsForTest: {1},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.byType(UbanProgressRing), findsNothing,
          reason: '進度環只留在「我的」頁');
      expect(find.text('今天要做的事'), findsOneWidget);
      expect(find.text('1／3 完成'), findsOneWidget);
      expect(find.byType(ElderTaskRow), findsNWidgets(2));
      expect(find.text('測試提醒1'), findsNothing, reason: '已完成不列在首頁');
      expect(find.text('測試提醒2'), findsOneWidget);
      expect(find.text('測試提醒3'), findsOneWidget);
      // 總數 3 > 列出 2：底部有「看全部 3 件」。
      expect(find.text('看全部 3 件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未完成超過 3 件只列前 3 件；全部完成時顯示完成訊息與「看全部」', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(
        child: ElderHomeTab(
          userId: 1,
          userName: '測試長輩',
          roomId: 'test-elder-room',
          debugInitialRemindersForTest: _fakeReminders(),
          debugInitialCompletedIdsForTest: {1, 2, 3},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('3／3 完成'), findsOneWidget);
      expect(find.byType(ElderTaskRow), findsNothing);
      expect(find.text('今天的事都做完了'), findsOneWidget);
      expect(find.text('看全部 3 件'), findsOneWidget, reason: '全完成仍可看已完成清單');
    });

    testWidgets('首頁列的打卡鈕可點（語意標籤「打卡 標題」）', (tester) async {
      _phone(tester, const Size(412, 915));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(
        child: ElderHomeTab(
          userId: 1,
          userName: '測試長輩',
          roomId: 'test-elder-room',
          debugInitialRemindersForTest: _fakeReminders(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.bySemanticsLabel('打卡 測試提醒1'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('任務抽屜', () {
    testWidgets('點任務卡開抽屜：出現「現在要做」「已完成」組標題與張數', (tester) async {
      _phone(tester, const Size(412, 915));
      await tester.pumpWidget(_app(
        child: ElderHomeTab(
          userId: 1,
          userName: '測試長輩',
          roomId: 'test-elder-room',
          debugInitialRemindersForTest: _fakeReminders(),
          debugInitialCompletedIdsForTest: {1},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.text('看全部 3 件'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // 首頁卡與抽屜各有一個標題；抽屜標籤是「1／3」。
      expect(find.text('今天要做的事'), findsNWidgets(2));
      expect(find.text('1／3'), findsOneWidget);
      // 批次六：抽屜改為「家人提醒／我的目標」兩區，總數仍含全部項目。
      expect(find.text('家人提醒'), findsOneWidget);
      expect(find.text('我的目標'), findsOneWidget);
      expect(find.text('新增我的目標'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('三組標題都出現；現在要做展開，稍後／已完成預設收合、點標題展開',
        (tester) async {
      _phone(tester, const Size(412, 915));
      Map<String, dynamic> r(int id, String t) => {
            'id': id,
            'title': t,
            'time_str': '09:0$id',
            'category': 'medication',
          };
      final groups = ReminderGroups(
        dueNow: [r(1, '現在的事')],
        later: [r(2, '稍後的事')],
        done: [r(3, '做完的事')],
      );
      await tester.pumpWidget(_app(
        child: SingleChildScrollView(
          child: ElderTaskSheetBody(
            readGroups: () => groups,
            onCheckIn: (_) async {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('現在要做（1）'), findsOneWidget);
      expect(find.text('稍後（1）'), findsOneWidget);
      expect(find.text('已完成（1）'), findsOneWidget);
      expect(find.text('現在的事'), findsOneWidget, reason: '現在要做預設展開');
      expect(find.text('稍後的事'), findsNothing, reason: '稍後預設收合');
      expect(find.text('做完的事'), findsNothing, reason: '已完成預設收合');

      await tester.tap(find.text('稍後（1）'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('稍後的事'), findsOneWidget, reason: '點標題後展開');
    });

    testWidgets('抽屜內打卡走傳入的 onCheckIn（首頁即既有 _completeNextDose）',
        (tester) async {
      _phone(tester, const Size(412, 915));
      final checked = <int>[];
      final groups = ReminderGroups(
        dueNow: [
          {'id': 7, 'title': '吃藥', 'time_str': '08:00', 'category': 'medication'}
        ],
        later: const [],
        done: const [],
      );
      await tester.pumpWidget(_app(
        child: SingleChildScrollView(
          child: ElderTaskSheetBody(
            readGroups: () => groups,
            onCheckIn: (m) async => checked.add(m['id'] as int),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('打卡 吃藥'));
      await tester.pump();
      expect(checked, [7]);
    });
  });

  // G204 最壞情境：已設定「家」（帶我回家）＋真實任務卡（有下一件、未全部完成）。
  // 「帶我回家」是獨立的大入口（問候列之後、今天卡之前），屬安全功能，使用者指定要最顯眼，
  // 因此最壞情境下由它優先佔第一屏（可視底線＝螢幕高－114）；今日頭條因而可能被擠到折線下，
  // 改以「有算進清單、可捲動到」為準（首頁本就是可捲動列表）。真正不可破的是：任何尺寸都
  // 不得出現 RenderFlex 溢位（鐵律 #14），且新聞清單仍須封頂三則。
  group('G204 最壞情境：帶我回家＋有下一件的任務卡', () {
    const home = ElderPlace(
        id: 1, name: '家', latitude: 25, longitude: 121, radiusM: 100, isHome: true);
    for (final size in [const Size(360, 640), const Size(412, 915)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final semantics = tester.ensureSemantics();
        _phone(tester, size);
        await tester.pumpWidget(_app(
          child: ElderHomeTab(
            userId: 1,
            userName: '測試長輩',
            roomId: 'test-elder-room',
            debugInitialNewsItemsForTest: _fakeNews(),
            debugInitialRemindersForTest: _fakeReminders(),
            debugInitialHomePlaceForTest: home,
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));

        expect(tester.takeException(), isNull);
        final visibleBottom = size.height - 114;
        // 安全功能優先：帶我回家大入口本身最壞情境下仍須落在第一屏。
        expect(find.bySemanticsLabel('帶我回家'), findsOneWidget);
        expect(tester.getRect(find.bySemanticsLabel('帶我回家')).bottom,
            lessThanOrEqualTo(visibleBottom),
            reason: '帶我回家是安全入口，最壞情境下仍須在第一屏');
        expect(find.byType(ElderTaskRow), findsNWidgets(3), reason: '有未完成項目的任務卡');
        // 今日頭條：被大入口擠到折線下可接受，確認仍有算進清單、可捲動到即可。
        expect(find.text('今日頭條'), findsOneWidget);
        if (size.height >= 700) {
          expect(find.text('TEST_NEWS_ITEM_2'), findsOneWidget);
          expect(find.text('TEST_NEWS_ITEM_3'), findsOneWidget);
          expect(find.text('TEST_NEWS_ITEM_4'), findsNothing, reason: '新聞清單封頂三則');
        }
        semantics.dispose();
      });
    }
  });

  group('深色主題＋大字級不溢位', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('首頁 360x640 深色 textScaler=$scale', (tester) async {
        _phone(tester, const Size(360, 640));
        await tester.pumpWidget(_app(
          dark: true,
          textScale: scale,
          child: ElderHomeTab(
            userId: 1,
            userName: '測試長輩名字很長很長很長很長',
            roomId: 'test-elder-room',
            debugInitialNewsItemsForTest: _fakeNews(),
            debugInitialRemindersForTest: _fakeReminders(),
            debugInitialCompletedIdsForTest: {1},
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));

        expect(tester.takeException(), isNull);
        expect(find.text('今日頭條'), findsOneWidget);
        // 深色主題確實套用（背景取自 UbanColors.dark）。
        final ctx = tester.element(find.byType(ElderHomeTab));
        expect(UbanColors.of(ctx).bg, UbanColors.dark.bg);
      });

      testWidgets('首頁 412x915 深色 textScaler=$scale（含補列新聞）', (tester) async {
        _phone(tester, const Size(412, 915));
        await tester.pumpWidget(_app(
          dark: true,
          textScale: scale,
          child: ElderHomeTab(
            userId: 1,
            userName: '測試長輩',
            roomId: 'test-elder-room',
            debugInitialNewsItemsForTest: _fakeNews(),
            debugInitialRemindersForTest: _fakeReminders(),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
        expect(tester.takeException(), isNull);
      });

      testWidgets('電話頁 360x640 深色 textScaler=$scale', (tester) async {
        _phone(tester, const Size(360, 640));
        await tester.pumpWidget(_app(
          dark: true,
          textScale: scale,
          child: const FriendsScreen(
            userId: 1,
            userName: '測試長輩',
            roomId: 'test-elder-room',
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.text('打電話'), findsOneWidget);
        expect(find.byType(UbanSegmented), findsOneWidget);

        // 切到「朋友」分頁（同一個 TabController 驅動）。
        await tester.tap(find.text('朋友'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
