// ★ 2026-10-07 交接 B1：「長輩檔案」「對話偏好」兩頁的 widget 測試。
//
// 驗證：
// 1. 從後端 `{status, data}` 的 data 讀取（interests 是 List、語氣／篇幅是真值）。
// 2. 只送有改過的欄位（部分更新）。
// 3. 失敗時顯示後端真實原因、不顯示成功訊息，也不離開頁面。
// 4. 360×640、字級 1.3 倍不溢位。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/screens/family/elder_basic_profile_screen.dart';
import 'package:flutter_application_1/screens/family/elder_profile_shared.dart';
import 'package:flutter_application_1/screens/family/elder_talk_preference_screen.dart';
import 'package:flutter_application_1/services/api/elder_data_api.dart';

/// 記錄所有呼叫的假資料來源。
class FakeGateway {
  Map<String, dynamic> profile;
  Map<String, dynamic> saveResult = {'status': 'success', 'data': {}};
  List<Map<String, dynamic>> topics;
  Map<String, dynamic>? addResult;
  Map<String, dynamic>? deleteResult;

  final List<Map<String, dynamic>> saves = [];
  final List<List<String>> adds = [];
  final List<int> deletes = [];
  int loads = 0;

  FakeGateway({required this.profile, List<Map<String, dynamic>>? topics})
      : topics = topics ?? [];

  ElderProfileGateway get gateway => ElderProfileGateway(
        load: (uid) async {
          loads++;
          return profile;
        },
        save: (uid, fields) async {
          saves.add(Map<String, dynamic>.from(fields));
          return saveResult;
        },
        listTopics: (id) async => {'status': 'success', 'data': List.of(topics)},
        addTopic: (id, kw, type) async {
          adds.add([id, kw, type]);
          final r = addResult ?? {'status': 'success', 'data': {}};
          if (r['status'] == 'success') {
            topics.add({
              'topic_id': 100 + topics.length,
              'elder_id': id,
              'keyword': kw,
              'topic_type': type,
            });
          }
          return r;
        },
        deleteTopic: (tid) async {
          deletes.add(tid);
          final r = deleteResult ?? {'status': 'success', 'data': {}};
          if (r['status'] == 'success') {
            topics.removeWhere((t) => t['topic_id'] == tid);
          }
          return r;
        },
      );
}

Map<String, dynamic> okProfile(Map<String, dynamic> data) =>
    {'status': 'success', 'data': data};

final _elderBase = <String, dynamic>{
  'user_id': 2,
  'user_name': '宇璿',
  'elder_id': '6160',
  'elder_name': '宇璿',
  'appellation': '奶奶',
  'gender': 'F',
  'age': 78,
  'location': '臺北市大安區',
  'residence_city': '臺北市',
  'residence_district': '大安區',
  'chronic_diseases': '高血壓',
  'medication_notes': '早餐後降血壓藥',
  'ai_emotion_tone': 80,
  'ai_text_verbosity': 20,
  'heartbeat_frequency': 60,
  'interests': ['鄧麗君', '園藝'],
};

const _elderArgs = {'user_id': 2, 'user_name': '宇璿'};

