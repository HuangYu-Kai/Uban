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
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection
    // （比照 family_data_tab_test.dart 的既有作法）。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<Set<Key?>> pumpAndCollectDismissibleKeys(
    WidgetTester tester,
    List<Map<String, dynamic>> activeAlerts, {
    Set<String> dismissedAlertKeys = const {},
    bool dismissedKeysLoaded = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAlertPreviewCard(
            // currentElder 刻意留預設 null：build() 的長輩過濾邏輯在
            // currentElderIdStr == null 時對全部項目直接放行（見
            // home_alert_preview_card.dart build() 開頭的迴圈），不需要
            // 另外建構 Elder 物件即可獨立測試複合鍵組法。
            activeAlerts: activeAlerts,
            dismissedAlertKeys: dismissedAlertKeys,
            dismissedKeysLoaded: dismissedKeysLoaded,
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

  group('dismissedKeysLoaded 閘門（第五十二輪任務一：冷啟動競態）', () {
    // 背景：family_main_screen.dart::initState() 對 _loadDismissedAlertKeys()
    // 的呼叫沒有 await——App 冷啟動時，本卡片可能在那次非同步讀取完成
    // *之前* 就先畫一次，此時過濾用的 dismissedAlertKeys 還是空集合，導致
    // 使用者上次已經滑掉的警示重新閃現，幾百毫秒後讀取完成才被濾掉。修法是
    // 新增 dismissedKeysLoaded 旗標：為 false 時本卡片完全不渲染任何警示
    // 項目、也不顯示「目前沒有任何警示」（那句話在旗標為 false 時無法被
    // 驗證是否成立）。以下兩個測試直接釘住 HomeAlertPreviewCard 這個公開
    // 契約；家屬端實際的旗標管理（_dismissedKeysLoaded）是
    // _FamilyMainScreenState 的私有狀態，Dart 的 library 隱私規則使外部測試
    // 檔案無法直接存取，因此改用下方 _ColdStartHarness 重現同一種「initState
    // 不 await、旗標延遲翻正」的呼叫模式來驗證端對端行為。

    testWidgets(
      'dismissedKeysLoaded 為 false 時，即使 activeAlerts 已有資料也不渲染任何警示項目、'
      '也不顯示「目前沒有任何警示」',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HomeAlertPreviewCard(
                dismissedKeysLoaded: false,
                activeAlerts: [
                  {
                    'alert_id': '9001',
                    'alert_type': 'fall',
                    'device_id': 'dev-abc',
                    'timestamp': '1758600000',
                  },
                ],
              ),
            ),
          ),
        );
        // ★ 不可用 pumpAndSettle()：「載入中骨架」本身含一個不確定進度的
        //   CircularProgressIndicator，它的動畫永遠不會停止，pumpAndSettle()
        //   會因為「永遠有待處理的下一影格」而逾時掛住。改用帶固定時長的
        //   pump()，時長 > 卡片外層 Container 進場淡入動畫的 300ms 延遲 +
        //   400ms 時長，足以讓畫面穩定下來供斷言，又不必等到「零待處理影格」
        //   這個對本卡片而言不存在的狀態。
        await tester.pump(const Duration(milliseconds: 800));

        expect(find.byType(Dismissible), findsNothing);
        // 當下還不知道濾掉已讀警示後是否真的沒有項目，不可以宣稱「目前
        // 沒有任何警示」。
        expect(find.text('目前沒有任何警示'), findsNothing);
      },
    );

    testWidgets(
      'dismissedKeysLoaded 為 true 時，已滑掉的那筆被過濾、其餘警示照常顯示',
      (tester) async {
        final keys = await pumpAndCollectDismissibleKeys(
          tester,
          [
            {
              'alert_id': '9001',
              'alert_type': 'fall',
              'device_id': 'dev-abc',
              'timestamp': '1758600000',
            },
            {
              'alert_id': '9002',
              'alert_type': 'crawl',
              'device_id': 'dev-abc',
              'timestamp': '1758600001',
            },
          ],
          dismissedAlertKeys: const {'alert:9001'},
          dismissedKeysLoaded: true,
        );

        expect(keys, isNot(contains(const ValueKey('alert:9001'))));
        expect(keys, contains(const ValueKey('alert:9002')));
      },
    );

    testWidgets(
      '端對端：SharedPreferences 已滑掉紀錄配合可控延遲——讀取完成前不渲染、'
      '完成後正確過濾掉已滑掉的那筆',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'family_dismissed_alert_keys': jsonEncode({
            'alert:9001': DateTime.now().millisecondsSinceEpoch,
          }),
        });
        final gate = Completer<void>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _ColdStartHarness(
                gate: gate.future,
                activeAlerts: const [
                  {
                    'alert_id': '9001',
                    'alert_type': 'fall',
                    'device_id': 'dev-abc',
                    'timestamp': '1758600000',
                  },
                  {
                    'alert_id': '9002',
                    'alert_type': 'crawl',
                    'device_id': 'dev-abc',
                    'timestamp': '1758600001',
                  },
                ],
              ),
            ),
          ),
        );

        // gate 尚未放行 == SharedPreferences 讀取尚未完成：不得渲染任何
        // 警示項目，也不得顯示「目前沒有任何警示」。
        await tester.pump();
        expect(find.byType(Dismissible), findsNothing);
        expect(find.text('目前沒有任何警示'), findsNothing);

        // 放行讀取，模擬非同步完成，讓卡片重新 build。
        gate.complete();
        await tester.pumpAndSettle();

        final keys = tester
            .widgetList<Dismissible>(find.byType(Dismissible))
            .map((d) => d.key)
            .toSet();
        expect(keys, isNot(contains(const ValueKey('alert:9001'))));
        expect(keys, contains(const ValueKey('alert:9002')));
      },
    );
  });
}

/// 測試專用 harness：重現 `family_main_screen.dart::initState()` 對
/// `_loadDismissedAlertKeys()` 的呼叫模式——`initState()` 不 await 這個非同步
/// 讀取，讀取完成前 [dismissedKeysLoaded] 維持 false，完成（含 `finally`
/// 收尾）後才 `setState` 翻正。外部傳入的 [gate] 讓測試能精準控制「讀取尚未
/// 完成」與「讀取已完成」兩個時間點，不必依賴真實的 I/O 時間差。
class _ColdStartHarness extends StatefulWidget {
  final Future<void> gate;
  final List<Map<String, dynamic>> activeAlerts;

  const _ColdStartHarness({required this.gate, required this.activeAlerts});

  @override
  State<_ColdStartHarness> createState() => _ColdStartHarnessState();
}

class _ColdStartHarnessState extends State<_ColdStartHarness> {
  bool _dismissedKeysLoaded = false;
  Set<String> _dismissedAlertKeys = {};

  @override
  void initState() {
    super.initState();
    _load(); // 刻意不 await，比照 family_main_screen.dart::initState()。
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('family_dismissed_alert_keys');
      await widget.gate; // 由測試控制何時放行，模擬真實情況下的非同步延遲。
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final dismissed = decoded.keys.map((k) => k.toString()).toSet();
      if (!mounted) return;
      setState(() {
        _dismissedAlertKeys = dismissed;
        _dismissedKeysLoaded = true;
      });
    } finally {
      if (mounted && !_dismissedKeysLoaded) {
        setState(() {
          _dismissedKeysLoaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomeAlertPreviewCard(
      activeAlerts: widget.activeAlerts,
      dismissedAlertKeys: _dismissedAlertKeys,
      dismissedKeysLoaded: _dismissedKeysLoaded,
    );
  }
}
