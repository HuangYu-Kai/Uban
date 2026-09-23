// 今日頭條可見性回歸測試（第五十二輪，任務 A）。
//
// 背景：見 elder_home_tab.dart 內 `_buildFeaturedNewsCard` 開頭的說明——
// 第五十輪把「依剩餘空間決定大圖或精簡列」的下限判斷拿掉，變成無條件擠出
// 至少 170px 大圖，是三輪修復都沒解決「今日頭條看不到」的根因。第五十二輪
// 改回固定小尺寸縮圖的精簡列（不再有 `_availableNewsImageHeight` 這個方法），
// 本檔驗證「今日頭條」標題與新聞卡片在常見手機尺寸下，是否落在「第一屏
// 可視範圍」內（不需捲動、且不被浮動導覽列遮住）——這兩項現在是**硬性
// 斷言**（`expect`），不是只印出來給人看，重蹈覆轍會直接讓 `flutter test`
// 失敗。
//
// ⚠️ 本測試 pump 的是 ElderHomeTab 本尊（不是另外手刻的重現版）。
// `elder_home_tab_date_card_test.dart` 檔頭明講「不適合直接 pump 本尊」，
// 因為 initState 會打 HTTP（ApiService.getNews／getElderReminders、
// WeatherService.getWeather、SubscriptionService.isPro）。實測結果：
// `flutter test` 的 `TestWidgetsFlutterBinding` 會自動攔截整個測試套件
// 建立的 HttpClient，讓所有請求一律立即回傳 400、不會真的打對外網路
// （見執行時印出的官方警告："all HTTP requests will return status code
// 400, and no network request will actually be made"）——因此
// `_newsItems` 在本測試裡恆為空陣列、`_buildFeaturedNewsCard` 恆停在
// 「還在整理中」分支，`newsCardKey`／`moreNewsKey` 兩個 GlobalKey 不會
// 被建出來（只掛在「已有真實資料」分支），量測時用 evaluate().isNotEmpty
// 動態判斷，不強制要求存在。
//
// 這對本檔要驗證的「今日頭條標題 Y 座標」沒有影響：標題本身的位置只
// 取決於它前面兩張卡片（今天卡／下一包藥卡）當下的高度，新聞卡的
// header 一律無條件排在最前面（見 `_buildFeaturedNewsCard` 開頭），
// loading／無資料／有資料三態差別只在 header 之後的內容，不影響
// header 自己的座標。為了降低「今天卡／下一包藥卡自己還在 loading」
// 造成的誤差，這裡分兩個檢查點量測（第一輪 build 完成 vs 額外 pump
// 多輪讓非同步呼叫盡量落地），兩者都印出來對照。
//
// 全程只用 `tester.pump()`／`tester.pump(duration)` 固定次數，刻意不用
// `pumpAndSettle()`——避免 `_loadNextDoseData` 失敗後排的 8 秒重試
// Timer 或其他懸而未決的 Future 讓測試掛住或在收尾時噴出 pending timer
// 錯誤。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_home_tab.dart';

