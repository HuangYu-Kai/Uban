// 長輩端子畫面換新設計後的 UI 迴歸測試：新聞收聽、新聞文章、農民曆、權限引導。
//
// 涵蓋（皆在 360x640、textScaler 1.3、淺色／深色下不得有 RenderFlex 溢位，
// CLAUDE.md §3.1 第 14 條）：
//   1. 新聞收聽主畫面：prev_button／play_pause_button／next_button 三個 ValueKey 仍在、
//      「在此處往上滑查看更多新聞」與向上箭頭仍在。
//   2. 新聞子元件：分類列、卡片列、字幕（卡拉 OK）、音波、重點整理對話框。
//   3. 新聞文章頁：「聆聽新聞」呼叫 onListenNews 並返回。
//   4. 農民曆：前一日／後一日／回今天／日曆鈕、「唸給我聽」切換、宜忌點擊解說。
//   5. 權限引導：「前往設定」「稍後再說」「我已完成設定」三顆鈕都在、高度 ≥60。
//
// 全程只用 pump() 固定次數，不用 pumpAndSettle（有循環動畫與逾時的網路請求）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/almanac/farmer_almanac_screen.dart';
import 'package:flutter_application_1/screens/emergency_permission_guide_screen.dart';
import 'package:flutter_application_1/screens/news_listen_player/news_article_screen.dart';
import 'package:flutter_application_1/screens/news_listen_player/news_listen_player_screen.dart';
import 'package:flutter_application_1/screens/news_listen_player/widgets/news_card_list.dart';
import 'package:flutter_application_1/screens/news_listen_player/widgets/news_category_selector.dart';
import 'package:flutter_application_1/screens/news_listen_player/widgets/news_sound_wave_indicator.dart';
import 'package:flutter_application_1/screens/news_listen_player/widgets/news_subtitle_viewer.dart';
import 'package:flutter_application_1/screens/news_listen_player/widgets/news_summary_dialog.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

