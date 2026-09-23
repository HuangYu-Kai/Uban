// 第五十二輪 F2：家屬端「警示中心」重新設計回歸測試。
//
// 使用者原話：「警示中心的警示紀錄若是已經結案就不應該再擁有誤報等按鍵
// 能按，並重新設計回報按鈕，將回報、待處理、誤報用一個按鍵解決...此外，
// 將警示紀錄改以週、月、所有的時間表呈現」。對應本檔三組測試：
//   (a) 已結案（status == 'resolved'）的警示紀錄項目找不到任何可按的
//       「誤報」／動作控制項，只有唯讀徽章＋說明文字（任務 A）。
//   (b) 未結案（active／acknowledged）的項目只有一個動作控制項
//       （PopupMenuButton），點開後看得到「回報已處理」／「標記為誤報」
//       兩個選項（任務 B，取代原本兩個並排按鈕）。
//   (c) 警示紀錄清單上方有「本週／本月／全部」三個時間篩選鈕，且可切換
//       （任務 C 前端部分）。
//
// `_buildHistoryAlertCard`／`_buildAlertActionArea` 是 alert_center_screen.dart
// 的 library-private 方法，測試檔案（不同檔案＝不同 library）無法直接
// 呼叫；`AlertCenterScreen.activeAlerts` 餵的是即時 CCTV 警報，不是這裡要
// 驗證的持久化警示紀錄清單。因此本檔改用 alert_center_screen.dart 新增的
// `historyAlertItemsOverride` 測試專用注入點，讓 (a)(b) 兩組測試能直接
// 命中真正的 `_buildHistoryAlertCard` 實作，而不必在測試檔裡另外手刻一份
// 容易與正式程式碼漂移不同步的相似結構。(c) 不需要注入資料，走真實網路
// 失敗路徑即可——沙盒沒有對應網路，DNS 查詢快速失敗，既有 try/catch 會
// 吞掉、不影響篩選器本身的渲染（比照 family_data_tab_test.dart 的既有
// 作法：`await tester.pump(const Duration(seconds: 2))` 取代
// `pumpAndSettle()`，避免真的卡在逾時等待）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/alert_center_screen.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection
    // （比照 family_data_tab_test.dart 的既有作法）。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    // 空白 mock：SharedPreferences 讀不到 'caregiver_id'，_loadHistoryAlerts
    // 會略過 getEmergencyAlerts 這段抓取（見該方法既有的既定行為），不影響
    // 本檔測試——(a)(b) 兩組直接注入 historyAlertItemsOverride，完全不走
    // 這條網路路徑；(c) 只驗證篩選器本身，不依賴這段抓取的成功與否。
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> makeItem({
    required String id,
    required int alertId,
    String status = 'active',
    String resolutionSource = '',
    bool isFalseAlarm = false,
  }) {
    return <String, dynamic>{
      'id': id,
      'title': '🚨 跌倒緊急警報',
      'desc': '測試用警示描述（發生於 09/20 10:00）',
      'level': 'high',
      'icon': Icons.warning_amber_rounded,
      'sortTs': DateTime.now(),
      'alertId': alertId,
      'isFalseAlarm': isFalseAlarm,
      'status': status,
      'resolution_source': resolutionSource,
    };
  }

  Widget buildHarness({List<Map<String, dynamic>>? historyItems}) {
    return MaterialApp(
      home: AlertCenterScreen(
        elderName: '陳阿嬤',
        elderId: 1,
        elderRoomId: 'E001',
        historyAlertItemsOverride: historyItems,
      ),
    );
  }

  // 任一頁面上都可能出現的 PopupMenuButton，只有本畫面的動作控制項會用到
  // ——用 `is PopupMenuButton`（不帶泛型引數）比對，不需要引用私有的
  // `_AlertMenuAction` 型別即可從測試檔精準命中。
  Finder popupMenuFinder() =>
      find.byWidgetPredicate((widget) => widget is PopupMenuButton);

  group('任務 A：已結案不得再有動作鍵', () {
    testWidgets('status=resolved（家屬回報）找不到任何可按的動作控制項',
        (tester) async {
      await tester.pumpWidget(buildHarness(historyItems: [
        makeItem(
          id: 'alert:1',
          alertId: 1,
          status: 'resolved',
          resolutionSource: 'family',
        ),
      ]));
      await tester.pump(const Duration(seconds: 1));

      // 唯讀徽章與「不能再更改」說明文字都要在。
      expect(find.text('已回報處理完畢'), findsOneWidget);
      expect(find.text('已結案的紀錄不能再更改'), findsOneWidget);

      // 不應該有任何可點擊的動作控制項，也不應該殘留舊版按鈕文案。
      expect(popupMenuFinder(), findsNothing);
      expect(find.text('這是誤報'), findsNothing);
      expect(find.text('標記為誤報'), findsNothing);
      expect(find.text('回報已處理'), findsNothing);
    });

    testWidgets('status=resolved 且來源為 false_alarm 時，徽章顯示「已標記為誤報」且同樣沒有動作控制項',
        (tester) async {
      // 這是使用者原話最直接對應的情境：曾經被標記過誤報、現已結案。
      await tester.pumpWidget(buildHarness(historyItems: [
        makeItem(
          id: 'alert:2',
          alertId: 2,
          status: 'resolved',
          resolutionSource: 'false_alarm',
          isFalseAlarm: true,
        ),
      ]));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('已標記為誤報'), findsOneWidget);
      expect(find.text('已結案的紀錄不能再更改'), findsOneWidget);
      expect(popupMenuFinder(), findsNothing);
    });

    testWidgets('canary：同一份資料把 status 改成 active，動作控制項應該要能出現',
        (tester) async {
      // 證明上面兩項「resolved 找不到動作控制項」不是因為測試沙盒本來就
      // 畫不出 PopupMenuButton（例如被某種全域設定擋住）——同一筆資料只
      // 改 status，控制項就應該要能出現。
      await tester.pumpWidget(buildHarness(historyItems: [
        makeItem(id: 'alert:1', alertId: 1, status: 'active'),
      ]));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('已回報處理完畢'), findsNothing);
      expect(popupMenuFinder(), findsOneWidget);
    });
  });

  group('任務 B：三個動作收斂成單一控制項', () {
    testWidgets('未結案項目只有一個動作控制項，本體顯示狀態、點開後看得到兩個選項',
        (tester) async {
      await tester.pumpWidget(buildHarness(historyItems: [
        makeItem(id: 'alert:3', alertId: 3, status: 'acknowledged'),
      ]));
      await tester.pump(const Duration(seconds: 1));

      // 剛好只有一個動作控制項（不是兩個並排按鈕）。
      expect(popupMenuFinder(), findsOneWidget);
      // 本體顯示目前狀態。
      expect(find.text('處理中'), findsOneWidget);

      // 點開下拉選單。
      await tester.tap(find.text('處理中'));
      await tester.pumpAndSettle();

      expect(find.text('回報已處理'), findsOneWidget);
      expect(find.text('標記為誤報'), findsOneWidget);

      // 不提供「退回待處理」——resolved 是刻意鎖死的終態，明確斷言選單裡
      // 沒有任何「退回」字樣的選項，避免日後被誤加回去。
      expect(find.textContaining('退回'), findsNothing);
    });

    testWidgets('status=active（尚未處理）本體顯示「待處理」', (tester) async {
      await tester.pumpWidget(buildHarness(historyItems: [
        makeItem(id: 'alert:4', alertId: 4, status: 'active'),
      ]));
      await tester.pump(const Duration(seconds: 1));

      expect(popupMenuFinder(), findsOneWidget);
      expect(find.text('待處理'), findsOneWidget);
      expect(find.text('處理中'), findsNothing);
    });
  });

  group('任務 C：時間範圍篩選', () {
    testWidgets('本週／本月／全部三個篩選鈕存在且可切換，不拋出例外', (tester) async {
      await tester.pumpWidget(buildHarness());
      // 不注入 historyItems：走真實網路路徑，沙盒無對應網路會以 DNS 失敗
      // 快速收斂到既有 catch 分支，不影響篩選器本身的渲染。
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('本週'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('本月'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('本週'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('全部'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('本週'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('canary：篩選鈕的文字斷言真的會依實際畫面內容失敗（刻意找不存在的字串）',
        (tester) async {
      // 證明上面 findsOneWidget 系列斷言不是恆真——故意找一個不可能出現在
      // 這個畫面上的字串，必須是 findsNothing。
      await tester.pumpWidget(buildHarness());
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.text('這段文字不可能出現在警示中心畫面上_canary'),
        findsNothing,
      );
    });
  });
}
