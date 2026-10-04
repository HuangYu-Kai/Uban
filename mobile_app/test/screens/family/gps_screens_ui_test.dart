// 家屬端 GPS 三個畫面（移動軌跡／常去地點／外出趨勢）新設計 UI 回歸測試。
//
// 目的：360×640、textScaler 1.3、家屬主題淺／深色下不得出現 RenderFlex 溢位
// （CLAUDE.md §3.1 第 14 條；測試中任何溢位都會變成例外而讓測試失敗）。
//
// 做法：
//   * OutingTrendsScreen／ElderPlacesScreen／ElderLocationMapScreen 都以 MockClient
//     餵固定回應，直接 pump 真實畫面（地圖圖磚請求回 404，不打網路）。
//   * gps_ui.dart 的純外觀元件（時間軸列、狀態列、警示卡、空狀態、日期膠囊、規則列…）
//     以超長字串另外單獨測一次，確保「動態字串可收縮」。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/elder_location_map_screen.dart';
import 'package:flutter_application_1/screens/family/elder_places_screen.dart';
import 'package:flutter_application_1/screens/family/outing_trends_screen.dart';
import 'package:flutter_application_1/screens/family/widgets/fam_ui.dart';
import 'package:flutter_application_1/screens/family/widgets/gps_ui.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

const _longName = '王大明爸爸這個名字故意取得很長很長很長很長很長很長很長很長';

