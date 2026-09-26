import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/home/widgets/home_elder_header_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_zone_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_monitor_device_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_ai_mood_radar_card.dart';
import 'package:flutter_application_1/screens/family/home/widgets/home_alert_preview_card.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';
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
      'caregiver_name': '王大明',
    });
  });

  testWidgets('Generate 12-3-1 Family Home Tab and 12-3-8 Family Data Tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;

    final mockElder = Elder(
      id: 1,
      elderId: '1001',
      name: '王阿公',
      location: '客廳',
    );

    // ─── 1. Capture Family Home Tab (12-3-1) ──────────────────────
    final homeKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: FamilyTheme.lightColorScheme,
          scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: RepaintBoundary(
            key: homeKey,
            child: Container(
              color: const Color(0xFFF8FAFC),
              width: 411.4,
              height: 914.3,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                child: Column(
                  children: [
                    HomeElderHeaderCard(
                      currentElder: mockElder,
                      isElderOnline: true,
                    ),
                    const SizedBox(height: 16),
                    const HomeZoneCard(
                      monitorDevices: [
                        {'device_id': 'cctv_living', 'device_name': '客廳 AI 守護鏡頭', 'status': 'online', 'room_name': '客廳'},
                        {'device_id': 'cctv_bedroom', 'device_name': '臥室監控鏡頭', 'status': 'online', 'room_name': '臥室'},
                      ],
                      elderZone: {
                        'zone': '客廳',
                        'enteredAt': '10分鐘前',
                        'present': true,
                      },
                    ),
                    const SizedBox(height: 16),
                    HomeMonitorDeviceCard(
                      monitorDevices: const [
                        {'device_id': 'cctv_living', 'device_name': '客廳 AI 守護鏡頭', 'status': 'online', 'room_name': '客廳'},
                        {'device_id': 'cctv_bedroom', 'device_name': '臥室監控鏡頭', 'status': 'online', 'room_name': '臥室'},
                      ],
                      activeAlerts: const [
                        {
                          'id': 'alert_1',
                          'alert_type': 'fall_detected',
                          'elder_id': '1001',
                          'device_name': '客廳 AI 守護鏡頭',
                          'location': '客廳沙發旁',
                          'timestamp': '2026-09-27 10:15:20',
                          'severity': 'critical',
                          'message': 'AI 影像偵測到疑似跌倒姿態，請立即確認！',
                        }
                      ],
                      elderZone: const {
                        'zone': '客廳',
                        'enteredAt': '10分鐘前',
                        'present': true,
                      },
                      currentElder: mockElder,
                    ),
                    const SizedBox(height: 16),
                    HomeAiMoodRadarCard(
                      currentElder: mockElder,
                      moodInsightData: const {
                        'mood': '平和舒暢',
                        'summary': '王阿公今日精神良好，早晨於花園漫步，午後與小豬互動頻繁。',
                        'suggestion': '推薦晚間進行溫馨通話，分享今日生活趣事。',
                      },
                      realLogs: const [],
                    ),
                    const SizedBox(height: 16),
                    HomeAlertPreviewCard(
                      currentElder: mockElder,
                      activeAlerts: const [
                        {
                          'id': 'alert_1',
                          'alert_type': 'fall_detected',
                          'elder_id': '1001',
                          'device_name': '客廳 AI 守護鏡頭',
                          'location': '客廳沙發旁',
                          'timestamp': '2026-09-27 10:15:20',
                          'severity': 'critical',
                          'message': 'AI 影像偵測到疑似跌倒姿態，請立即確認！',
                        }
                      ],
                      realLogs: const [],
                      emergencyAlerts: const [],
                      dismissedAlertKeys: const {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    final homeBoundary = homeKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final homeImage = await homeBoundary.toImage(pixelRatio: 2.0);
    final homeByteData = await homeImage.toByteData(format: ui.ImageByteFormat.png);
    final homeBytes = homeByteData!.buffer.asUint8List();

    File(r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images\fig_12_3_1_family_home.png')
        .writeAsBytesSync(homeBytes);
    print('SUCCESS: Captured fig_12_3_1_family_home.png (${homeBytes.length} bytes)');

    // ─── 2. Capture Family Data Tab (12-3-8) ──────────────────────
    final dataKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: FamilyTheme.lightColorScheme,
          scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: RepaintBoundary(
            key: dataKey,
            child: Container(
              color: const Color(0xFFF8FAFC),
              width: 411.4,
              height: 914.3,
              child: FamilyDataTab(
                currentElder: mockElder,
                userId: 1,
                userName: '王大明',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    final dataBoundary = dataKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final dataImage = await dataBoundary.toImage(pixelRatio: 2.0);
    final dataByteData = await dataImage.toByteData(format: ui.ImageByteFormat.png);
    final dataBytes = dataByteData!.buffer.asUint8List();

    File(r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images\fig_12_3_8_family_data.png')
        .writeAsBytesSync(dataBytes);
    print('SUCCESS: Captured fig_12_3_8_family_data.png (${dataBytes.length} bytes)');

    exit(0);
  });
}
