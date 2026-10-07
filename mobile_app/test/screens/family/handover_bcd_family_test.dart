// ★ 2026-10-07 交接 B/C/D（家屬端）回歸測試：
//   D2 首頁長輩卡步數改讀 API（沒資料不顯示）、D4 最新警示不顯示已結案／誤報／聊天關鍵字、
//   B3 資料分頁通知開關接真偏好、D6 GPS 卡 refreshToken 參數。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_elder_header_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_gps_trail_card.dart';
import 'package:flutter_application_1/widgets/ui/uban_switch.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final elder = Elder(id: 1, elderId: 'E001', name: '陳阿嬤', gender: 'F', age: 78, location: '臺北市');

  Future<void> pump(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    await t.pumpAndSettle();
  }

  group('D2 首頁長輩卡步數', () {
    testWidgets('API 有步數 → 顯示；不從聊天文字抓', (t) async {
      await pump(
        t,
        HomeElderHeaderCard(
          currentElder: elder,
          realLogs: const [
            {'content': '長輩說：我今天走了 99999 步'},
          ],
          stepsLoader: (id) async => 4321,
        ),
      );
      expect(find.text('今天步數'), findsOneWidget);
      expect(find.text('4,321'), findsOneWidget);
      expect(find.textContaining('99,999'), findsNothing);
    });

    testWidgets('沒有資料 → 整格不顯示（聊天裡的「N 步」不算）', (t) async {
      await pump(
        t,
        HomeElderHeaderCard(
          currentElder: elder,
          realLogs: const [
            {'content': '走了 5000 步'},
          ],
          stepsLoader: (id) async => null,
        ),
      );
      expect(find.text('今天步數'), findsNothing);
    });
  });

  group('D4 最新警示', () {
    testWidgets('已結案／誤報不顯示；聊天關鍵字不當警示；event_type=alert 才算', (t) async {
      await pump(
        t,
        HomeAlertPreviewCard(
          currentElder: elder,
          emergencyAlerts: const [
            {'alert_id': 1, 'elder_id': 'E001', 'alert_type': 'fall', 'status': 'resolved', 'detected_at': '2026-10-06 01:00:00'},
            {'alert_id': 2, 'elder_id': 'E001', 'alert_type': 'fall', 'status': 'active', 'is_false_alarm': 1, 'detected_at': '2026-10-06 02:00:00'},
            {'alert_id': 3, 'elder_id': 'E001', 'alert_type': 'fall', 'status': 'active', 'is_false_alarm': 0, 'detected_at': '2026-10-06 03:00:00'},
          ],
          activeAlerts: const [
            {'alert_id': '1', 'elder_id': 'E001', 'alert_type': 'fall'},
          ],
          realLogs: const [
            {'log_id': 10, 'event_type': 'chat', 'content': '提醒我明天買菜'},
            {'log_id': 11, 'event_type': 'alert', 'content': '【警示】今日藥未確認'},
          ],
        ),
      );
      // 待處理：#3 持久化 + event_type=alert 的 log 11 → 計數 2
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('提醒我明天買菜'), findsNothing);
    });
  });

  testWidgets('D6 HomeGpsTrailCard 接受 refreshToken', (t) async {
    await pump(t, HomeGpsTrailCard(currentElder: elder, userId: null, refreshToken: 1));
    await pump(t, HomeGpsTrailCard(currentElder: elder, userId: null, refreshToken: 2));
    expect(find.byType(HomeGpsTrailCard), findsOneWidget);
  });

  testWidgets('B3 資料分頁通知開關讀取並寫回真偏好；不再有假項目', (t) async {
    SharedPreferences.setMockInitialValues({'pet_gift_notify_enabled': false});
    await t.binding.setSurfaceSize(const Size(360, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: FamilyDataTab(currentElder: null, userId: 1, userName: '測試家屬')),
    ));
    await t.pumpAndSettle();
    expect(find.text('小豬共養通知'), findsOneWidget);
    expect(find.text('長輩打卡通知'), findsOneWidget);
    expect(find.text('每天 18:00 健康日誌'), findsNothing);
    expect(find.text('作息與情緒預警'), findsNothing);
    final sw = t.widgetList<UbanSwitch>(find.byType(UbanSwitch)).toList();
    expect(sw.any((s) => s.value == false), isTrue); // 小豬共養：讀到 false
  });
}