/// 後端回應包裝：`/location/...` 一律 200，其他（圖磚）回 404。
MockClient _api(Map<String, dynamic>? Function(Uri) dataFor) => MockClient((req) async {
      if (!req.url.path.contains('/location/')) {
        return http.Response('', 404);
      }
      final data = dataFor(req.url);
      if (data == null) return http.Response('{}', 500);
      return http.Response(
        jsonEncode({'status': 'success', 'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

String _iso(DateTime t) => '${t.toUtc().toIso8601String().substring(0, 19)}Z';

List<Map<String, dynamic>> _days(int n, {bool hasHome = true}) {
  final today = DateTime.now();
  return List.generate(n, (i) {
    final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: n - 1 - i));
    return {
      'date': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'distance_m': 1200 * (i % 5),
      'outing_count': hasHome ? i % 3 : null,
      'outside_minutes': hasHome ? 45 * (i % 4) : null,
      'point_count': 5,
    };
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required bool dark,
  required MockClient client,
  double scale = 1.3,
  int pumps = 4,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({FamilyThemeController.prefsKey: dark});
  FamilyThemeController.instance.value = dark;
  // 同一個測試內多次呼叫時先清掉舊畫面，State 才會重新載入。
  await tester.pumpWidget(const SizedBox());
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ));
    for (var i = 0; i < pumps; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }, () => client);
}

/// 純元件用的外殼：家屬主題＋指定縮放，內容放在有高度的 Scaffold 裡。
Future<void> _pumpWidget(
  WidgetTester tester,
  Widget child, {
  required bool dark,
  double scale = 1.3,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: FamilyTheme.buildTheme(_Ctx(), isDark: dark),
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(body: SafeArea(child: SingleChildScrollView(child: child))),
  ));
  await tester.pump();
}

class _Ctx extends Fake implements BuildContext {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final combos = <({bool dark, String name})>[
    (dark: false, name: '淺色'),
    (dark: true, name: '深色'),
  ];

  // ───────────────────────── 外出趨勢 ─────────────────────────
  group('OutingTrendsScreen（360×640、1.3 倍字）', () {
    for (final cb in combos) {
      testWidgets('${cb.name}：有家 7 天', (tester) async {
        await _pump(
          tester,
          const OutingTrendsScreen(elderId: 'E1', userId: 1, elderName: _longName),
          dark: cb.dark,
          client: _api((u) => {'sharing_enabled': true, 'has_home': true, 'days': _days(7)}),
        );
        expect(find.text('外出趨勢'), findsOneWidget);
        expect(find.text('每日移動距離'), findsOneWidget);
        expect(find.text('每日外出次數'), findsOneWidget);
        expect(find.text('每日在外時間'), findsOneWidget);
        expect(find.text('今天（統計中）'), findsNWidgets(3));
        expect(find.text('平均每天在外'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：沒有家（引導卡、不顯示次數）', (tester) async {
        await _pump(
          tester,
          const OutingTrendsScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api((u) => {'sharing_enabled': true, 'has_home': false, 'days': _days(7, hasHome: false)}),
        );
        expect(find.text('設定常去地點'), findsOneWidget);
        expect(find.text('平均每天外出'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：30 天、分享關閉', (tester) async {
        final client = _api((u) {
          final days = int.tryParse(u.queryParameters['days'] ?? '7') ?? 7;
          return {'sharing_enabled': true, 'has_home': true, 'days': _days(days)};
        });
        await _pump(tester, const OutingTrendsScreen(elderId: 'E1', userId: 1),
            dark: cb.dark, client: client);
        await http.runWithClient(() async {
          await tester.tap(find.text('30 天'));
          for (var i = 0; i < 3; i++) {
            await tester.pump(const Duration(milliseconds: 600));
          }
        }, () => client);
        expect(find.textContaining('近 30 天平均每天外出'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _pump(tester, const OutingTrendsScreen(elderId: 'E1', userId: 1),
            dark: cb.dark, client: _api((u) => {'sharing_enabled': false}));
        expect(find.text('長輩已關閉位置分享'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ───────────────────────── 常去地點 ─────────────────────────
  Map<String, dynamic>? places(Uri u, {bool hasHome = true}) {
    final p = u.path;
    if (p.contains('/location/places/')) {
      return {
        'places': [
          if (hasHome)
            {'id': 1, 'name': '家', 'latitude': 25.03, 'longitude': 121.5, 'radius_m': 150, 'is_home': true},
          {'id': 2, 'name': _longName, 'latitude': 25.04, 'longitude': 121.51, 'radius_m': 300, 'is_home': false},
        ],
      };
    }
    if (p.contains('/location/alert-settings/')) {
      return {
        'has_home': hasHome,
        'settings': {
          'late_return_enabled': true,
          'late_return_time': '21:00',
          'no_update_enabled': true,
          'no_update_start': '08:00',
          'no_update_end': '20:00',
          'no_update_hours': 3,
          'far_enabled': false,
          'far_km': 5,
        },
      };
    }
    return null;
  }

  group('ElderPlacesScreen（360×640、1.3 倍字）', () {
    for (final cb in combos) {
      testWidgets('${cb.name}：清單＋三條安心提醒', (tester) async {
        await _pump(
          tester,
          const ElderPlacesScreen(elderId: 'E1', userId: 1, elderName: _longName),
          dark: cb.dark,
          client: _api(places),
        );
        expect(find.text('常去地點'), findsOneWidget);
        expect(find.text('晚歸提醒'), findsOneWidget);
        expect(find.text('失聯提醒'), findsOneWidget);
        expect(find.text('遠離家提醒'), findsOneWidget);
        expect(find.text('21:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：沒設家時晚歸／遠離家停用並顯示提示', (tester) async {
        await _pump(
          tester,
          const ElderPlacesScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api((u) => places(u, hasHome: false)),
        );
        expect(find.text('先設定「家」才能使用'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：編輯地點面板（新增、長名稱、4 個半徑）', (tester) async {
        await _pump(
          tester,
          const ElderPlacesScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api(places),
        );
        // 點第二列（長名稱地點）開啟編輯面板。
        await tester.tap(find.text('半徑 300 公尺'));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(find.text('編輯地點'), findsOneWidget);
        expect(find.text('設為家'), findsOneWidget);
        expect(find.text('儲存'), findsOneWidget);
        expect(find.text('取消'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ───────────────────────── 移動軌跡（地圖頁） ─────────────────────────
  Map<String, dynamic>? mapData(Uri u, {bool sharing = true, bool withTrail = true}) {
    final p = u.path;
    final now = DateTime.now();
    if (p.contains('/location/current/')) {
      if (!sharing) return {'sharing_enabled': false};
      return {
        'sharing_enabled': true,
        'point': withTrail
            ? {
                'latitude': 25.0332,
                'longitude': 121.5654,
                'recorded_at': _iso(now.subtract(const Duration(minutes: 3))),
              }
            : null,
        'stale_after_ms': 30 * 60 * 1000,
        'device_status': 'service_disabled',
        'device_status_at': _iso(now.subtract(const Duration(minutes: 5))),
      };
    }
    if (p.contains('/location/trail/')) {
      return {
        'points': withTrail
            ? [
                for (var i = 0; i < 12; i++)
                  {
                    'latitude': 25.0300 + i * 0.0006,
                    'longitude': 121.5600 + i * 0.0006,
                    'recorded_at': _iso(now.subtract(Duration(minutes: 90 - i * 3))),
                    'accuracy_m': 10,
                  },
              ]
            : <Map<String, dynamic>>[],
        'cursor': 12,
      };
    }
    if (p.contains('/location/places/')) {
      return {
        'places': [
          {'id': 1, 'name': '家', 'latitude': 25.0300, 'longitude': 121.5600, 'radius_m': 150, 'is_home': true},
        ],
      };
    }
    return null;
  }

  group('ElderLocationMapScreen（360×640、1.3 倍字）', () {
    for (final cb in combos) {
      testWidgets('${cb.name}：地圖＋警示卡＋狀態列＋時間軸', (tester) async {
        await _pump(
          tester,
          const ElderLocationMapScreen(elderId: 'E1', userId: 1, elderName: _longName),
          dark: cb.dark,
          client: _api(mapData),
        );
        expect(find.text('移動軌跡'), findsOneWidget);
        expect(find.text('今天'), findsOneWidget);
        // 版權標示不得被拿掉。
        expect(find.textContaining('OpenStreetMap'), findsWidgets);
        // 定位被關掉的警示卡（`.mapwarn`）。
        expect(find.byType(GpsMapWarn), findsOneWidget);
        // 底部狀態列（`.mapstatus`），點擊開時間軸。
        expect(find.byType(GpsMapStatusBar), findsOneWidget);
        await tester.tap(find.byType(GpsMapStatusBar));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(find.text('今日行程'), findsOneWidget);
        expect(find.byType(GpsTimelineRow), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：分享關閉／無資料的 .mapempty', (tester) async {
        await _pump(
          tester,
          const ElderLocationMapScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api((u) => mapData(u, sharing: false)),
        );
        expect(find.text('長輩已關閉位置分享'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _pump(
          tester,
          const ElderLocationMapScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api((u) => mapData(u, withTrail: false)),
        );
        expect(find.text('尚無定位資料'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _pump(
          tester,
          const ElderLocationMapScreen(elderId: 'E1', userId: 1),
          dark: cb.dark,
          client: _api((u) => null),
        );
        expect(find.text('無法讀取位置資料'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ───────────────────────── gps_ui 純元件（超長字串） ─────────────────────────
  group('gps_ui 純元件：超長動態字串不溢位', () {
    const long = '這是一段故意寫得非常非常長的動態字串用來驗證窄螢幕下的收縮行為是否正確';
    for (final cb in combos) {
      testWidgets('${cb.name}：時間軸列（四種事件）', (tester) async {
        await _pumpWidget(
          tester,
          Column(
            children: [
              for (final k in GpsEventKind.values)
                GpsTimelineRow(
                  kind: k,
                  time: k == GpsEventKind.depart ? '08:12' : '08:12–09:30',
                  description: long,
                  ongoing: k == GpsEventKind.stay,
                  isFirst: k == GpsEventKind.depart,
                  isLast: k == GpsEventKind.gap,
                  onTap: () {},
                ),
            ],
          ),
          dark: cb.dark,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：狀態列、警示卡、空狀態、日期膠囊', (tester) async {
        await _pumpWidget(
          tester,
          Column(
            children: [
              const GpsMapStatusBar(title: long, subtitle: long, debugLine: long, onTap: null),
              GpsMapStatusBar(title: long, subtitle: long, stale: true, onTap: () {}),
              const GpsMapWarn(text: long),
              const GpsEmptyBlock(icon: Icons.location_off_rounded, title: long, message: long),
              GpsDatePill(label: '12/31', onPrev: null, onPick: () {}, onNext: () {}),
              Row(children: [
                Expanded(child: Container()),
                const GpsGlassButton(icon: Icons.my_location_rounded, tooltip: '目前位置', onTap: _noop),
              ]),
            ],
          ),
          dark: cb.dark,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('${cb.name}：地點列、規則列、摘要格、圖表標題與圖例', (tester) async {
        await _pumpWidget(
          tester,
          Column(
            children: [
              const GpsPlaceRow(name: long, subtitle: long, isHome: true, first: true),
              const GpsPlaceRow(name: long, subtitle: long, isHome: false),
              GpsRuleRow(
                title: long,
                body: [
                  gpsPlain('距離家超過'),
                  gpsInline('5', onTap: () {}),
                  gpsPlain(long),
                ],
                trailing: const SizedBox(width: 60, height: 36),
              ),
              Row(children: const [
                Expanded(child: GpsSumCell(label: long, value: '123.4', unit: '公里')),
                SizedBox(width: 8),
                Expanded(child: GpsSumCell(label: long, value: '—')),
                SizedBox(width: 8),
                Expanded(child: GpsSumCell(label: '平均每天在外', value: '12.5', unit: '小時')),
              ]),
              GpsChartHead(title: long, unit: '公里', swatch: Colors.blue),
              GpsLegend(color: Colors.blue),
              const FamSectionLabel('安心提醒'),
            ],
          ),
          dark: cb.dark,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

void _noop() {}
