import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/role_selection_screen.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/elder_profile_onboarding_screen.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'caregiver_id': 1,
      'caregiver_name': '王大明',
      'user_role': 'family',
    });
  });

  Future<void> captureScreen(
    WidgetTester tester,
    Widget widget,
    String filename, {
    ThemeData? theme,
    Duration settleTime = const Duration(milliseconds: 1000),
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ??
            ThemeData(
              fontFamily: 'NotoSansTC',
              useMaterial3: true,
            ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: widget,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(settleTime);

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.625);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    const outputDir = r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images';
    final targetFile = File('$outputDir\\$filename');
    await targetFile.writeAsBytes(pngBytes);
    print('Rendered: $filename (${pngBytes.length} bytes)');
  }

  testWidgets('Test 12-1-1, 12-1-2, 12-1-3', (tester) async {
    await captureScreen(
      tester,
      const RoleSelectionScreen(),
      'fig_12_1_1_role_identification.png',
    );

    await captureScreen(
      tester,
      const LoginScreen(),
      'fig_12_1_2_login.png',
    );

    await captureScreen(
      tester,
      ElderProfileOnboardingScreen(
        userId: 1,
        userName: '王阿公',
        roomId: '1001',
        nextScreenBuilder: (_) => const SizedBox(),
      ),
      'fig_12_1_3_elder_onboarding.png',
    );
  });
}
