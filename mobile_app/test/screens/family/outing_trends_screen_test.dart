// 外出趨勢畫面：以 MockClient 餵固定回應，驗證各狀態與窄螢幕下不溢位
// （任何 RenderFlex 溢位在測試中都會變成例外而讓測試失敗，對應鐵律 #14）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/screens/family/outing_trends_screen.dart';

List<Map<String, dynamic>> _days(int n, {bool hasHome = true, int points = 5}) {
  final today = DateTime.now();
  return List.generate(n, (i) {
    final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: n - 1 - i));
    return {
      'date': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'distance_m': points == 0 ? 0 : 1200 * (i % 5),
      'outing_count': hasHome ? (points == 0 ? 0 : i % 3) : null,
      'outside_minutes': hasHome ? (points == 0 ? 0 : 45 * (i % 4)) : null,
      'point_count': points,
    };
  });
}

MockClient _client(Map<String, dynamic> Function(Uri) dataFor) => MockClient((req) async {
      return http.Response(
        jsonEncode({'status': 'success', 'data': dataFor(req.url)}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

Future<void> _pump(WidgetTester tester, MockClient client) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(const MaterialApp(
      home: OutingTrendsScreen(elderId: 'E001', userId: 1, elderName: '陳阿嬤'),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }, () => client);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('有家：顯示摘要與三張圖、今天標示，窄螢幕不溢位', (tester) async {
    await _pump(
      tester,
      _client((u) => {'sharing_enabled': true, 'has_home': true, 'days': _days(7)}),
    );
    expect(find.text('外出趨勢'), findsOneWidget);
    expect(find.textContaining('本週平均每天外出'), findsOneWidget);
    expect(find.text('每日移動距離'), findsOneWidget);
    expect(find.text('每日外出次數'), findsOneWidget);
    expect(find.text('每日在外時間'), findsOneWidget);
    expect(find.text('今天（統計中）'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有家：外出次數顯示引導卡與設定按鈕', (tester) async {
    await _pump(
      tester,
      _client((u) => {'sharing_enabled': true, 'has_home': false, 'days': _days(7, hasHome: false)}),
    );
    expect(find.text('設定「家」之後就能看到外出次數與在外時間'), findsOneWidget);
    expect(find.text('設定常去地點'), findsOneWidget);
    expect(find.textContaining('本週平均每天移動'), findsOneWidget);
    expect(find.textContaining('平均每天外出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('長輩關閉位置分享', (tester) async {
    await _pump(tester, _client((u) => {'sharing_enabled': false}));
    expect(find.text('長輩已關閉位置分享'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整段期間沒有定位資料', (tester) async {
    await _pump(
      tester,
      _client((u) => {'sharing_enabled': true, 'has_home': true, 'days': _days(7, points: 0)}),
    );
    expect(find.text('這段期間沒有定位資料'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切到 30 天：帶 days=30 並顯示「近 30 天」摘要，不溢位', (tester) async {
    final requested = <String>[];
    final client = _client((u) {
      requested.add(u.toString());
      final days = int.parse(u.queryParameters['days']!);
      return {'sharing_enabled': true, 'has_home': true, 'days': _days(days)};
    });
    await _pump(tester, client);
    await http.runWithClient(() async {
      await tester.tap(find.text('30 天'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }, () => client);
    expect(requested.last, contains('days=30'));
    expect(requested.last, contains('tz_offset='));
    expect(find.textContaining('近 30 天平均每天外出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
