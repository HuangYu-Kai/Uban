import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_greeting_tab.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// 祝賀圖上的「我的小豬」：開關開啟時疊圖存在、關閉時消失，且偏好會存本機。
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host() => MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[UbanColors.light]),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ElderGreetingTab(userId: 1, userName: '測試', embedded: true),
          ),
        ),
      );

  final overlay = find.byKey(const ValueKey('greeting_pig_overlay'));
  final toggle = find.byKey(const ValueKey('greeting_pig_toggle'));

  testWidgets('預設開啟：疊圖存在；點開關後消失並寫入偏好', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlay, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlay, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('greeting_show_pig'), isFalse);
  });

  testWidgets('偏好為關：載入後無疊圖', (tester) async {
    SharedPreferences.setMockInitialValues({'greeting_show_pig': false});
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlay, findsNothing);
  });

  testWidgets('AI 智能生圖模式：無疊圖也無開關（偏好不動）；切回經典恢復', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlay, findsOneWidget);
    expect(toggle, findsOneWidget);

    await tester.tap(find.text('AI 智能生圖'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(overlay, findsNothing);
    expect(toggle, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('greeting_show_pig'), isNull);

    await tester.tap(find.text('經典圖文組合'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(overlay, findsOneWidget);
    expect(toggle, findsOneWidget);
  });
}
