// 家屬端第 4 批（資料分頁與其子頁）新設計 UI 回歸測試。
//
// 目的：
//   (a) 資料分頁、健康趨勢、回憶錄、訂閱頁、情緒時間軸、回報問題頁，在 360×640、
//       textScaler 1.3、家屬主題淺／深色下不得出現 RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
//   (b) 資料分頁的深色開關點下去後，FamilyThemeController.instance.value 真的改變
//       （主殼就是用同一個 callback 接 controller）。
//   (c) 登出／換手機連結／編輯名稱對話框改走 UbanDialog 後仍能開啟、取消能關閉，
//       且深色模式下對話框底色是家屬深色 surface（showFamDialog 在路由內自掛主題）。
//   (d) 任何一張卡片都不得掉進 ErrorBoundary 的「這張卡片載入失敗」。
//
// 純 UI 測試：不打網路（ApiService 由 flutter test 的 HttpClient 立即回 400，各畫面既有 try/catch 吞掉）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/screens/family/emotion_timeline_screen.dart';
import 'package:flutter_application_1/screens/family/family_bug_report_screen.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';
import 'package:flutter_application_1/screens/family/family_subscription_screen.dart';
import 'package:flutter_application_1/screens/family/health_trends_screen.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';
import 'package:flutter_application_1/screens/family/widgets/fam_ui.dart';
import 'package:flutter_application_1/services/memoir_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/family_theme.dart';
import 'package:flutter_application_1/widgets/ui/uban_segmented.dart';
import 'package:flutter_application_1/widgets/ui/uban_switch.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // FamilyThemeScope 的 initState 會 load 一次偏好；先讀完，之後測試才能自己指定深淺色。
    await FamilyThemeController.instance.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FamilyThemeController.instance.value = false;
  });

  final elder = Elder(
    id: 7,
    elderId: '1234',
    name: '王大明爸爸這個名字故意取得很長很長很長',
    gender: 'M',
    age: 78,
    location: '臺北市萬華區這個地址也取得很長很長很長很長',
  );

  const bigTitle = '民國五十年在大稻埕當學徒的日子這個標題故意寫得很長很長很長很長';

  Future<void> seedMemoirs() async {
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_ui_1',
      elderId: '1234',
      title: bigTitle,
      tag: '奮鬥歲月',
      preview: '那時候天還沒亮就要起床，店裡的活兒做不完，師傅很嚴格但是很照顧我們這些學徒。',
      fullStory: '那時候天還沒亮就要起床，店裡的活兒做不完，師傅很嚴格但是很照顧我們這些學徒。' * 4,
      promptQuestion: '年輕的時候做過什麼工作？',
      recordedDate: DateTime(2026, 9, 28),
    ));
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_ui_2',
      elderId: '1234',
      title: '阿公騎鐵馬載我去看歌仔戲',
      tag: '經典回憶',
      preview: '夏天的傍晚，阿公把我放在前面的橫槓上。',
      fullStory: '夏天的傍晚，阿公把我放在前面的橫槓上。',
      promptQuestion: '小時候最開心的事？',
      recordedDate: DateTime(2026, 10, 2),
      isFavorite: true,
    ));
  }

  Widget harness(Widget child, {required bool dark}) {
    FamilyThemeController.instance.value = dark;
    return MaterialApp(
      theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: child,
    );
  }

  Future<void> pumpCase(WidgetTester tester, Widget child,
      {required bool dark}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(child, dark: dark));
    await tester.pump(const Duration(seconds: 2));
  }

  /// 一路往下捲到底，每一步都檢查沒有例外。
  Future<void> scrollToBottom(WidgetTester tester, Finder scrollable) async {
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull, reason: '捲動第 ${i + 1} 步出現例外');
    }
  }

  Widget dataTab({Elder? e, bool dark = false, ValueChanged<bool>? onToggle}) =>
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: FamilyThemeController.instance,
          builder: (context, isDark, _) => FamilyDataTab(
            currentElder: e,
            userId: 1,
            userName: '測試家屬名稱也故意很長很長很長很長',
            isDarkMode: isDark,
            onToggleDarkMode: onToggle,
          ),
        ),
      );

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '淺色';

    testWidgets('資料分頁（有長輩）360×640 ×1.3 $mode 無溢位、無卡片掉進 ErrorBoundary',
        (tester) async {
      await seedMemoirs();
      await pumpCase(tester, dataTab(e: elder), dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('這張卡片載入失敗'), findsNothing);
      expect(find.text('受關照長輩檔案'), findsOneWidget);
      await scrollToBottom(tester, find.byType(CustomScrollView));
      expect(find.text('這張卡片載入失敗'), findsNothing);
    });

    testWidgets('資料分頁（尚未選長輩）360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(tester, dataTab(), dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('尚未選擇要關照的長輩'), findsOneWidget);
      await scrollToBottom(tester, find.byType(CustomScrollView));
      expect(find.text('這張卡片載入失敗'), findsNothing);
    });

    testWidgets('健康趨勢 360×640 ×1.3 $mode 切換步數／體重／身高、週月半年年皆無溢位',
        (tester) async {
      await pumpCase(
        tester,
        const HealthTrendsScreen(elderName: '王大明爸爸這個名字故意取得很長', elderId: 7),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(UbanSegmented), findsOneWidget);
      for (final label in ['體重', '身高', '步數']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '切到「$label」出現例外');
      }
      for (final label in ['月', '半年', '年', '週']) {
        await tester.tap(find.widgetWithText(FamFilterChip, label));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '切到「$label」出現例外');
      }
      await scrollToBottom(tester, find.byType(SingleChildScrollView).first);
    });

    testWidgets('回憶錄 360×640 ×1.3 $mode 列表／繪本／委託提問彈窗皆無溢位', (tester) async {
      await seedMemoirs();
      await pumpCase(
        tester,
        const MemoirsGalleryScreen(elderId: '1234', elderName: '王大明爸爸這個名字故意取得很長'),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(bigTitle), findsOneWidget);
      // 篩選：切到「珍藏」只剩一則。
      final favChip = find.widgetWithText(FamFilterChip, '珍藏');
      await tester.ensureVisible(favChip); // 篩選列可橫向捲動，360 寬時「珍藏」在畫面外
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(favChip);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(bigTitle), findsNothing);
      expect(find.text('阿公騎鐵馬載我去看歌仔戲'), findsOneWidget);
      final allChip = find.widgetWithText(FamFilterChip, '全部 2');
      await tester.ensureVisible(allChip);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(allChip);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      // 繪本模式
      await tester.tap(find.byTooltip('切換繪本翻頁模式'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('第 1 / 2 章'), findsOneWidget);

      // 委託提問彈窗
      await tester.tap(find.text('委託提問'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('託付給小豬'), findsOneWidget);
    });

    testWidgets('訂閱頁 360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(tester, const FamilySubscriptionScreen(), dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('選擇最適合您家人的方案'), findsOneWidget);
      expect(find.text('黃金會員'), findsOneWidget);
      await scrollToBottom(tester, find.byType(SingleChildScrollView).first);
    });

    testWidgets('情緒時間軸與回報問題頁 360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(
        tester,
        const EmotionTimelineScreen(elderName: '王大明', elderId: null),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('尚未配對長輩'), findsOneWidget);

      await pumpCase(tester, const FamilyBugReportScreen(familyId: 1), dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('送出回報'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '標題' * 20);
      await tester.pump();
      await scrollToBottom(tester, find.byType(SingleChildScrollView).first);
    });
  }

  // 有資料時才會畫出 fl_chart 折線圖、統計格與虛線平均；用 http.runWithClient 注入假回應。
  for (final dark in [false, true]) {
    testWidgets('健康趨勢（有資料）360×640 ×1.3 ${dark ? '深色' : '淺色'} 折線圖、統計格、新增紀錄 sheet 無溢位',
        (tester) async {
      final now = DateTime(2026, 10, 4);
      String d(int back) {
        final t = now.subtract(Duration(days: back));
        return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      }

      final client = MockClient((req) async {
        Map<String, dynamic> body;
        if (req.url.path.contains('/family_insight/steps/')) {
          body = {
            'status': 'success',
            'data': {
              'available': true,
              'series': [
                for (var i = 29; i >= 0; i--)
                  {'date': d(i), 'steps': i % 7 == 3 ? null : 2500 + (i * 137) % 4200},
              ],
            },
          };
        } else if (req.url.path.contains('/family_insight/body_metrics/')) {
          body = {
            'status': 'success',
            'data': {
              'available': true,
              'series': [
                for (var i = 4; i >= 0; i--)
                  {'date': d(i * 5), 'weight_kg': 58.0 + i * 0.6, 'height_cm': 158.0},
              ],
            },
          };
        } else {
          body = {'status': 'error', 'message': 'not mocked'};
        }
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({'caregiver_id': 1});
        await pumpCase(
          tester,
          const HealthTrendsScreen(elderName: '王大明', elderId: 7),
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(LineChart), findsOneWidget);
        expect(find.textContaining('虛線：這段期間平均'), findsOneWidget);
        expect(find.text('最多一天'), findsOneWidget);

        await tester.tap(find.text('體重'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        expect(find.byType(LineChart), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);

        await tester.tap(find.text('身高'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);

        // 新增紀錄 sheet
        final addBtn = find.text('新增紀錄');
        await tester.ensureVisible(addBtn);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(addBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        expect(find.text('新增體重／身高紀錄'), findsOneWidget);
        expect(find.text('儲存'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
      }, () => client);
    });
  }

  testWidgets('深色開關：點擊後 FamilyThemeController.instance.value 改變，再點一次恢復', (tester) async {
    await pumpCase(
      tester,
      dataTab(
        e: elder,
        onToggle: (v) => FamilyThemeController.instance.setDark(v),
      ),
      dark: false,
    );
    expect(FamilyThemeController.instance.value, isFalse);

    final sw = find.byType(UbanSwitch).first;
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 400));
    expect(FamilyThemeController.instance.value, isTrue,
        reason: '深色開關必須走原本的 onToggleDarkMode callback，最終改到 FamilyThemeController');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(UbanSwitch).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(FamilyThemeController.instance.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登出對話框（UbanDialog）：深色模式底色為家屬深色 surface，取消可關閉', (tester) async {
    await pumpCase(tester, dataTab(e: elder), dark: true);
    await tester.tap(find.text('登出目前帳號'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('安全登出'), findsOneWidget);
    expect(find.text('確認登出'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, UbanColors.familyDark.surface,
        reason: 'showFamDialog 要在路由內自掛家屬主題，深色模式下對話框底色才會是深色 surface');

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('安全登出'), findsNothing);
  });

  testWidgets('編輯名稱與長輩換手機連結對話框 360×640 ×1.3 可開啟、無溢位', (tester) async {
    await pumpCase(tester, dataTab(e: elder), dark: false);

    await tester.tap(find.byTooltip('編輯名稱'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('編輯我的顯示名稱'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final row = find.text('長輩移機與免密重裝助手');
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable));
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('長輩移機與重裝助手'), findsOneWidget);
    expect(find.text('產生並分享'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 讓捲動時新建卡片的 flutter_animate 零秒計時器跑完，避免測試結束時還有 pending timer。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('教學用 GlobalKey 掛在對應卡片上（4 個都有 currentContext）', (tester) async {
    await seedMemoirs();
    final k1 = GlobalKey(), k2 = GlobalKey(), k3 = GlobalKey(), k4 = GlobalKey();
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(
      Scaffold(
        body: FamilyDataTab(
          currentElder: elder,
          userId: 1,
          userName: '測試家屬',
          caregiverCardKey: k1,
          elderSummaryKey: k2,
          memoirsKey: k3,
          aiHelperKey: k4,
        ),
      ),
      dark: false,
    ));
    await tester.pump(const Duration(seconds: 2));
    for (final k in [k1, k2, k3, k4]) {
      expect(k.currentContext, isNotNull);
      expect(k.currentContext!.findRenderObject(), isA<RenderBox>());
    }
    await tester.pump(const Duration(seconds: 1));
  });
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
