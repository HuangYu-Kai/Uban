import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/family_onboarding_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('360x640 三頁不溢位 (dark=$dark)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [dark ? UbanColors.dark : UbanColors.light],
        ),
        home: const FamilyOnboardingScreen(userId: 1, userName: '小明'),
      ));
      await tester.pump();
      expect(find.text('歡迎，小明'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('先準備長輩的手機'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('掃描或輸入配對碼'), findsOneWidget);
      expect(find.text('開始配對'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
