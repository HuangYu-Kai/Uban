// 第五十二輪：家屬端「資料」分頁回歸測試。
//
// 背景：使用者實機回報第五十一輪修復後，家屬端「資料」分頁 (1) 內容呈現
// 空白、(2) 任何按鍵（含純本機的深色主題開關）全部無法互動。本測試直接
// pump `FamilyDataTab` 本尊（不是另外手刻的重現版），驗證：
//   a. 「受關照長輩檔案」卡片與長輩姓名確實有畫出來
//   b. 深色主題 Switch 點擊後真的會呼叫 onToggleDarkMode
//   c. 登出按鈕點擊後真的能開啟確認對話框（Navigator/showDialog 未被擋）
//   d. 分頁根節點版面尺寸不是 0
//
// `_loadSubscriptionInfo` / `_loadAiProfile` / `EmotionPreviewCard` 會打真實
// HTTP（打 ApiClient.baseUrl，預設 Tailscale 主機名），測試沙盒沒有對應網路
// /VPN，會以 DNS 查詢失敗快速失敗（非 15 秒逾時卡住）；三處呼叫皆已包
// try/catch，失敗後會落到既有的預設值/錯誤狀態顯示，不會拋出例外炸穿測試。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testElder = Elder(
    id: 1,
    elderId: 'E001',
    name: '陳阿嬤',
    gender: 'F',
    age: 78,
    location: '台北市',
  );

  Widget buildHarness({
    Elder? elder,
    bool isDarkMode = false,
    ValueChanged<bool>? onToggleDarkMode,
    List<NavigatorObserver> navigatorObservers = const [],
  }) {
    return MaterialApp(
      navigatorObservers: navigatorObservers,
      home: Scaffold(
        body: FamilyDataTab(
          currentElder: elder,
          userId: 1,
          userName: '測試家屬',
          isDarkMode: isDarkMode,
          onToggleDarkMode: onToggleDarkMode,
        ),
      ),
    );
  }

  // ── canary：刻意寫一個不可能成立的斷言，證明本測試機制真的會失敗 ──
  // 驗證完「測試機制有效」後改為 skip，避免污染正式測試結果，但保留在檔案
  // 內方便之後其他人／自己重新確認測試機制沒有失效。
  testWidgets(
    'canary（驗證測試機制有效，平常應為 skip）',
    (WidgetTester tester) async {
      await tester.pumpWidget(buildHarness(elder: testElder));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('這段文字不可能出現在畫面上_canary_只是用來證明斷言會失敗'),
          findsOneWidget);
    },
    skip: true,
  );

  // ── canary：重建第五十二輪根因的最小錯誤結構，證明它「真的」會丟出例外 ──
  // 不是改 family_data_tab.dart 本身，而是在測試裡獨立重建同一種誤用
  // 形狀（SliverList 清單項目 → Column 直接子節點包 Expanded/Flexible），
  // 用來證明上面「版面不會炸」那個測試真的有可能失敗、不是恆真斷言
  // （鐵律「驗證必須有可能失敗」）。若 Flutter 未來版本改變了這個例外的
  // 判定方式導致本測試開始失敗，也是有意義的訊號，應該回頭檢視。
  testWidgets(
    'canary：SliverList 項目裡的 Column 直接包 Expanded 會丟出 unbounded RenderFlex 例外',
    (WidgetTester tester) async {
      // ⚠️ 這個壞結構在同一次 pump 內會連續觸發多次（layout、paint、
      // semantics 各自嘗試處理同一棵壞掉的 render tree），實測會累積到 7
      // 個例外——`tester.takeException()` 一旦偵測到「不只一個」，回傳的
      // 不是原始例外，而是一個 `'Multiple exceptions (N) were detected...'`
      // 的包裝物件，`.toString()` 抓不到 'RenderFlex' 字樣（已實測踩過這個
      // 坑：一開始直接斷言 takeException() 的內容，導致 canary 本身以錯誤
      // 的理由失敗）。改成暫時接管 `FlutterError.onError`，自己收集全部
      // FlutterErrorDetails，就能明確斷言「至少一個是我們要的 unbounded
      // RenderFlex 例外」，而不被聚合包裝訊息擋住。
      final List<FlutterErrorDetails> caught = [];
      final void Function(FlutterErrorDetails)? originalOnError =
          FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        caught.add(details);
      };

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: CustomScrollView(
              slivers: [
                SliverList(
                  delegate: SliverChildListDelegate([
                    // 與第五十二輪修復前的 _buildHealthTrendsEntryCard 同款
                    // 誤用：Column 是 SliverList 清單項目的（間接）直接子
                    // 節點，拿到無界高度，Expanded 卻是它的直接子節點。
                    Column(
                      children: [
                        Text('標題'),
                        Expanded(child: Text('這裡放 Expanded 會丟出例外')),
                      ],
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      } finally {
        FlutterError.onError = originalOnError;
      }

      expect(
        caught,
        isNotEmpty,
        reason: '這個刻意重建的錯誤結構應該要讓 Flutter 在 layout 階段丟出 '
            'unbounded RenderFlex 例外；若這裡是空的，代表本測試沒有正確'
            '重建出鐵律 #14「Flexible/Expanded 誤包在無界高度 Column」這個'
            '誤用模式對應的真實 bug 情境，需要重新檢查重建的結構。',
      );
      expect(
        caught.any((d) {
          final msg = d.exceptionAsString();
          return msg.contains('RenderFlex') && msg.contains('unbounded');
        }),
        isTrue,
        reason: '收集到 ${caught.length} 個例外，但沒有一個同時符合 '
            '「RenderFlex」與「unbounded」——代表這次重建出的可能是別的例外，'
            '不是我們要證明的那個 layout 階段 unbounded RenderFlex 錯誤。'
            '實際收集到的訊息：${caught.map((d) => d.exceptionAsString()).join(' | ')}',
      );
    },
  );

  testWidgets('FamilyDataTab 會畫出「受關照長輩檔案」卡片與長輩姓名', (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness(elder: testElder));
    // 不用 pumpAndSettle()：EmotionPreviewCard/_loadAiProfile/_loadSubscriptionInfo
    // 走真實 http，沙盒沒有對應網路，用固定 pump 給 DNS 失敗的 catch 分支足夠時間跑完即可。
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('受關照長輩檔案'), findsOneWidget);
    expect(find.text('陳阿嬤'), findsOneWidget);
    expect(find.text('🎨 外觀風格與色彩主題'), findsOneWidget);
    // 「登出目前帳號」在清單最下方，預設測試視窗高度看不到、也還沒被
    // SliverList 掛載進 Element 樹，故不在本測試斷言（這裡只驗證「內容有
    // 畫出來」，捲動可互動性由下面兩個專門的測試驗證）。
  });

  testWidgets('FamilyDataTab 版面不會炸：pump 期間沒有任何 FlutterError/例外', (WidgetTester tester) async {
    // ★ 第五十二輪根因的直接迴歸測試：原本「健康趨勢」標題誤用 Flexible
    // 包在 Column 的直接子節點上，該 Column 活在 SliverList 清單項目裡
    // （無界高度），layout 階段會丟出「RenderFlex children have non-zero
    // flex but incoming height constraints are unbounded」，例外沿
    // RenderObject 樹往上炸穿 SliverList／Viewport，導致整條
    // CustomScrollView 這一影格的版面計算全部失敗——這正是使用者回報
    // 「資料分頁一片空白、所有按鍵都按不動」的根因。`ErrorBoundary`
    // （見 family_data_tab.dart build() 內的說明）只包得住 build 階段的
    // 同步呼叫，攔不到 layout 階段的例外，因此本測試不能只看畫面上有沒有
    // 文字，必須直接檢查 `tester.takeException()`。
    // 下方 canary group 用重建的最小結構證明「這個結構真的會丟出這個例外」。
    await tester.pumpWidget(buildHarness(elder: testElder));
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.takeException(),
      isNull,
      reason: '若這裡抓到例外，代表 Flexible/Expanded 誤包在無界高度 Column 的'
          '直接子節點這個模式又出現了（同款誤用見鐵律 #14），必須修正——不能只'
          '靠畫面上的文字斷言，因為 layout 例外不影響 Text 判斷結果。',
    );
  });

  testWidgets('深色主題開關可互動：點擊後真的呼叫 onToggleDarkMode', (WidgetTester tester) async {
    bool? received;
    await tester.pumpWidget(buildHarness(
      elder: testElder,
      isDarkMode: false,
      onToggleDarkMode: (val) => received = val,
    ));
    await tester.pump(const Duration(seconds: 2));

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget, reason: '深色主題開關必須存在於畫面上');

    await tester.tap(switchFinder);
    await tester.pump();

    expect(received, isTrue, reason: '點擊 Switch 後 onToggleDarkMode 必須被呼叫，否則代表手勢被擋住了');
  });

  testWidgets('登出按鈕可互動：點擊後真的會開啟確認對話框', (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness(elder: testElder));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('安全登出'), findsNothing);

    // 「登出目前帳號」在清單最下方，預設測試視窗看不到、SliverList 也還沒把
    // 它掛進 Element 樹，必須先捲動讓它進入建置範圍才找得到、點得到。
    await tester.scrollUntilVisible(
      find.text('登出目前帳號'),
      300.0,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('登出目前帳號'));
    await tester.pump(); // showDialog 觸發
    await tester.pump(const Duration(milliseconds: 300)); // 對話框轉場動畫

    expect(find.text('安全登出'), findsOneWidget,
        reason: '點擊登出按鈕後應該要能打開確認對話框，若找不到代表手勢沒有送達 onPressed');
    expect(find.text('確定要登出當前帳號並回到身分選擇頁面嗎？'), findsOneWidget);
  });

  testWidgets('裝置配對與加值服務的動作項目可互動：點擊會呼叫 Navigator.push', (WidgetTester tester) async {
    // ⚠️ 這裡刻意不用 pumpAndSettle 真正進入 FamilySubscriptionScreen：
    // 該畫面自己的 initState 會起一個測試沙盒收不到 callback、也不會在
    // dispose 時取消的 Timer（已實測驗證，pop 回來也無法避免），跟本檔要
    // 驗證的「FamilyDataTab 的 InkWell 手勢有沒有送達 onTap」無關，屬於
    // FamilySubscriptionScreen 自己的問題、不在本輪任務範圍內。改用
    // NavigatorObserver 在「導覽被呼叫」的當下就攔截驗證——`tester.tap()`
    // 的 pointer up 事件會同步觸發 InkWell 的 onTap → Navigator.push，
    // 這一步觀察者的 didPush 就能同步記錄到，不需要真的 pump 進新畫面、
    // 不會讓新畫面的 initState 有機會起 Timer。
    final List<Route<dynamic>> pushedRoutes = [];

    await tester.pumpWidget(buildHarness(
      elder: testElder,
      navigatorObservers: [_RecordingNavigatorObserver(pushedRoutes)],
    ));
    await tester.pump(const Duration(seconds: 2));

    final subscriptionEntry = find.text('訂閱方案與設備上限管理');
    // 這張卡片在清單中段，預設測試視窗看不到、也還沒被 SliverList 掛進
    // Element 樹，先捲動讓它進入建置範圍（同登出按鈕測試的理由）。
    await tester.scrollUntilVisible(
      subscriptionEntry,
      300.0,
      scrollable: find.byType(Scrollable),
    );
    // `scrollUntilVisible` 只確保目標「進入 Element 樹」，不保證完全落在
    // 測試視窗（800×600）可視範圍內；`ensureVisible` 再精準捲動一次，
    // 否則 tap() 算出的座標可能落在視窗外而打不中（同類經驗見鐵律 #14
    // 「驗證必須有可能失敗」——這裡曾經真的因為差 21px 而 tap 不到）。
    await tester.ensureVisible(subscriptionEntry);
    await tester.pumpAndSettle();
    expect(subscriptionEntry, findsOneWidget);

    // `MaterialApp` 啟動時會先自己 push 一次初始路由（"/"），所以基準值
    // 不是 0，改記錄 tap 前的筆數、比對 tap 後是否「多了一筆」。
    final int pushedBeforeTap = pushedRoutes.length;
    await tester.tap(subscriptionEntry);
    // 刻意不 pump：讓斷言只驗證「手勢有沒有送達 onTap 呼叫
    // Navigator.push」，不去碰新路由實際 build 之後的內部狀態。
    expect(pushedRoutes.length, greaterThan(pushedBeforeTap),
        reason: '點擊「訂閱方案與設備上限管理」後 InkWell 的 onTap 應該要呼叫 Navigator.push，'
            '若筆數沒有增加代表手勢沒有送達 onTap（即使用者回報的「按了沒反應」症狀）');
  });

  testWidgets('FamilyDataTab 根節點版面尺寸不為 0', (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness(elder: testElder));
    await tester.pump(const Duration(seconds: 2));

    final size = tester.getSize(find.byType(FamilyDataTab));
    expect(size.width, greaterThan(0), reason: 'FamilyDataTab 寬度不應為 0（否則代表版面塌陷）');
    expect(size.height, greaterThan(0), reason: 'FamilyDataTab 高度不應為 0（否則代表版面塌陷）');
  });
}

/// 只記錄「有哪些路由被 push 過」的最小 NavigatorObserver，用來驗證
/// `InkWell`/按鈕的 onTap 是否真的呼叫了 `Navigator.push`，不需要真的把
/// 目的畫面 pump 進畫面（見上面「裝置配對與加值服務」測試的說明）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  _RecordingNavigatorObserver(this.pushedRoutes);

  final List<Route<dynamic>> pushedRoutes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}