Widget _app({
  required Widget child,
  bool dark = false,
  double textScale = 1.0,
  bool scaffold = true,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Theme(
        data: dark ? buildAppDarkTheme(context) : buildAppTheme(context),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: scaffold ? Scaffold(body: child) : child,
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester, [Size size = const Size(360, 640)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _news = <Map<String, dynamic>>[
  {
    'id': 'n1',
    'title': '寒露將至早晚溫差大，醫師提醒長輩外出加件薄外套並注意保暖',
    'category': '健康',
    'content': '中央氣象署表示，下週三進入寒露節氣，各地早晚氣溫明顯下降，'
        '白天與夜間溫差可能超過 8 度。醫師提醒，長輩血管對溫度變化較敏感，'
        '清晨出門運動前可先在室內暖身，並多帶一件薄外套，洗澡水溫也不宜過高。',
    'published_at_raw': '2026-10-01 08:00',
  },
  {
    'id': 'n2',
    'title': '社區共餐據點新增週末場次',
    'category': '生活',
    'content': '',
  },
  {
    'id': 'n3',
    'title': '國際油價小幅回落',
    'category': '財經',
    'content': '內文',
  },
];

void main() {
  setUpAll(() {
    // 測試環境不連網抓字型。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // flutter_tts 在測試環境沒有原生端，攔下 MethodChannel 避免 MissingPluginException。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.example.app/notification_policy'),
            (call) async => false);
  });

  // ──────────────────────────────────────────────────────────────
  // 1. 新聞收聽主畫面
  // ──────────────────────────────────────────────────────────────
  group('新聞收聽主畫面', () {
    for (final dark in [false, true]) {
      testWidgets('360x640、1.3、${dark ? "深色" : "淺色"}：無溢位，三個控制鍵與捲動提示都在',
          (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          scaffold: false,
          child: NewsListenPlayerScreen(
            newsItems: _news,
            initialIndex: 0,
            userId: 1,
          ),
        ));
        await _settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('prev_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('play_pause_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('next_button')), findsOneWidget);
        expect(find.text('在此處往上滑查看更多新聞'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.text('重點整理'), findsOneWidget);

        // 播放控制鍵尺寸：上一則／下一則 60、播放 78（長輩尺度）
        expect(tester.getSize(find.byKey(const ValueKey('prev_button'))).height,
            greaterThanOrEqualTo(60));
        expect(
            tester
                .getSize(find.byKey(const ValueKey('play_pause_button')))
                .height,
            greaterThanOrEqualTo(76));
      });
    }

    testWidgets('點「在此處往上滑」展開面板：分類列與新聞卡出現、無溢位', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(
        textScale: 1.3,
        scaffold: false,
        child: NewsListenPlayerScreen(
          newsItems: _news,
          initialIndex: 0,
          userId: 1,
          startExpanded: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('健康'), findsWidgets);
      expect(find.text('社區共餐據點新增週末場次'), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 2. 新聞子元件
  // ──────────────────────────────────────────────────────────────
  group('新聞子元件', () {
    for (final dark in [false, true]) {
      testWidgets('分類列＋卡片列＋音波＋字幕：360x640、1.3、${dark ? "深色" : "淺色"} 無溢位',
          (tester) async {
        _phone(tester);
        String? picked;
        int? tapped;
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NewsCategorySelector(
                categories: const ['全部', '健康', '生活', '國際', '財經'],
                selectedCategory: '健康',
                onWhiteBackground: true,
                onCategorySelected: (c) => picked = c,
              ),
              NewsCardList(
                newsItems: _news,
                currentIndex: 0,
                selectedCategory: '全部',
                userId: 1,
                onSelectTrack: (i) => tapped = i,
              ),
              const NewsSoundWaveIndicator(isPlaying: true),
              SizedBox(
                height: 260,
                child: NewsSubtitleViewer(
                  subtitles: const [
                    {'text': '寒露將至，早晚溫差大。', 'start_ms': 0, 'duration_ms': 2000},
                    {'text': '醫師提醒長輩外出加件薄外套。', 'start_ms': 2000, 'duration_ms': 3000},
                  ],
                  currentSubtitleIndex: 0,
                  subtitleProgress: 0.4,
                ),
              ),
            ],
          ),
        ));
        await _settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('播放中'), findsOneWidget);

        // 分類鍵高度 ≥48，點下去回呼原值
        final chip = find.text('生活').first;
        expect(
            tester
                .getSize(find.ancestor(
                    of: chip, matching: find.byType(AnimatedContainer)).first)
                .height,
            greaterThanOrEqualTo(48));
        await tester.tap(chip);
        expect(picked, '生活');
        expect(tapped, isNull);
      });
    }

    testWidgets('分類無新聞時顯示空狀態、字幕為空顯示準備播放中', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(
        textScale: 1.3,
        child: Column(
          children: [
            NewsCardList(
              newsItems: _news,
              currentIndex: 0,
              selectedCategory: '運動',
              userId: 1,
              onSelectTrack: (_) {},
            ),
            const Expanded(
              child: NewsSubtitleViewer(
                subtitles: [],
                currentSubtitleIndex: -1,
                subtitleProgress: 0,
              ),
            ),
          ],
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('目前沒有此分類的新聞'), findsOneWidget);
      expect(find.text('準備播放中...'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('重點整理對話框：360x640、1.3、${dark ? "深色" : "淺色"}，「我知道了」呼叫 onClose',
          (tester) async {
        _phone(tester);
        var closed = 0;
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          scaffold: false,
          child: Scaffold(
            body: NewsSummaryDialog(
              summaryText: '下週三開始變冷。早晚溫差超過 8 度。出門多帶一件外套。' * 3,
              onClose: () => closed++,
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        expect(find.text('我知道了'), findsOneWidget);
        await tester.tap(find.text('我知道了'));
        expect(closed, 1);
      });
    }
  });

  // ──────────────────────────────────────────────────────────────
  // 3. 新聞文章頁
  // ──────────────────────────────────────────────────────────────
  group('新聞文章頁', () {
    for (final dark in [false, true]) {
      testWidgets('360x640、1.3、${dark ? "深色" : "淺色"}：無溢位，「聆聽新聞」呼叫 onListenNews 並返回',
          (tester) async {
        _phone(tester);
        var listened = 0;
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          scaffold: false,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewsArticleScreen(
                        newsItem: _news[0],
                        newsItems: _news,
                        currentIndex: 0,
                        userId: 1,
                        onListenNews: () => listened++,
                      ),
                    ),
                  ),
                  child: const Text('進入文章'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('進入文章'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(find.text('返回'), findsOneWidget);
        expect(find.text('健康'), findsOneWidget);
        expect(find.text('示意圖'), findsOneWidget);
        expect(find.text('聆聽新聞'), findsOneWidget);

        // 內文 20pt、行高 1.85
        final body = tester.widget<Text>(
            find.textContaining('中央氣象署表示，下週三進入寒露節氣'));
        expect(body.style?.fontSize, 20);
        expect(body.style?.height, 1.85);

        // 主要 CTA 高 ≥76
        final cta = find.ancestor(
            of: find.text('聆聽新聞'), matching: find.byType(Container)).first;
        expect(tester.getSize(cta).height, greaterThanOrEqualTo(76));

        await tester.tap(find.text('聆聽新聞'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 500));
        expect(listened, 1);
        expect(find.text('進入文章'), findsOneWidget, reason: '應已返回上一頁');
      });
    }

    testWidgets('無內文顯示「（此新聞暫無內文）」', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(
        textScale: 1.3,
        scaffold: false,
        child: NewsArticleScreen(
          newsItem: _news[1],
          newsItems: _news,
          currentIndex: 1,
          userId: 1,
          onListenNews: () {},
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('（此新聞暫無內文）'), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 4. 農民曆
  // ──────────────────────────────────────────────────────────────
  group('農民曆', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('360x640、$scale、${dark ? "深色" : "淺色"}：無溢位，底部列四個操作都在',
            (tester) async {
          _phone(tester);
          await tester.pumpWidget(_app(
            dark: dark,
            textScale: scale,
            scaffold: false,
            child: FarmerAlmanacScreen(initialDate: DateTime(2026, 10, 1)),
          ));
          await _settle(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('農民曆'), findsOneWidget);
          expect(find.text('唸給我聽'), findsOneWidget);
          expect(find.text('前一日'), findsOneWidget);
          expect(find.text('回今天'), findsOneWidget);
          expect(find.text('後一日'), findsOneWidget);
          expect(find.byTooltip('選擇日期'), findsOneWidget);
          // ListView 是惰性建構：往下捲到底，讓宜忌／方位卡也被排版後再檢查溢位。
          await tester.drag(find.byType(ListView), const Offset(0, -2000));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('今日宜忌'), findsOneWidget);
          expect(find.textContaining('今日沖煞'), findsOneWidget);
        });
      }
    }

    testWidgets('前一日／後一日／回今天：日期與「回今天」啟用狀態正確', (tester) async {
      _phone(tester);
      final today = DateTime.now();
      await tester.pumpWidget(_app(
        scaffold: false,
        child: const FarmerAlmanacScreen(),
      ));
      await _settle(tester);
      expect(find.text('今天'), findsOneWidget, reason: '今天的頭部徽章');

      await tester.tap(find.text('後一日'));
      await _settle(tester);
      expect(find.text('今天'), findsNothing);
      final next = today.add(const Duration(days: 1));
      expect(find.text('${next.month}月'), findsOneWidget);

      await tester.tap(find.text('回今天'));
      await _settle(tester);
      expect(find.text('今天'), findsOneWidget);

      await tester.tap(find.text('前一日'));
      await _settle(tester);
      expect(find.text('今天'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('「唸給我聽」切換成「停止」再切回；點宜忌詞彙開啟白話解說、可關閉', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(
        textScale: 1.3,
        scaffold: false,
        child: FarmerAlmanacScreen(initialDate: DateTime(2026, 10, 1)),
      ));
      await _settle(tester);

      await tester.tap(find.text('唸給我聽'));
      await _settle(tester);
      expect(find.text('停止'), findsOneWidget);
      await tester.tap(find.text('停止'));
      await _settle(tester);
      expect(find.text('唸給我聽'), findsOneWidget);

      // 宜忌詞彙：先捲到宜忌卡，點任何一個詞彙 → 出現「是什麼意思？」對話框
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await _settle(tester);
      final chips = find.byWidgetPredicate((w) =>
          w is Text &&
          w.style?.fontSize == 18 &&
          w.style?.fontWeight == FontWeight.w700 &&
          (w.data ?? '').length <= 3 &&
          w.data != '前一日' &&
          w.data != '後一日' &&
          w.data != '回今天');
      expect(chips, findsWidgets, reason: '2026-10-01 應有宜忌詞彙');
      await tester.ensureVisible(chips.first);
      await tester.tap(chips.first);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('是什麼意思？'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('是什麼意思？'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 5. 權限引導
  // ──────────────────────────────────────────────────────────────
  group('權限引導', () {
    for (final dark in [false, true]) {
      testWidgets('360x640、1.3、${dark ? "深色" : "淺色"}：無溢位，三顆按鈕都在且高度 ≥60',
          (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          textScale: 1.3,
          scaffold: false,
          child: const EmergencyPermissionGuideScreen(),
        ));
        await _settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('鎖屏與背景權限'), findsOneWidget);
        expect(find.text('需手動確認'), findsOneWidget);
        // 不得出現「已授權」字樣（誠實限制）
        expect(find.textContaining('已授權'), findsWidgets,
            reason: '說明文字會提到「無法顯示已授權」，但不得有獨立的「已授權」標籤');
        expect(find.text('已授權'), findsNothing);

        await tester.ensureVisible(find.text('我已完成設定'));
        for (final label in ['前往設定', '稍後再說', '我已完成設定']) {
          expect(find.text(label), findsOneWidget);
        }
        final goBtn = find.ancestor(
            of: find.text('前往設定'), matching: find.byType(Container)).first;
        expect(tester.getSize(goBtn).height, greaterThanOrEqualTo(76));
      });
    }

    testWidgets('「我已完成設定」寫入已確認並返回；「稍後再說」不寫入', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(
        scaffold: false,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const EmergencyPermissionGuideScreen()),
                ),
                child: const Text('開引導'),
              ),
            ),
          ),
        ),
      ));

      // 稍後再說
      await tester.tap(find.text('開引導'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('稍後再說'));
      await tester.tap(find.text('稍後再說'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('開引導'), findsOneWidget);
      var prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getBool(EmergencyPermissionGuideScreen.prefsAcknowledgedKey),
          isNull);

      // 我已完成設定
      await tester.tap(find.text('開引導'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('我已完成設定'));
      await tester.tap(find.text('我已完成設定'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('開引導'), findsOneWidget);
      prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getBool(EmergencyPermissionGuideScreen.prefsAcknowledgedKey),
          isTrue);
    });
  });
}
