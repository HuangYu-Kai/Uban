import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/profile_appearance_card.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/elder_theme_mode.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load：缺值或不合法 → 跟隨系統；dark → 深色', () async {
    final c1 = ElderThemeModeController();
    await c1.load();
    expect(c1.value, ThemeMode.system);

    SharedPreferences.setMockInitialValues({'elder_theme_mode': 'bogus'});
    final c2 = ElderThemeModeController();
    await c2.load();
    expect(c2.value, ThemeMode.system);

    SharedPreferences.setMockInitialValues({'elder_theme_mode': 'dark'});
    final c3 = ElderThemeModeController();
    await c3.load();
    expect(c3.value, ThemeMode.dark);
  });

  testWidgets('點「深色」→ controller 變 dark 並寫入 prefs', (tester) async {
    final ctrl = ElderThemeModeController();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Theme(
          data: buildAppTheme(context),
          child: Scaffold(body: ProfileAppearanceCard(controller: ctrl)),
        ),
      ),
    ));
    expect(ctrl.value, ThemeMode.system);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(ctrl.value, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('elder_theme_mode'), 'dark');

    await tester.tap(find.text('淺色'));
    await tester.pumpAndSettle();
    expect(ctrl.value, ThemeMode.light);
    expect(prefs.getString('elder_theme_mode'), 'light');
  });
}
