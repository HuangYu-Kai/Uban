import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/family/family_home_tab.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_elder_header_card.dart';
import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final iconFile = File(r'C:\Users\OuO\.vscode\extensions\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
    if (iconFile.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
      await iconLoader.load();
    }

    final notoSansFile = File(r'E:\114Project\Uban\mobile_app\assets\fonts\NotoSansTC-Regular.ttf');
    if (notoSansFile.existsSync()) {
      final fontBytes = notoSansFile.readAsBytesSync();
      for (final name in [
        'NotoSansTC',
        'NotoSansTC-Regular',
        'NotoSansTC-Bold',
        'NotoSansTC-Medium',
        'NotoSansTC-SemiBold',
      ]) {
        try {
          final loader = FontLoader(name);
          loader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
          await loader.load();
        } catch (_) {}
      }
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'saved_role': 'family',
      'user_role': 'family',
      'caregiver_id': 1,
    });
  });

  testWidgets('Test 12-3-1 Family Home Tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;

    final boundaryKey = GlobalKey();
    final mockElder = Elder(
      id: 1,
      elderId: '1001',
      name: '王阿公',
      location: '客廳',
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: FamilyTheme.lightColorScheme,
          scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  HomeElderHeaderCard(
                    currentElder: mockElder,
                    isElderOnline: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File(r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images\fig_12_3_1_family_home.png');
    file.writeAsBytesSync(bytes);
    print('SUCCESS: Captured fig_12_3_1_family_home.png (${bytes.length} bytes)');

    exit(0);
  });
}
