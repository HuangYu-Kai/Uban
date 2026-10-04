// 2026-10-02：語音求救（sos_voice）在家屬端卡片的文案與位置回歸測試。
//
// 鎖住兩件事：
// 1. G196——sos_voice／未知警報型別不可被寫成跌倒、也不可叫家屬去看監視畫面；
// 2. 求救「有位置才顯示位置相關 UI」，沒位置時不可出現假提示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_application_1/screens/family/alert_center_screen.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';
import 'package:flutter_application_1/utils/alert_display.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AlertDisplay', () {
    test('sos_voice 文案不含跌倒／監視畫面', () {
      final all = [
        AlertDisplay.title('sos_voice'),
        AlertDisplay.liveDesc('sos_voice', confText: ' (信心度 90%)'),
        AlertDisplay.pastDesc('sos_voice'),
      ].join('|');
      expect(all, contains('求救'));
      expect(all, isNot(contains('跌倒')));
      expect(all, isNot(contains('監視')));
      expect(all, isNot(contains('信心度')));
    });

    test('未知型別退回中性「異常狀況」，不宣稱跌倒', () {
      final all = [
        AlertDisplay.title('something_new'),
        AlertDisplay.liveDesc('something_new'),
        AlertDisplay.pastDesc('something_new'),
      ].join('|');
      expect(all, contains('異常狀況'));
      expect(all, isNot(contains('跌倒')));
    });

    test('fall 文案維持原樣', () {
      expect(AlertDisplay.title('fall'), '🚨 跌倒緊急警報');
      expect(AlertDisplay.pastDesc('fall'), '監視機曾偵測到長輩疑似跌倒。');
    });

    test('parseLocation：數字、字串皆可；缺漏／越界回傳 null', () {
      expect(
        AlertDisplay.parseLocation({'latitude': 25.03, 'longitude': 121.56}),
        (lat: 25.03, lng: 121.56),
      );
      expect(
        AlertDisplay.parseLocation({'latitude': '25.03', 'longitude': '121.56'}),
        (lat: 25.03, lng: 121.56),
      );
      expect(AlertDisplay.parseLocation({'latitude': 25.03}), isNull);
      expect(AlertDisplay.parseLocation({'latitude': null, 'longitude': null}), isNull);
      expect(AlertDisplay.parseLocation({'latitude': 91, 'longitude': 0}), isNull);
      expect(AlertDisplay.parseLocation({'latitude': 'x', 'longitude': 'y'}), isNull);
      expect(AlertDisplay.parseLocation(null), isNull);
    });

    test('lastLocationText：分鐘／小時／天；沒時間回傳 null', () {
      final now = DateTime(2026, 10, 2, 12, 0);
      expect(AlertDisplay.lastLocationText(null, now: now), isNull);
      expect(AlertDisplay.lastLocationText(now, now: now), '最後位置：剛剛');
      expect(
        AlertDisplay.lastLocationText(now.subtract(const Duration(minutes: 5)), now: now),
        '最後位置：5 分鐘前',
      );
      expect(
        AlertDisplay.lastLocationText(now.subtract(const Duration(hours: 3)), now: now),
        '最後位置：3 小時前',
      );
      expect(
        AlertDisplay.lastLocationText(now.subtract(const Duration(days: 2)), now: now),
        '最後位置：2 天前',
      );
      // 裝置時鐘比伺服器慢（差值為負）也當作剛剛
      expect(
        AlertDisplay.lastLocationText(now.add(const Duration(minutes: 2)), now: now),
        '最後位置：剛剛',
      );
    });
  });

  group('首頁最新警示卡片', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> alerts) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeAlertPreviewCard(activeAlerts: alerts),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sos_voice 顯示求救文案、不顯示跌倒', (tester) async {
      await pump(tester, [
        {'alert_id': '1', 'alert_type': 'sos_voice', 'device_id': 0},
      ]);
      expect(find.text('🆘 長輩開口求救'), findsOneWidget);
      expect(find.textContaining('跌倒'), findsNothing);
      // 沒有位置：不可點（沒有 chevron）、不出現位置提示
      expect(find.textContaining('最後位置'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('未知型別顯示中性文案', (tester) async {
      await pump(tester, [
        {'alert_id': '2', 'alert_type': 'brand_new_type', 'device_id': 3},
      ]);
      expect(find.text('⚠️ 異常狀況警報'), findsOneWidget);
      expect(find.textContaining('跌倒'), findsNothing);
    });
  });

  group('警示中心卡片', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> alerts) async {
      await tester.pumpWidget(MaterialApp(
        home: AlertCenterScreen(
          elderName: '陳阿嬤',
          elderId: 1,
          elderRoomId: 'E001',
          activeAlerts: alerts,
          historyAlertItemsOverride: const [],
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('即時 sos_voice 無位置：沒有「查看位置」', (tester) async {
      await pump(tester, [
        {'alert_id': '1', 'alert_type': 'sos_voice', 'elder_id': 'E001'},
      ]);
      expect(find.text('🆘 長輩開口求救'), findsOneWidget);
      expect(find.textContaining('跌倒'), findsNothing);
      expect(find.text('查看位置'), findsNothing);
    });

    testWidgets('即時 sos_voice 有位置：顯示「最後位置」與「查看位置」', (tester) async {
      final at = DateTime.now().toUtc().subtract(const Duration(minutes: 7));
      await pump(tester, [
        {
          'alert_id': '1',
          'alert_type': 'sos_voice',
          'elder_id': 'E001',
          'latitude': 25.03,
          'longitude': 121.56,
          'location_at': at.toIso8601String(),
        },
      ]);
      expect(find.text('查看位置'), findsOneWidget);
      expect(find.textContaining('最後位置：7 分鐘前'), findsOneWidget);
    });

    testWidgets('窄螢幕（280px）位置列不溢位', (tester) async {
      tester.view.physicalSize = const Size(280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, [
        {
          'alert_id': '1',
          'alert_type': 'sos_voice',
          'elder_id': 'E001',
          'latitude': 25.03,
          'longitude': 121.56,
          'location_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]);
      expect(tester.takeException(), isNull);
    });
  });
}