void main() {
  // google_fonts 在測試環境找不到本地字型資產時會嘗試打網路抓取，沙箱
  // 環境沒有對外網路會拖慢測試，關掉 runtime fetching 讓它退回系統
  // fallback 字型（做法與 elder_home_tab_date_card_test.dart 一致）。
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // 導覽列淨空：elder_home_tab.dart 自己的 `_availableNewsImageHeight`
  // 內文記載「底部 130 已含浮動導覽列 104 的淨空」——直接沿用這份檔案
  // 自己記載的常數當作「第一屏可視範圍」的判準，不需要另外讀
  // elder_home_screen.dart（本輪禁止改動的檔案）。
  const double navClearance = 130;

  final sizes = <({String label, double width, double height})>[
    (label: '360x640（窄機）', width: 360.0, height: 640.0),
    (label: '412x915（大機）', width: 412.0, height: 915.0),
  ];

  for (final size in sizes) {
    testWidgets('${size.label}：今日頭條標題與卡片量測', (tester) async {
      tester.view.physicalSize = Size(size.width, size.height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dateCardKey = GlobalKey();
      final newsCardKey = GlobalKey();
      final moreNewsKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElderHomeTab(
              userId: 1,
              userName: '測試長輩',
              roomId: 'test-elder-room',
              dateCardKey: dateCardKey,
              newsCardKey: newsCardKey,
              moreNewsKey: moreNewsKey,
            ),
          ),
        ),
      );
      await tester.pump();

      final double visibleBottom = size.height - navClearance;

      void report(String checkpoint) {
        expect(tester.takeException(), isNull, reason: '$checkpoint 不應該有任何例外');

        final headerFinder = find.text('今日頭條');
        expect(headerFinder, findsOneWidget, reason: '$checkpoint 標題必須被建出來');

        final headerRect = tester.getRect(headerFinder);
        final dateCardRect = tester.getRect(find.byKey(dateCardKey));

        // ⚠️ newsCardKey／moreNewsKey 只掛在 `_buildFeaturedNewsCard` 的
        // 「已有真實新聞資料」分支（Material/TextButton）——loading／無資料
        // 兩種狀態完全不會建出這兩個 widget。測試環境的 HTTP 一律被
        // TestWidgetsFlutterBinding 自動攔截回 400（見檔頭說明），
        // `_newsItems` 永遠是空陣列，因此這兩個 key 在本測試裡必然找不到，
        // 用 evaluate().isNotEmpty 動態判斷、不強制要求存在。
        final newsCardFinder = find.byKey(newsCardKey);
        final newsCardBuilt = newsCardFinder.evaluate().isNotEmpty;
        final moreNewsFinder = find.byKey(moreNewsKey);
        final moreNewsVisible = moreNewsFinder.evaluate().isNotEmpty;

        // 縮圖／佔位框固定尺寸（`_buildFeaturedNewsCard` 內的 `thumbSize`
        // 區域常數，第五十二輪起讀取中／無資料兩態共用同一顆常數，不再是
        // 依 MediaQuery 動態算出的 `_availableNewsImageHeight`）。量這個
        // newspaper 圖示佔位框的高度，等於間接量到該常數本身，不需要新聞
        // 資料真的抓得到。
        final placeholderBoxFinder = find.ancestor(
          of: find.byIcon(Icons.newspaper_rounded),
          matching: find.byType(Container),
        );
        final hasPlaceholderBox = placeholderBoxFinder.evaluate().isNotEmpty;
        final double? thumbSize = hasPlaceholderBox
            ? tester.getRect(placeholderBoxFinder.first).height
            : null;

        // ignore: avoid_print
        print(
          '[量測/$checkpoint] ${size.label}\n'
          '  今天卡: top=${dateCardRect.top.toStringAsFixed(1)} '
          'bottom=${dateCardRect.bottom.toStringAsFixed(1)} '
          'height=${dateCardRect.height.toStringAsFixed(1)}\n'
          '  今日頭條標題: top=${headerRect.top.toStringAsFixed(1)} '
          'bottom=${headerRect.bottom.toStringAsFixed(1)}\n'
          '  新聞卡是否已進入「有資料」分支: $newsCardBuilt'
          '${newsCardBuilt ? ' bottom=${tester.getRect(newsCardFinder).bottom.toStringAsFixed(1)}' : '（仍在 loading／無資料態，見檔頭說明）'}\n'
          '  縮圖／佔位框尺寸（間接量測，見上方註解）: '
          '${thumbSize?.toStringAsFixed(1) ?? "量不到"}\n'
          '  「更多」按鈕是否已建出: $moreNewsVisible'
          '${moreNewsVisible ? ' bottom=${tester.getRect(moreNewsFinder).bottom.toStringAsFixed(1)}' : ''}\n'
          '  第一屏可視底線: ${visibleBottom.toStringAsFixed(1)} '
          '(螢幕高 ${size.height.toStringAsFixed(0)} － 導覽列淨空 $navClearance)\n'
          '  → 標題在第一屏內: ${headerRect.bottom <= visibleBottom}',
        );

        // ★ 第五十二輪：以下兩條是本檔真正的回歸防線（硬斷言，不是印給人看
        // 而已）。
        //
        // 1. 標題必須落在第一屏內。這是團隊主管訂的驗收標準本身
        //    （「長輩不需要捲動就看得到『今日頭條』」），過去這裡只有
        //    `print`、沒有 `expect`，即使標題被擠出第一屏，測試仍然全綠
        //    ——不符合「驗證必須有可能失敗」的鐵律，第五十二輪補上。
        expect(
          headerRect.bottom,
          lessThanOrEqualTo(visibleBottom),
          reason: '$checkpoint「今日頭條」標題必須落在第一屏可視範圍內，'
              '不需捲動就看得到',
        );

        // 2. 佔位框尺寸必須維持小尺寸精簡列，不能再回到第五十輪
        //    `leftover.clamp(170.0, 260.0)` 那種「無論剩餘空間夠不夠，
        //    一律強制擠出至少 170px」的設計——170 遠大於這裡設的門檻
        //    100，未來若有人重蹈覆轍，這條斷言會直接讓測試失敗，而不是
        //    要等到下一輪使用者又實機回報「看不到」。
        if (thumbSize != null) {
          expect(
            thumbSize,
            lessThanOrEqualTo(100),
            reason: '$checkpoint 新聞卡縮圖／佔位框不應恢復成大圖尺寸'
                '（第五十輪 leftover.clamp(170.0, 260.0) 的回歸）',
          );
        }
      }

      report('第一輪 build 完成（未等待網路）');

      // 額外 pump 幾輪、每輪間隔 300ms，讓「這台測試機連得到正式後端」時
      // 的真實網路呼叫有機會落地（不用 pumpAndSettle，固定 6 輪、合計
      // 1.8 秒即結束，不會因為任何卡住的 Future 而掛住測試）。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      report('額外 pump 6 輪（1.8s）後');
    });
  }
}
