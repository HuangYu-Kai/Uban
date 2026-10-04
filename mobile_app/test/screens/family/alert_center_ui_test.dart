// 家屬端第 3 批（警示中心＋遠端排程提醒）新外觀的版面回歸測試。
//
// 目的：
//   (a) 警示中心（有即時警報／有歷史紀錄／空資料）與健康提醒頁（列表／空／新增表單）
//       在 360×640、textScaler 1.3、家屬主題淺／深色下不得出現 RenderFlex 溢位
//       （CLAUDE.md §3.1 第 14 條；溢位在測試中會變成例外）。
//   (b) G196：sos_voice 沒有位置時畫面上沒有「查看位置」；任何 sos_voice 項目
//       都不得出現「監視」字樣（也不得有跌倒文案）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/alert_center_screen.dart';
import 'package:flutter_application_1/screens/family/health_reminder_screen.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

MockClient _client(List<Map<String, dynamic>> reminders) => MockClient((req) async {
      return http.Response(
        jsonEncode({'status': 'success', 'data': reminders}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required bool dark,
  MockClient? client,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({FamilyThemeController.prefsKey: dark});
  FamilyThemeController.instance.value = dark;
  // 同一個測試內多次呼叫時先清掉舊畫面，State 才會重新載入。
  await tester.pumpWidget(const SizedBox());
  Future<void> body() async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: screen,
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  if (client != null) {
    await http.runWithClient(body, () => client);
  } else {
    await body();
  }
}

/// 沿著主要的 ListView 一路捲到底，每一步都確認沒有溢位例外
/// （ListView 只建構可見範圍，不捲就看不到下面的列）。
Future<void> _scrollAll(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 8; i++) {
    await tester.drag(list, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: '捲動第 $i 步出現例外');
  }
}

Map<String, dynamic> _item({
  required String id,
  String title = '🚨 跌倒緊急警報',
  String desc = '監視機曾偵測到長輩疑似跌倒。（發生於 10/03 21:10）',
  String level = 'high',
  DateTime? ts,
  int? alertId,
  String status = 'active',
  String source = '',
  bool falseAlarm = false,
  bool hasLocation = false,
  DateTime? locationAt,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'desc': desc,
    'level': level,
    'icon': Icons.warning_amber_rounded,
    'sortTs': ts,
    'alertId': alertId,
    'isFalseAlarm': falseAlarm,
    'status': status,
    'resolution_source': source,
    'hasLocation': hasLocation,
    'locationAt': locationAt,
    'locationDate': hasLocation ? (locationAt ?? ts) : null,
  };
}

Widget _alertCenter({
  List<Map<String, dynamic>> live = const [],
  List<Map<String, dynamic>> history = const [],
}) =>
    AlertCenterScreen(
      elderName: '陳阿嬤',
      elderId: 1,
      elderRoomId: 'E001',
      activeAlerts: live,
      historyAlertItemsOverride: history,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9, 30);
  final yesterday = today.subtract(const Duration(days: 1));
  final older = today.subtract(const Duration(days: 5));

  final liveAlerts = <Map<String, dynamic>>[
    {'alert_id': '1', 'alert_type': 'sos_voice', 'elder_id': 'E001'},
    {
      'alert_id': '2',
      'alert_type': 'sos_voice',
      'elder_id': 'E001',
      'latitude': 25.03,
      'longitude': 121.56,
      'location_at': DateTime.now().toUtc().subtract(const Duration(minutes: 7)).toIso8601String(),
    },
    {'alert_id': '3', 'alert_type': 'fall', 'elder_id': 'E001', 'confidence': 0.91},
  ];

  final historyItems = <Map<String, dynamic>>[
    _item(id: 'alert:11', alertId: 11, status: 'active', ts: today),
    _item(id: 'alert:12', alertId: 12, status: 'acknowledged', ts: today),
    _item(
      id: 'alert:13',
      alertId: 13,
      status: 'resolved',
      source: 'legacy_auto',
      ts: yesterday,
      title: '🆘 長輩開口求救',
      desc: '長輩曾透過語音助理（小嘎）開口求救。（發生於 10/03 09:30）',
    ),
    _item(
      id: 'alert:14',
      alertId: 14,
      status: 'resolved',
      source: 'family',
      ts: yesterday,
      title: '🆘 長輩開口求救',
      desc: '長輩曾透過語音助理（小嘎）開口求救。（發生於 10/03 09:31）',
      hasLocation: true,
      locationAt: yesterday,
    ),
    _item(id: 'alert:15', alertId: 15, status: 'resolved', falseAlarm: true, ts: older),
    _item(
      id: 'log:1',
      level: 'medium',
      title: '午餐藥還沒打卡，這是一個刻意拉長的標題用來測試文字在窄螢幕換行時不會溢位',
      desc: '提醒：午餐藥還沒打卡｜原訂 12:30，請協助確認長輩是否已經服藥並回報。',
      ts: older,
    ),
    _item(id: 'log:2', level: 'medium', title: '時間不明的活動警示', desc: '沒有時間戳', ts: null),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '淺色';

    testWidgets('警示中心（有即時警報＋歷史）$mode：360×640、1.3 倍字不溢位', (tester) async {
      await _pump(tester, _alertCenter(live: liveAlerts, history: historyItems), dark: dark);
      expect(find.text('正在發生'), findsOneWidget);
      expect(find.text('警示紀錄'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      await _scrollAll(tester);
    });

    testWidgets('警示中心（空資料）$mode：顯示空狀態與篩選列、不溢位', (tester) async {
      await _pump(tester, _alertCenter(), dark: dark);
      expect(find.text('目前沒有警示'), findsOneWidget);
      expect(find.text('本週沒有警示紀錄'), findsOneWidget);
      expect(find.text('本週'), findsOneWidget);
      expect(find.text('全部狀態'), findsOneWidget);
      await _scrollAll(tester);
    });

    testWidgets('健康提醒頁（有資料）$mode：列表與新增／編輯表單不溢位', (tester) async {
      final reminders = [
        {
          'id': 1,
          'title': '服用降壓藥乙顆，飯後半小時內，記得配溫開水不要配茶',
          'category': 'medication',
          'time_str': '08:00',
          'repeat_days': '每週一三五',
          'note': '記得飯後服用、帶隨身健保卡，出門前再確認一次',
          'is_active': 1,
        },
        {
          'id': 2,
          'title': '台大回診',
          'category': 'hospital',
          'time_str': '09:30',
          'repeat_days': '單次提醒',
          'note': '',
          'is_active': 0,
        },
      ];
      await _pump(
        tester,
        const HealthReminderScreen(elderId: 'E001', elderName: '陳阿嬤', familyId: 1),
        dark: dark,
        client: _client(reminders),
      );
      expect(find.textContaining('目前共有 1 項目在線啟用中'), findsOneWidget);
      await _scrollAll(tester);
      // 第二筆在第一屏以下，捲到底才會建構。
      expect(find.text('台大回診'), findsOneWidget);

      // 新增表單
      await tester.tap(find.text('新增提醒'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('新增遠端排程提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 標題空白送出：驗證仍擋下（SnackBar），表單不關閉。
      await tester.ensureVisible(find.text('確認新增提醒'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('確認新增提醒'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('請輸入提醒標題'), findsOneWidget);
      expect(find.text('新增遠端排程提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('健康提醒頁（編輯表單）$mode：不溢位', (tester) async {
      await _pump(
        tester,
        const HealthReminderScreen(elderId: 'E001', elderName: '陳阿嬤', familyId: 1),
        dark: dark,
        client: _client([
          {
            'id': 7,
            'title': '喝水',
            'category': 'water',
            'time_str': '10:15',
            'repeat_days': '每天',
            'note': '',
            'is_active': 1,
          },
        ]),
      );
      await tester.tap(find.text('編輯'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('編輯遠端排程提醒'), findsOneWidget);
      expect(find.text('儲存變更'), findsOneWidget);
      expect(find.text('10:15'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('健康提醒頁（空資料）$mode：不溢位', (tester) async {
      await _pump(
        tester,
        const HealthReminderScreen(elderId: 'E001', elderName: '陳阿嬤', familyId: 1),
        dark: dark,
        client: _client(const []),
      );
      expect(find.text('目前尚未建立任何排程提醒'), findsOneWidget);
      await _scrollAll(tester);
    });
  }

  group('G196：sos_voice 的呈現', () {
    testWidgets('即時 sos_voice 無位置：沒有「查看位置」、沒有「監視」、沒有跌倒文案', (tester) async {
      await _pump(
        tester,
        _alertCenter(live: [
          {'alert_id': '1', 'alert_type': 'sos_voice', 'elder_id': 'E001'},
        ]),
        dark: false,
      );
      expect(find.text('🆘 長輩開口求救'), findsOneWidget);
      expect(find.text('查看位置'), findsNothing);
      expect(find.textContaining('最後位置'), findsNothing);
      expect(find.textContaining('監視'), findsNothing);
      expect(find.textContaining('跌倒'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('即時 sos_voice 有位置：顯示「最後位置」與「查看位置」，仍沒有「監視」', (tester) async {
      await _pump(
        tester,
        _alertCenter(live: [
          {
            'alert_id': '1',
            'alert_type': 'sos_voice',
            'elder_id': 'E001',
            'latitude': 25.03,
            'longitude': 121.56,
            'location_at':
                DateTime.now().toUtc().subtract(const Duration(minutes: 7)).toIso8601String(),
          },
        ]),
        dark: false,
      );
      expect(find.text('查看位置'), findsOneWidget);
      expect(find.textContaining('最後位置：7 分鐘前'), findsOneWidget);
      expect(find.textContaining('監視'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('歷史 sos_voice（有／無位置）：只有有位置那筆有「查看位置」；任何按鈕都不含「監視」',
        (tester) async {
      await _pump(
        tester,
        _alertCenter(history: [
          _item(
            id: 'alert:21',
            alertId: 21,
            status: 'active',
            ts: today,
            title: '🆘 長輩開口求救',
            desc: '長輩曾透過語音助理（小嘎）開口求救。',
          ),
          _item(
            id: 'alert:22',
            alertId: 22,
            status: 'acknowledged',
            ts: today.subtract(const Duration(hours: 1)),
            title: '🆘 長輩開口求救',
            desc: '長輩曾透過語音助理（小嘎）開口求救。',
            hasLocation: true,
            locationAt: today,
          ),
        ]),
        dark: false,
      );
      expect(find.text('🆘 長輩開口求救'), findsNWidgets(2));
      expect(find.text('查看位置'), findsOneWidget);
      expect(find.textContaining('監視'), findsNothing);
      expect(find.textContaining('跌倒'), findsNothing);
      // 所有可按的元件（按鈕／膠囊）文字都不含「監視」。
      final tappableTexts = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is GestureDetector || w is InkWell || w is PopupMenuButton || w is TextButton),
        matching: find.textContaining('監視'),
      );
      expect(tappableTexts, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
