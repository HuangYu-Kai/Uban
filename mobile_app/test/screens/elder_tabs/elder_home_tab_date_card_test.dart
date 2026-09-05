// 長輩端首頁「日期卡片」大字級溢位迴歸測試。
//
// 背景：`ElderHomeTab` 首頁日期卡片的左（國曆日期＋星期）右（農曆＋節氣）
// 兩欄排版，過去用 `Row` + `Spacer()` + 兩個未包 `Flexible`/`Expanded` 的
// `Column`。兩欄字級極大（44pt／26pt／24pt／22pt）且全 App 沒有任何
// `textScaler` 覆寫（會完全跟隨系統字體大小），當長輩把系統字體調大時，
// 兩欄實際需要的寬度會超過卡片可用寬度，觸發 Flutter 的 RenderFlex
// 溢位警示（黃黑斜紋條）——這是使用者看得到的 UI 缺陷（CLAUDE.md 鐵律 #14）。
//
// 測試對象：本檔測的是 `ElderDateSummaryRow`（`lib/screens/elder_tabs/
// elder_home_tab.dart` 內的正式元件，從 `_ElderHomeTabState
// ._buildElderDateCard` 抽出），不是另外手刻的「重現版」——`ElderHomeTab`
// 本尊的 `initState` 會呼叫 `ApiService.getNews`（真實 HTTP 請求）與
// `SubscriptionService.isPro`，且農曆字串來自 `Lunar.fromDate(DateTime.now())`
// 無法在測試中控制成「閏月」等最長字串情境，因此不適合直接 pump 本尊。
// `ElderDateSummaryRow` 是把卡片排版抽成的獨立、不連網、不讀
// SharedPreferences 的 StatelessWidget，pump 的就是實際會被
// `ElderHomeTab` 使用的同一個 class（而非另外複製一份長得很像的程式碼）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_home_tab.dart';

