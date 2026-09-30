// 第五十三輪 familyfix53 任務 1：情緒時間軸卡片樣式回歸測試。
//
// 使用者原話：「在家屬端的『情緒時間軸』介面設計與其他處不一致，沒有邊框，
// 內部顯示還歪一邊，不會隨著切換深色或淺色模式變更」。對應本檔兩組測試：
//   (a) 卡片背景／邊框必須取自 Theme.of(context).colorScheme，深色模式下
//       不能維持修正前寫死的 Colors.white／固定淺灰色碼（見
//       lib/screens/family/widgets/emotion_preview_card.dart 修正前的
//       `color: Colors.white` 與 `Border.all(color: const Color(0xFFE2E8F0))`）。
//   (b) `error`／`empty` 狀態的內容區塊必須撐滿卡片寬度（width: double.infinity）
//       才能讓圖示與文字相對整張卡片真正置中，而不是退化成 Column 預設縮寬
//       貼齊卡片左緣、造成「內部顯示還歪一邊」。
//
// `widget.elderId == null` 會讓 `_loadEmotionData()` 同步（不打任何網路）
// 把 `_status` 設成 `error`，藉此不需要 mock HTTP 就能確定性地命中要驗證
// 的 `error` 狀態分支——`empty`／`hasData` 兩種狀態依賴真實網路回應，本檔
// 刻意不驗證（沙盒沒有對應網路，命中不到；`error`／`empty` 兩者在本輪修正
// 前共用同一個「裸 Column 沒有撐滿寬度」的錯誤結構，驗證 error 分支足以
// 證明這個修法本身有效）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/widgets/emotion_preview_card.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection
    // （比照 family_data_tab_test.dart／alert_center_screen_test.dart 既有作法）。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({required Brightness brightness}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF59B294),
      brightness: brightness,
    );
    // 刻意只設定 `theme`、不設定 `darkTheme`——Flutter 在 `darkTheme` 為
    // null 時，`ThemeMode.system`（MaterialApp 預設值）一律套用 `theme`，
    // 不受測試執行環境的系統亮度設定影響，結果才具決定性。
    return MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        // elderId 為 null → 同步進入 error 狀態，不需要網路。
        body: EmotionPreviewCard(elderName: '測試長輩', elderId: null),
      ),
    );
  }

  BoxDecoration outerCardDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(EmotionPreviewCard),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration as BoxDecoration;
  }

  group('任務 1a：卡片背景／邊框必須隨主題切換', () {
    testWidgets('深色模式下卡片背景不能是寫死的 Colors.white，必須等於 colorScheme.surface',
        (tester) async {
      final darkScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF59B294),
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(buildHarness(brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 200));

      final decoration = outerCardDecoration(tester);

      expect(
        decoration.color,
        isNot(equals(Colors.white)),
        reason: '深色模式下卡片背景不能維持寫死的白色，否則就是使用者回報的'
            '「整張卡片是純白底」——其上下相鄰的健康趨勢／人生故事膠囊卡片'
            '在深色模式下都不是白色。',
      );
      expect(decoration.color, equals(darkScheme.surface));
    });

    testWidgets('深色模式下卡片邊框必須等於 colorScheme.outline（不是寫死的淺灰色）',
        (tester) async {
      final darkScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF59B294),
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(buildHarness(brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 200));

      final decoration = outerCardDecoration(tester);
      final border = decoration.border as Border;

      expect(border.top.color, equals(darkScheme.outline));
      expect(border.top.width, equals(1.5));
    });

    testWidgets('淺色模式下卡片背景改用 colorScheme.surface 後仍能正確渲染（不拋例外）',
        (tester) async {
      final lightScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF59B294),
        brightness: Brightness.light,
      );
      await tester.pumpWidget(buildHarness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 200));

      final decoration = outerCardDecoration(tester);
      expect(decoration.color, equals(lightScheme.surface));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'canary：淺色與深色兩種 colorScheme 的 surface 顏色本來就不同，證明上面的相等斷言並非恆真',
        (tester) async {
      final lightScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF59B294),
        brightness: Brightness.light,
      );
      final darkScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF59B294),
        brightness: Brightness.dark,
      );
      expect(lightScheme.surface, isNot(equals(darkScheme.surface)),
          reason: '若淺色/深色的 surface 顏色相同，上面兩組「等於 colorScheme.surface」'
              '的斷言就算卡片仍寫死同一個顏色也會誤判通過，必須先證明兩者不同。');
    });
  });

  group('任務 1b：error 狀態內容區塊必須撐滿卡片寬度，避免「歪一邊」', () {
    testWidgets('error 狀態下必須存在 width: double.infinity 的內容容器', (tester) async {
      await tester.pumpWidget(buildHarness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 200));

      // 修正前，error/empty 狀態用的是沒有指定寬度的裸 Column（縮寬貼齊
      // 卡片左緣，內容只在自己的窄範圍內置中）；修正後兩者都包了一層
      // SizedBox(width: double.infinity)。hasData 狀態原本就用
      // Container(width: double.infinity) 而非 SizedBox，因此「找得到
      // width 為 double.infinity 的 SizedBox」是修正後才會成立的斷言。
      final infiniteWidthSizedBoxes = tester
          .widgetList<SizedBox>(find.descendant(
            of: find.byType(EmotionPreviewCard),
            matching: find.byType(SizedBox),
          ))
          .where((box) => box.width == double.infinity);

      expect(
        infiniteWidthSizedBoxes,
        isNotEmpty,
        reason: 'error 狀態的圖示與文字內容必須包在 width: double.infinity 的容器'
            '內，否則 Column 會退化成依內容縮寬＋貼齊卡片左緣，形成使用者'
            '回報的「內部顯示還歪一邊」。',
      );
    });

    testWidgets('canary：一般的高度用 SizedBox（如 SizedBox(height: 8)）不會被誤判成寬度撐滿',
        (tester) async {
      await tester.pumpWidget(buildHarness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 200));

      // 證明上面的篩選條件真的有在區分——純高度間隔用的 SizedBox（width
      // 為 null，不是 double.infinity）不應該被算進「撐滿寬度」的集合。
      final heightOnlySizedBoxes = tester
          .widgetList<SizedBox>(find.descendant(
            of: find.byType(EmotionPreviewCard),
            matching: find.byType(SizedBox),
          ))
          .where((box) => box.width == null && box.height != null);

      expect(heightOnlySizedBoxes, isNotEmpty,
          reason: '本卡片本來就大量使用 SizedBox(height: N) 做間距，這個集合'
              '不應該是空的，否則代表上面 width==double.infinity 的篩選條件'
              '沒有實際區分作用（例如把所有 SizedBox 都算進去了）。');
    });

    testWidgets('error 狀態下顯示「尚未配對長輩」訊息（未提供 elderId 的既有行為，未被本輪改動）',
        (tester) async {
      await tester.pumpWidget(buildHarness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('尚未配對長輩'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
