import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/identification_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ★ 2026-10-07 身分選擇導覽：help 入口、版面不溢位、導覽開啟行為。
Future<void> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [UbanColors.light]),
    darkTheme: ThemeData(
        brightness: Brightness.dark, extensions: const [UbanColors.dark]),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: const IdentificationScreen(),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final dark in [false, true]) {
    testWidgets('已看過導覽：有說明按鈕且無溢位（${dark ? "深色" : "淺色"}）', (tester) async {
      SharedPreferences.setMockInitialValues({
        'tutorial_done_identification_v1': true,
      });
      await _pump(tester, dark: dark);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('怎麼選？'), findsOneWidget);
      expect(find.bySemanticsLabel('身分選擇說明'), findsOneWidget);
      expect(find.text('歡迎使用 Uban'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首次進入自動開啟導覽', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('歡迎使用 Uban'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全域跳過旗標不影響本頁首次導覽', (tester) async {
    SharedPreferences.setMockInitialValues({
      'elder_all_tutorials_dismissed': true,
    });
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('歡迎使用 Uban'), findsOneWidget);
  });

  testWidgets('點「怎麼選？」開啟導覽', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tutorial_done_identification_v1': true,
    });
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('怎麼選？'));
    // showForce 會等一個 post-frame 才開對話框，需多推進幾個 frame。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('歡迎使用 Uban'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
