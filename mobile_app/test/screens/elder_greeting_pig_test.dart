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
    // 白邊圖層（貼紙式描邊）隨小豬一起存在
    expect(find.byKey(const ValueKey('greeting_pig_outline')), findsWidgets);

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
}