/// 用一個按鈕 push 目標頁，這樣儲存成功的 Navigator.pop 才有地方回。
Widget harness(Widget Function() page) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> openPage(WidgetTester tester, Widget Function() page) async {
  // 功能測試用高螢幕，整頁都在可視範圍內，不必捲動（溢位測試另用 360x640）。
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(page));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('長輩檔案頁', () {
    Widget page(FakeGateway g) =>
        ElderBasicProfileScreen(elderData: _elderArgs, gateway: g.gateway);

    testWidgets('從 data 讀取並顯示真實值', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase));
      await openPage(tester, () => page(g));
      expect(find.text('長輩檔案'), findsOneWidget);
      expect(find.widgetWithText(TextField, '宇璿'), findsOneWidget);
      expect(find.widgetWithText(TextField, '78'), findsOneWidget);
      expect(find.widgetWithText(TextField, '高血壓'), findsOneWidget);
      expect(find.widgetWithText(TextField, '早餐後降血壓藥'), findsOneWidget);
      expect(find.text('臺北市'), findsOneWidget);
      expect(find.text('大安區'), findsOneWidget);
      final female = tester.widget<ChoiceChip>(find.byKey(const ValueKey('gender_F')));
      expect(female.selected, isTrue);
    });

    testWidgets('只改年齡 → 只送 age', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase));
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(1), '80');
      await tapVisible(tester, find.byKey(const ValueKey('save_basic_profile')));
      expect(g.saves, [
        {'age': 80}
      ]);
      expect(find.text('長輩檔案已更新'), findsOneWidget);
    });

    testWidgets('改姓名與用藥 → 只送 user_name 與 medication_notes', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase));
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(0), '王宇璿');
      await tester.enterText(find.byType(TextField).at(3), '早晚各一顆');
      await tapVisible(tester, find.byKey(const ValueKey('save_basic_profile')));
      expect(g.saves.single, {'user_name': '王宇璿', 'medication_notes': '早晚各一顆'});
    });

    testWidgets('沒有變更不呼叫後端', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase));
      await openPage(tester, () => page(g));
      await tapVisible(tester, find.byKey(const ValueKey('save_basic_profile')));
      expect(g.saves, isEmpty);
      expect(find.text('沒有需要儲存的變更'), findsOneWidget);
    });

    testWidgets('清空欄位會明確提示，不送出、不假成功', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase));
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(2), '');
      await tapVisible(tester, find.byKey(const ValueKey('save_basic_profile')));
      expect(g.saves, isEmpty);
      expect(find.textContaining('無法清空'), findsOneWidget);
      expect(find.text('長輩檔案已更新'), findsNothing);
    });

    testWidgets('儲存失敗顯示後端原因、不顯示成功、留在頁面', (tester) async {
      final g = FakeGateway(profile: okProfile(_elderBase))
        ..saveResult = {'status': 'error', 'message': '年齡必須介於 1 到 120 之間'};
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(1), '90');
      await tapVisible(tester, find.byKey(const ValueKey('save_basic_profile')));
      expect(find.textContaining('年齡必須介於 1 到 120 之間'), findsOneWidget);
      expect(find.text('長輩檔案已更新'), findsNothing);
      expect(find.byKey(const ValueKey('save_basic_profile')), findsOneWidget);
    });

    testWidgets('讀取失敗顯示原因與重新載入，不顯示空表單', (tester) async {
      final g = FakeGateway(profile: {'status': 'error', 'message': '連線逾時，請檢查網路'});
      await openPage(tester, () => page(g));
      expect(find.text('連線逾時，請檢查網路'), findsOneWidget);
      expect(find.byKey(const ValueKey('save_basic_profile')), findsNothing);
      g.profile = okProfile(_elderBase);
      await tester.tap(find.text('重新載入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(TextField, '宇璿'), findsOneWidget);
    });

    testWidgets('360x640、字級 1.3 倍不溢位', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final g = FakeGateway(
        profile: okProfile({
          ..._elderBase,
          'elder_name': '一個非常非常長的長輩姓名用來測試溢位狀況是否會發生',
          'chronic_diseases': '高血壓、糖尿病、' * 12,
        }),
      );
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: harness(() => ElderBasicProfileScreen(
              elderData: _elderArgs,
              gateway: g.gateway,
              onUnbind: () {},
            )),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 小螢幕捲到底，儲存鈕要點得到（沒有變更 → 提示訊息）。
      await tester.tap(find.byKey(const ValueKey('save_basic_profile')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
      expect(find.text('沒有需要儲存的變更'), findsOneWidget);
    });
  });

  group('對話偏好頁', () {
    Widget page(FakeGateway g) =>
        ElderTalkPreferenceScreen(elderData: _elderArgs, gateway: g.gateway);

    FakeGateway gw() => FakeGateway(profile: okProfile(_elderBase), topics: [
          {'topic_id': 1, 'elder_id': '6160', 'keyword': '孫子', 'topic_type': 'priority'},
          {'topic_id': 2, 'elder_id': '6160', 'keyword': '過世的先生', 'topic_type': 'avoid'},
          {'topic_id': 3, 'elder_id': '6160', 'keyword': '醫院', 'topic_type': 'forbidden'},
        ]);

    testWidgets('從 data 讀取：interests 清單、真實語氣篇幅、頻率、話題', (tester) async {
      final g = gw();
      await openPage(tester, () => page(g));
      expect(find.widgetWithText(TextField, '奶奶'), findsOneWidget);
      expect(find.widgetWithText(TextField, '鄧麗君，園藝'), findsOneWidget);
      expect(tester.widget<Slider>(find.byKey(const ValueKey('tone_slider'))).value, 80);
      expect(tester.widget<Slider>(find.byKey(const ValueKey('verbosity_slider'))).value, 20);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('heartbeat_60'))).selected, isTrue);
      expect(find.text('孫子'), findsOneWidget);
      expect(find.text('過世的先生'), findsOneWidget);
      expect(find.text('醫院'), findsOneWidget);
    });

    testWidgets('語氣篇幅沒資料時顯示尚未設定，沒動滑桿就不送', (tester) async {
      final g = FakeGateway(
        profile: okProfile({..._elderBase}..remove('ai_emotion_tone')..remove('ai_text_verbosity')),
      );
      await openPage(tester, () => page(g));
      expect(find.text('尚未設定'), findsWidgets);
      await tester.enterText(find.byType(TextField).at(0), '阿嬤');
      await tapVisible(tester, find.byKey(const ValueKey('save_talk_pref')));
      expect(g.saves.single, {'appellation': '阿嬤'});
    });

    testWidgets('只改稱呼、頻率 → 只送兩個欄位', (tester) async {
      final g = gw();
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(0), '阿嬤');
      await tapVisible(tester, find.byKey(const ValueKey('heartbeat_120')));
      await tapVisible(tester, find.byKey(const ValueKey('save_talk_pref')));
      expect(g.saves.single, {'appellation': '阿嬤', 'heartbeat_frequency': 120});
      expect(find.textContaining('對話偏好已更新'), findsOneWidget);
    });

    testWidgets('關閉主動關懷送 0；興趣以逗號字串送出', (tester) async {
      final g = gw();
      await openPage(tester, () => page(g));
      await tapVisible(tester, find.byKey(const ValueKey('heartbeat_0')));
      await tester.enterText(find.byType(TextField).at(1), '鄧麗君、園藝、泡茶');
      await tapVisible(tester, find.byKey(const ValueKey('save_talk_pref')));
      expect(g.saves.single, {'heartbeat_frequency': 0, 'interests': '鄧麗君,園藝,泡茶'});
    });

    testWidgets('儲存失敗顯示後端原因、不顯示成功', (tester) async {
      final g = gw()
        ..saveResult = {'status': 'error', 'detail': '語氣與篇幅設定必須介於 0 到 100 之間'};
      await openPage(tester, () => page(g));
      await tester.enterText(find.byType(TextField).at(0), '阿嬤');
      await tapVisible(tester, find.byKey(const ValueKey('save_talk_pref')));
      expect(find.textContaining('語氣與篇幅設定必須介於 0 到 100 之間'), findsOneWidget);
      expect(find.textContaining('對話偏好已更新'), findsNothing);
    });

    testWidgets('新增話題呼叫 addTopic（priority）並重新讀清單', (tester) async {
      final g = gw();
      await openPage(tester, () => page(g));
      await tester.enterText(find.byKey(const ValueKey('topic_input_priority')), '園藝');
      await tapVisible(tester, find.byKey(const ValueKey('topic_add_priority')));
      expect(g.adds, [
        ['6160', '園藝', 'priority']
      ]);
      expect(find.text('園藝'), findsWidgets);
    });

    testWidgets('新增話題失敗顯示原因', (tester) async {
      final g = gw()..addResult = {'status': 'error', 'message': '伺服器忙碌'};
      await openPage(tester, () => page(g));
      await tester.enterText(find.byKey(const ValueKey('topic_input_avoid')), '天氣');
      await tapVisible(tester, find.byKey(const ValueKey('topic_add_avoid')));
      expect(find.textContaining('伺服器忙碌'), findsOneWidget);
    });

    testWidgets('刪除話題呼叫 deleteTopic 並移除', (tester) async {
      final g = gw();
      await openPage(tester, () => page(g));
      final chip = find.byKey(const ValueKey('topic_1'));
      final del = find.descendant(of: chip, matching: find.byType(Icon));
      await tester.tap(del);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.deletes, [1]);
      expect(find.text('孫子'), findsNothing);
    });

    testWidgets('360x640、字級 1.3 倍不溢位', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final g = FakeGateway(
        profile: okProfile({..._elderBase, 'heartbeat_frequency': 45}),
        topics: [
          for (var i = 0; i < 6; i++)
            {
              'topic_id': i + 1,
              'elder_id': '6160',
              'keyword': '一個很長很長的話題關鍵字用來測試換行$i',
              'topic_type': ['priority', 'avoid', 'forbidden'][i % 3],
            },
        ],
      );
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: harness(() => ElderTalkPreferenceScreen(
              elderData: _elderArgs,
              gateway: g.gateway,
            )),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ★ 2026-10-07 交接 話題隱私：GET 要帶 elder_id，不再整包抓回來前端過濾。
  test('getTalkTopics 的 GET 帶 elder_id 參數', () async {
    Uri? seen;
    await http.runWithClient(() async {
      final r = await ElderDataApi.getTalkTopics('6160');
      expect(r['status'], 'success');
      expect((r['data'] as List).length, 1);
    }, () => MockClient((req) async {
          seen = req.url;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': [
                {'topic_id': 1, 'elder_id': '6160', 'keyword': '孫子', 'topic_type': 'priority'},
                {'topic_id': 2, 'elder_id': '9999', 'keyword': '別人的', 'topic_type': 'forbidden'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }));
    expect(seen!.path, endsWith('/ai/topics'));
    expect(seen!.queryParameters['elder_id'], '6160');
  });
}
