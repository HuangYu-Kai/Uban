// 第五十二輪：家屬端首頁「最新警示」即時推播的滑動關閉鍵格式回歸測試。
//
// 背景：任務原始假設是「即時推播（cctv-alert）的滑動關閉複合鍵固定是
// live:$type:$deviceId:$liveTs，不會被 family_main_screen.dart 的
// _handleAlertItemDismissed 持久化，導致重開 App 後又出現」。逐行追查
// HomeAlertPreviewCard.build()（liveItemId 組法）與後端
// yolo_alert_dispatcher.py（_insert_alert / _broadcast_alert /
// _build_push_payload）後發現：複合鍵組法**已經**優先使用
// `alert:$alert_id`，只有在 alert_id 缺漏時才退回 `live:...`；而後端所有
// 共用 dispatch_yolo_alert 派送鏈的警報型別（fall/crawl/lying_down/
// prolonged_inactivity/sos_voice，含長輩語音求救 notify_family_SOS）都保證
// 帶 alert_id（Socket 版 snake_case `alert_id`、FCM 版 camelCase
// `alertId`）。family_main_screen.dart::_handleCctvAlert 甚至在 alert_id
// 解析失敗時直接 return，根本不會把該筆警示塞進 _activeAlerts。
//
// 因此「即時推播用 live: 鍵」這個假設在目前程式碼下不成立，本檔未對
// family_main_screen.dart / home_alert_preview_card.dart 做任何行為變更。
// 這份測試把「有 alert_id 時鍵一定是 alert:<id>」釘成回歸測試，避免下一輪
// 又重新調查同一個結論，也讓「萬一日後真的退化成沒有 alert_id」的情況會
// 被抓到。
//
// 兩個案例互為 canary：只驗證「有 alert_id 會變成 alert:」不足以證明判斷式
// 真的按 alert_id 是否存在分流（邏輯被整個拆掉、恆回傳固定字串也可能巧合
// 通過）；同時驗證「沒有 alert_id 會退回 live:」才能證明兩條分支都在運作。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection
    // （比照 family_data_tab_test.dart 的既有作法）。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<Set<Key?>> pumpAndCollectDismissibleKeys(
    WidgetTester tester,
    List<Map<String, dynamic>> activeAlerts,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAlertPreviewCard(
            // currentElder 刻意留預設 null：build() 的長輩過濾邏輯在
            // currentElderIdStr == null 時對全部項目直接放行（見
            // home_alert_preview_card.dart build() 開頭的迴圈），不需要
            // 另外建構 Elder 物件即可獨立測試複合鍵組法。
            activeAlerts: activeAlerts,
          ),
        ),
      ),
    );
    // ★ 卡片內含 flutter_animate 進場動畫（`_AnimateState.initState` 會排一個
    //   0 秒延遲的 Timer 啟動動畫），單一 `pump()` 不會讓它跑完；用
    //   `pumpAndSettle()` 把動畫排空，否則 `tester.pumpWidget` 建立的
    //   widget 樹在測試結束時仍有待處理 Timer，會被測試框架判定為洩漏而報錯
    //   （與本測試要驗證的複合鍵邏輯無關，純粹是動畫元件本身的既有行為）。
    await tester.pumpAndSettle();
    return tester
        .widgetList<Dismissible>(find.byType(Dismissible))
        .map((d) => d.key)
        .toSet();
  }

  testWidgets('有 alert_id 時，即時警示的滑動關閉鍵是 alert:<id>（可被持久化）',
      (tester) async {
    final keys = await pumpAndCollectDismissibleKeys(tester, [
      {
        'alert_id': '9001',
        'alert_type': 'fall',
        'device_id': 'dev-abc',
        'timestamp': '1758600000',
      },
    ]);

    expect(keys, contains(const ValueKey('alert:9001')));
    // canary 的另一半：確認沒有退回易漂移的 live: 複合鍵格式。
    expect(
      keys.any(
          (k) => k is ValueKey && (k.value as String).startsWith('live:')),
      isFalse,
    );
  });

  testWidgets('缺 alert_id 時才退回 live: 複合鍵（canary：證明判斷式真的有分流）',
      (tester) async {
    final keys = await pumpAndCollectDismissibleKeys(tester, [
      {
        // 刻意不帶 alert_id / alertId，模擬後端理論上漏帶穩定 PK 的情境。
        'alert_type': 'fall',
        'device_id': 'dev-abc',
        'timestamp': '1758600000',
      },
    ]);

    expect(
      keys,
      contains(const ValueKey('live:fall:dev-abc:1758600000')),
    );
    expect(
      keys.any(
          (k) => k is ValueKey && (k.value as String).startsWith('alert:')),
      isFalse,
    );
  });
}
