import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/elder_pairing_display_screen.dart';
import 'package:flutter_application_1/screens/elder_profile_onboarding_screen.dart';
import 'package:flutter_application_1/screens/identification_screen.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/monitor_pairing_screen.dart';
import 'package:flutter_application_1/screens/privacy_policy_screen.dart';
import 'package:flutter_application_1/screens/registration_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登入流程畫面（新設計）在 360×640 小螢幕與系統字級 1.3 倍下不得有
/// RenderFlex 溢位（CLAUDE.md §3.1 第 14 條）。
///
/// 未納入：QrScannerScreen 需要相機外掛，測試環境無法建構。
/// ElderPairingDisplayScreen 在 initState 打後端 API，測試環境拿不到配對碼，
/// 因此只驗到「載入中」狀態；有配對碼的版面（6 格＋QR）未涵蓋。
Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required double textScale,
  bool dark = false,
}) async {
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
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: screen,
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final screens = <String, Widget Function()>{
    'IdentificationScreen': () => const IdentificationScreen(),
    'LoginScreen': () => const LoginScreen(),
    'PrivacyPolicyScreen': () => const PrivacyPolicyScreen(),
    'RegistrationScreen': () => const RegistrationScreen(),
    'MonitorPairingScreen': () => const MonitorPairingScreen(),
    'ElderPairingDisplayScreen': () => const ElderPairingDisplayScreen(),
    'ElderProfileOnboardingScreen': () => ElderProfileOnboardingScreen(
          userId: 1,
          userName: '秀枝阿嬤',
          roomId: 'r1',
          nextScreenBuilder: (_) => const SizedBox(),
        ),
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 1.3]) {
      for (final dark in [false, true]) {
        testWidgets(
            '${entry.key} 360×640 textScale $scale ${dark ? "深色" : "淺色"} 無溢位',
            (tester) async {
          await _pump(tester, entry.value(), textScale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          // 整頁可捲：確認沒有被固定高度卡死而無法操作。
          expect(find.byType(Scrollable), findsWidgets);
        });
      }
    }
  }
}
