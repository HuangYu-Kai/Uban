import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

/// 回歸測試：長輩端/家屬端淺深色主題切換時，AnimatedTheme 會 lerp 兩份 ThemeData，
/// TextStyle.lerp 要求 inherit 相同，否則擲例外並讓 App 重跑 Splash。
void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  // 模擬 main.dart：context 位於 MaterialApp 之上。
  Future<void> withCtx(WidgetTester tester,
      void Function(BuildContext) body) async {
    await tester.pumpWidget(Builder(builder: (context) {
      body(context);
      return const SizedBox();
    }));
  }

  testWidgets('長輩端淺/深色可雙向 lerp', (tester) async {
    await withCtx(tester, (context) {
      final l = buildAppTheme(context);
      final d = buildAppDarkTheme(context);
      expect(() => ThemeData.lerp(l, d, 0.5), returnsNormally);
      expect(() => ThemeData.lerp(d, l, 0.5), returnsNormally);
    });
    tester.takeException();
  });

  testWidgets('家屬端淺/深色可雙向 lerp', (tester) async {
    await withCtx(tester, (context) {
      final l = FamilyTheme.buildTheme(context);
      final d = FamilyTheme.buildTheme(context, isDark: true);
      expect(() => ThemeData.lerp(l, d, 0.5), returnsNormally);
      expect(() => ThemeData.lerp(d, l, 0.5), returnsNormally);
    });
    tester.takeException();
  });

  testWidgets('MaterialApp themeMode 切換不擲例外', (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    await tester.pumpWidget(Builder(
      builder: (context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, m, __) => MaterialApp(
          theme: buildAppTheme(context),
          darkTheme: buildAppDarkTheme(context),
          themeMode: m,
          home: const Scaffold(body: Text('hi')),
        ),
      ),
    ));
    for (final m in [ThemeMode.dark, ThemeMode.light, ThemeMode.dark]) {
      mode.value = m;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
