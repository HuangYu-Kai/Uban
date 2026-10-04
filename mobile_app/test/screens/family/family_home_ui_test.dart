// 家屬端首頁新設計（海灣藍）UI 回歸測試。
//
// 目的：
//   (a) 首頁各卡片、警報面板在 360×640、textScaler 1.3、家屬主題淺／深色下不得出現
//       RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
//   (b) FamilyThemeScope 在 FamilyThemeController 切換時會重建為深色（資料分頁的
//       深色開關就靠它即時生效）。
//   (c) 警報面板的按鈕集合由呼叫端決定——sos_voice 沒有位置時不出現「查看監視畫面」。
//
// 純 UI 測試：不打網路（GPS 卡以 currentElder=null 命中同步的 unavailable 分支）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/home/dialogs/full_dialogue_dialog.dart';
import 'package:flutter_application_1/screens/family/home/sheets/category_detail_sheet.dart';
import 'package:flutter_application_1/screens/family/home/sheets/send_care_card_sheet.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_ai_mood_radar_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_elder_header_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_elder_life_feed.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_gps_trail_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_monitor_device_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_zone_card.dart';
import 'package:flutter_application_1/screens/family/widgets/fam_ui.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final elder = Elder(
    id: 7,
    elderId: '1234',
    name: '王大明爸爸這個名字故意取得很長很長很長',
    gender: 'M',
    age: 78,
    location: '台北市萬華區某某路某某巷某某號',
  );

  final now = DateTime.now();
  String ts(int minutesAgo) =>
      now.subtract(Duration(minutes: minutesAgo)).toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  final logs = <Map<String, dynamic>>[
    {'log_id': 1, 'event_type': 'chat', 'content': '長者詢問：今天天氣如何 | AI 回應：今天天氣晴朗，適合出門散步。', 'timestamp': ts(5)},
    {'log_id': 2, 'event_type': 'medication', 'content': '早餐後完成降血壓藥打卡', 'timestamp': ts(60)},
    {'log_id': 3, 'event_type': 'activity', 'content': '戶外散步累計 3850 步', 'timestamp': ts(120)},
    {'log_id': 4, 'event_type': 'news_view', 'content': '【新聞點閱】類別: sports | 標題: NBA 季後賽戰況', 'timestamp': ts(180)},
    {'log_id': 5, 'event_type': 'alert', 'content': '【提醒】午餐藥還沒打卡 | 原訂 12:30', 'timestamp': ts(30)},
  ];

  Widget harness(Widget child, {required bool dark}) {
    final theme = FamilyTheme.buildTheme(
      // buildTheme 只用 context 以外的參數；這裡給任一 context 即可。
      _FakeContext(),
      isDark: dark,
    );
    return MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> pumpCase(WidgetTester tester, Widget child, {required bool dark}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(child, dark: dark));
    await tester.pump(const Duration(seconds: 2));
  }

  final cases = <String, Widget Function()>{
    'HomeElderHeaderCard': () => HomeElderHeaderCard(
          currentElder: elder,
          isElderOnline: true,
          realLogs: logs,
        ),
    'HomeZoneCard（偵測中）': () => HomeZoneCard(
          monitorDevices: const [
            {'deviceId': 1, 'deviceName': '客廳監視機名字也很長很長很長很長'}
          ],
          elderZone: {
            'present': true,
            'enteredAt': DateTime.now().subtract(const Duration(minutes: 12)),
            'updatedAt': DateTime.now(),
          },
        ),
    'HomeZoneCard（未綁定）': () => const HomeZoneCard(),
    'HomeGpsTrailCard': () => const HomeGpsTrailCard(),
    'HomeMonitorDeviceCard': () => HomeMonitorDeviceCard(
          monitorDevices: const [
            {'deviceId': 1, 'deviceName': '客廳監視機名字也很長很長很長很長', 'isOnline': true},
            {'deviceId': 2, 'deviceName': '臥室', 'isOnline': false},
          ],
          activeAlerts: const [],
          currentElder: elder,
        ),
    'HomeAiMoodRadarCard': () => HomeAiMoodRadarCard(
          currentElder: elder,
          moodInsightData: const {
            'mood_title': '心情平穩，有點想孫子',
            'mood_score': 72,
            'summary': '今天和小嘎聊了很久，提到早上去龍山寺拜拜，說膝蓋比上週好。',
            'icebreaker_topic': '問她龍山寺今天人多不多',
          },
          realLogs: logs,
          onStartVideoCall: () {},
        ),
    'HomeAlertPreviewCard（有警示）': () => HomeAlertPreviewCard(
          currentElder: elder,
          activeAlerts: const [
            {'alert_id': 'a1', 'alert_type': 'fall', 'device_id': '1', 'confidence': 0.93},
            {'alert_id': 'a2', 'alert_type': 'sos_voice', 'device_id': '0'},
          ],
          realLogs: logs,
          userId: 1,
        ),
    'HomeAlertPreviewCard（讀取中）': () => const HomeAlertPreviewCard(dismissedKeysLoaded: false),
    'HomeAlertPreviewCard（空）': () => const HomeAlertPreviewCard(),
    'HomeElderLifeFeed': () => HomeElderLifeFeed(
          currentElder: elder,
          realLogs: logs,
          moodInsightData: const {
            'topic_clusters': [
              {'title': '體育賽事與熱門新聞關注', 'match_keywords': ['NEWS', '新聞', 'NBA']},
              {'title': '健康運動與日常作息保養', 'match_keywords': ['WALK', 'MEDICINE', '藥', '散步']},
            ],
          },
        ),
    'HomeElderLifeFeed（無紀錄）': () => HomeElderLifeFeed(currentElder: elder),
  };

  for (final dark in [false, true]) {
    for (final e in cases.entries) {
      testWidgets('${e.key} 在 360×640／1.3 倍字／${dark ? "深" : "淺"}色下無溢位', (tester) async {
        await pumpCase(tester, e.value(), dark: dark);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('警報面板 FamAlarmSheet', () {
    // 按鈕集合與條件由 family_main_screen.dart 決定；這裡驗證四種情境下面板能容納
    // 全部按鈕且不溢位，並確認 sos_voice 沒位置時只有「我知道了」。
    Widget sheet(List<FamAlarmAction> primary, List<String> lines) => FamAlarmSheet(
          title: '偵測到跌倒（王大明爸爸這個名字故意取得很長很長）',
          description: '請立即查看監視畫面確認長輩狀況。',
          detailLines: lines,
          primary: primary,
          dismiss: FamAlarmAction('我知道了', () {}),
        );

    for (final dark in [false, true]) {
      testWidgets('CCTV／跌倒（查看監視畫面＋我知道了）${dark ? "深" : "淺"}色', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: sheet([FamAlarmAction('查看監視畫面', () {})], ['監視機：客廳', '信心度 93%']),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.text('查看監視畫面'), findsOneWidget);
        expect(find.text('我知道了'), findsOneWidget);
      });

      testWidgets('sos_voice 附位置（查看位置＋我知道了）${dark ? "深" : "淺"}色', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: sheet([FamAlarmAction('查看位置', () {})], ['最後定位 3 分鐘前']),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.text('查看位置'), findsOneWidget);
        expect(find.text('查看監視畫面'), findsNothing);
      });
    }

    testWidgets('sos_voice 無位置：只有「我知道了」，沒有看監視畫面／位置', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext()),
        home: Scaffold(body: sheet(const [], const [])),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('我知道了'), findsOneWidget);
      expect(find.text('查看監視畫面'), findsNothing);
      expect(find.text('查看位置'), findsNothing);
    });

    testWidgets('點「我知道了」會呼叫傳入的 callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext()),
        home: Scaffold(
          body: FamAlarmSheet(
            title: '偵測到緊急求救',
            description: 'desc',
            dismiss: FamAlarmAction('我知道了', () => tapped++),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('我知道了'));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('底部面板／彈窗', () {
    Future<void> pumpHost(WidgetTester tester, bool dark, void Function(BuildContext) open) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    for (final dark in [false, true]) {
      testWidgets('分類詳細面板 ${dark ? "深" : "淺"}色無溢位', (tester) async {
        await pumpHost(tester, dark, (ctx) {
          showCategoryDetailModal(
            ctx,
            categoryTitle: '健康運動與日常作息保養的很長很長很長的分類名稱',
            items: [
              for (final l in logs)
                {
                  'id': l['log_id'],
                  'rawTimestamp': l['timestamp'],
                  'time': '10:24',
                  'date': '2026-10-04',
                  'badge': 'AI CHAT',
                  'title': l['content'],
                  'desc': l['content'],
                  'fullQuery': '與 AI 長輩陪伴語音互動',
                  'fullAi': l['content'],
                  'isChat': true,
                }
            ],
          );
        });
        expect(tester.takeException(), isNull);
        expect(find.text('關閉'), findsOneWidget);
      });

      testWidgets('完整對話彈窗 ${dark ? "深" : "淺"}色無溢位', (tester) async {
        await pumpHost(tester, dark, (ctx) {
          showFullDialogueDialog(ctx, '今天天氣如何？' * 6, '今天天氣晴朗，適合出門散步。' * 8, '10:24');
        });
        expect(tester.takeException(), isNull);
        expect(find.text('關閉'), findsOneWidget);
      });

      testWidgets('發送關懷卡面板 ${dark ? "深" : "淺"}色無溢位', (tester) async {
        await pumpHost(tester, dark, (ctx) {
          SendCareCardSheet.show(ctx, currentElder: elder, elderName: '王大明爸爸這個名字故意取得很長很長');
        });
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        expect(find.text('AI 近況短句'), findsOneWidget);
      });
    }
  });

  group('FamilyThemeScope', () {
    testWidgets('controller 切換時重建為深色', (tester) async {
      final controller = FamilyThemeController(false);
      Brightness? seen;
      Color? bg;
      await tester.pumpWidget(MaterialApp(
        home: FamilyThemeScope(
          controller: controller,
          child: Builder(builder: (context) {
            seen = Theme.of(context).brightness;
            bg = UbanColors.of(context).bg;
            return const SizedBox();
          }),
        ),
      ));
      expect(seen, Brightness.light);
      expect(bg, UbanColors.familyLight.bg);

      controller.value = true;
      await tester.pump();
      expect(seen, Brightness.dark);
      expect(bg, UbanColors.familyDark.bg);

      controller.value = false;
      await tester.pump();
      expect(seen, Brightness.light);
    });

    testWidgets('setDark 會寫入既有的 SharedPreferences 鍵', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = FamilyThemeController(false);
      await tester.runAsync(() => controller.setDark(true));
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool('family_theme_is_dark'), isTrue);
      expect(controller.value, isTrue);
    });
  });
}

/// FamilyTheme.buildTheme 的 context 參數只是舊簽章，內部不使用；測試給個占位。
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