void main() {
  // google_fonts 在測試環境找不到本地字型資產時會嘗試打網路抓取 Google
  // Fonts CDN；沙箱/CI 環境通常沒有對外網路，會造成測試變慢甚至因未處理的
  // Future rejection 而誤報失敗。關掉 runtime fetching 讓它直接退回系統
  // fallback 字型（兩側比較用的是同一支 API，量測與實際渲染仍然一致，
  // 不影響本測試要驗證的「會不會溢位」）。
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // 卡片外層寬度預算，對應 elder_home_tab.dart `_ElderHomeTabState.build`
  // 與 `_buildElderDateCard` 的實際排版鏈：
  //   Padding(20, 0, 20, 130)         → 左右各扣 20
  //   GlassCard(padding: h:24, v:18)  → 左右各扣 24
  // 320dp 螢幕下，Row 實際可用寬度 = 320 - 20*2 - 24*2 = 232。
  const outerHorizontalPadding = EdgeInsets.fromLTRB(20, 0, 20, 130);
  const cardPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 18);

  // 國曆日期恆為 6 碼（DateFormat('MM月') 固定 2 碼零填+『月』，dd 固定 2 碼
  // 零填+『日』），沒有「最長」的問題，用 12/31 示範即可。
  const monthStr = '12月';
  const dateStr = '31';
  // 星期固定 3 碼（星期一～星期日），任取一個。
  const dayName = '星期三';
  // 節氣固定 2 碼（24 節氣皆為 2 字），任取一個。
  const solarTerm = '大寒';
  // 農曆日期的真正最長情形：lunar 套件（lunar-1.7.8）getMonthInChinese()
  // 對閏月回傳「閏」+單字月名（如「闰腊」，2 碼），getDayInChinese() 固定
  // 回傳 2 碼日名（如「廿九」）；平年最長是 4 碼（如「腊月廿九」），閏年
  // 閏月是全年最長情形，5 碼（如「闰腊月廿九」），拿來當壓力測試上限。
  const lunarDateLeapWorstCase = '闰腊月廿九';
  const lunarDateTypical = '腊月廿九';

  final rowKey = UniqueKey();

  /// 與正式頁面相同的外層排版鏈包住 [ElderDateSummaryRow]，讓
  /// `LayoutBuilder` 量到的可用寬度與 production 一致。
  Widget buildHarness({required String lunarDate}) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: outerHorizontalPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: cardPadding,
                child: ElderDateSummaryRow(
                  key: rowKey,
                  monthStr: monthStr,
                  dateStr: dateStr,
                  dayName: dayName,
                  lunarDate: lunarDate,
                  solarTerm: solarTerm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 用 [MediaQuery] 覆寫 textScaler，並用 tester.view 讓「螢幕寬度」真的
  /// 影響 layout 的實際 constraints（單純包一層 MediaQueryData(size: ...)
  /// 只會改變「資料」，不會改變 RenderView 真正給出的 BoxConstraints）。
  Future<void> pumpAt(
    WidgetTester tester, {
    required double width,
    required double textScale,
    required String lunarDate,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: buildHarness(lunarDate: lunarDate),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ElderDateSummaryRow 大字級溢位防護', () {
    for (final lunarDate in [lunarDateLeapWorstCase, lunarDateTypical]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '320dp 寬 / textScaler=$scale / 農曆="$lunarDate" 不應觸發 RenderFlex 溢位',
          (tester) async {
            await pumpAt(
              tester,
              width: 320,
              textScale: scale,
              lunarDate: lunarDate,
            );

            expect(
              tester.takeException(),
              isNull,
              reason: '不應該有任何例外（尤其是 RenderFlex overflowed 這類斷言錯誤）',
            );
          },
        );
      }
    }

    testWidgets(
      '1.0 倍字級、寬度充足（650dp）時，維持原本 Row+Spacer 排版（沒有進入等比縮小分支）',
      (tester) async {
        // 650dp 是實測（見下方診斷數據）在本測試環境的 fallback 字型下，
        // 確保兩欄「塞得下」所需的寬度，附帶充足安全邊際：
        // 這個測試環境沒有網路可下載真正的 Noto Sans TC，google_fonts 會
        // 退回系統 fallback 字型，量出來的 CJK 字元寬度恰好等於字級本身
        // （每字 1 em，等同「豆腐塊」寬度），比正式環境的 Noto Sans TC 實際
        // 字寬更寬。用診斷腳本量測本環境下最長組合（leftMax=264 + rightMax
        // =120 = 384px），650dp 螢幕扣掉 Padding(20,0,20,130) 與 GlassCard
        // padding(24) 共 88px 後可用 562px，遠大於 384px，確保穩穩「塞得下」
        // ——這個案例要驗證的是分支邏輯本身（塞得下就完全不進 FittedBox），
        // 不是特定裝置寬度，320dp 的裝置寬度已由上面幾個案例覆蓋。
        await pumpAt(
          tester,
          width: 650,
          textScale: 1.0,
          lunarDate: lunarDateLeapWorstCase,
        );

        expect(tester.takeException(), isNull);

        final rowFinder = find.descendant(
          of: find.byKey(rowKey),
          matching: find.byType(Row),
        );
        final fittedBoxFinder = find.descendant(
          of: find.byKey(rowKey),
          matching: find.byType(FittedBox),
        );
        final spacerFinder = find.descendant(
          of: find.byKey(rowKey),
          matching: find.byType(Spacer),
        );

        // 塞得下時必須完全沿用原本的 Row+Spacer 寫法，不能跑進 FittedBox
        // 等比縮小分支——這是保證「1.0 倍字級外觀零改變」最直接的證明：
        // 走的是同一段程式碼／同一棵 widget tree，而不是「看起來很像」。
        expect(rowFinder, findsOneWidget);
        expect(spacerFinder, findsOneWidget);
        expect(fittedBoxFinder, findsNothing);

        // 進一步核對左欄靠左、右欄靠右都貼齊 Row 本身的邊界（Spacer 撐開
        // 全部剩餘空間的既有行為）。
        final rowRect = tester.getRect(rowFinder);
        final dateTextRect = tester.getRect(find.text('$monthStr$dateStr日'));
        final lunarTextRect = tester.getRect(find.text(lunarDateLeapWorstCase));

        expect(dateTextRect.left, moreOrLessEquals(rowRect.left, epsilon: 0.5));
        expect(lunarTextRect.right, moreOrLessEquals(rowRect.right, epsilon: 0.5));
      },
    );

    testWidgets(
      '超大字級（2.0x）仍會等比縮小而非溢位或裁切文字（改走 FittedBox 分支）',
      (tester) async {
        await pumpAt(
          tester,
          width: 320,
          textScale: 2.0,
          lunarDate: lunarDateLeapWorstCase,
        );

        expect(tester.takeException(), isNull);

        final fittedBoxFinder = find.descendant(
          of: find.byKey(rowKey),
          matching: find.byType(FittedBox),
        );
        expect(
          fittedBoxFinder,
          findsOneWidget,
          reason: '塞不下時應該改走整體等比縮小分支',
        );

        // 兩段文字都完整存在（沒有被 ellipsis 裁掉任何字元）。
        expect(find.text('$monthStr$dateStr日'), findsOneWidget);
        expect(find.text(lunarDateLeapWorstCase), findsOneWidget);

        // 不應該有任何 Text 使用 ellipsis 裁切。
        final dateTextWidget =
            tester.widget<Text>(find.text('$monthStr$dateStr日'));
        final lunarTextWidget =
            tester.widget<Text>(find.text(lunarDateLeapWorstCase));
        expect(dateTextWidget.overflow, isNot(TextOverflow.ellipsis));
        expect(lunarTextWidget.overflow, isNot(TextOverflow.ellipsis));
      },
    );
  });
}
