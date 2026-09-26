import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Screens to capture
import 'package:flutter_application_1/screens/identification_screen.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_home_tab.dart';
import 'package:flutter_application_1/screens/almanac/farmer_almanac_screen.dart';
import 'package:flutter_application_1/screens/news_listen_player/news_listen_player_screen.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/pet_studio_screen.dart';
import 'package:flutter_application_1/screens/zen_pond/zen_pond_screen.dart';
import 'package:flutter_application_1/screens/video_call_screen.dart';
import 'package:flutter_application_1/screens/family/family_home_tab.dart';
import 'package:flutter_application_1/screens/family/family_interaction_tab.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';
import 'package:flutter_application_1/screens/family/remote_care_hub_screen.dart';
import 'package:flutter_application_1/screens/family/alert_center_screen.dart';
import 'package:flutter_application_1/screens/family/health_reminder_screen.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';
import 'package:flutter_application_1/screens/caregiver_pairing_screen.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/services/memoir_service.dart';
import 'package:flutter_application_1/services/signaling.dart';

import 'package:flutter_application_1/theme/family_theme.dart';

final String outputDir = r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images';

Future<void> loadFonts() async {
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
      'NotoSansTC-Light',
      'NotoSansTC-Thin',
      'NotoSansTC-Black',
      'NotoSansTC-ExtraBold',
      'NotoSansTC_regular',
      'NotoSansTC_bold',
      'NotoSansTC_medium',
      'NotoSansTC_semiBold',
      'NotoSansTC_300',
      'NotoSansTC_400',
      'NotoSansTC_500',
      'NotoSansTC_700',
      'NotoSansTC_black',
      'Roboto',
      'Roboto_regular',
      'Roboto_bold',
      'AppFont',
      'Inter',
      'Inter-Regular',
      'Inter-Bold',
    ]) {
      try {
        final loader = FontLoader(name);
        loader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  final fontFile = File(r'C:\Windows\Fonts\kaiu.ttf');
  if (fontFile.existsSync()) {
    final fontBytes = fontFile.readAsBytesSync();
    for (final name in [
      'DFKai-SB',
      '標楷體',
    ]) {
      try {
        final loader = FontLoader(name);
        loader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  final emojiFile = File(r'C:\Windows\Fonts\seguiemj.ttf');
  if (emojiFile.existsSync()) {
    try {
      final emojiLoader = FontLoader('Segoe UI Emoji');
      emojiLoader.addFont(Future.value(ByteData.view(emojiFile.readAsBytesSync().buffer)));
      await emojiLoader.load();
    } catch (_) {}
  }
}

void registerMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter_callkit_incoming'),
    (MethodCall methodCall) async => true,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (MethodCall methodCall) async => <int, int>{0: 1, 1: 1, 7: 1, 15: 1},
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC/Method'),
    (MethodCall methodCall) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter_tts'),
    (MethodCall methodCall) async => 1,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall methodCall) async => 1,
  );
}

Future<void> captureScreen(
  WidgetTester tester,
  Widget widget,
  String filename, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final boundaryKey = GlobalKey();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData(
        fontFamily: 'NotoSansTC',
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 411.4,
            height: 914.3,
            child: widget,
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();

  final file = File('$outputDir\\$filename');
  file.writeAsBytesSync(bytes);
  print('--> Captured $filename (${bytes.length} bytes)');
}

final mockElder = Elder(
  id: 1,
  elderId: '1001',
  name: '王阿公',
  avatarUrl: '',
  location: '客廳',
);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    registerMocks();
    await loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'saved_role': 'elder',
      'saved_id': '1001',
      'user_role': 'elder',
      'access_token': 'dummy_token',
    });
  });

  testWidgets('12-1-1 Role identification', (tester) async {
    await captureScreen(tester, const IdentificationScreen(), 'fig_12_1_1_role_identification.png');
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-1-2 Login', (tester) async {
    await captureScreen(tester, const LoginScreen(), 'fig_12_1_2_login.png');
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-1 Elder home tab', (tester) async {
    await captureScreen(
      tester,
      const ElderHomeTab(
        userId: 1,
        userName: '王阿公',
        roomId: '1001',
      ),
      'fig_12_2_1_elder_home.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-2 Farmer almanac', (tester) async {
    await captureScreen(
      tester,
      FarmerAlmanacScreen(
        userName: '王阿公',
        initialDate: DateTime(2026, 9, 27),
      ),
      'fig_12_2_2_farmer_almanac.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-3 News player', (tester) async {
    await captureScreen(
      tester,
      NewsListenPlayerScreen(
        userId: 1,
        initialIndex: 0,
        newsItems: const [
          {
            'title': '中央氣象署秋季天氣提醒：早晚溫差顯著，長輩請適時增添保暖衣物',
            'content': '隨著秋分節氣到來，全台各地清晨與夜間氣溫逐漸轉涼，日夜溫差可達八至十度。氣象署特別提醒銀髮族朋友早晚外出散步時注意保暖，並保持規律水分補充。',
            'category': '生活健康',
            'source': '生活氣象快訊',
            'published_at': '2026-09-27 08:30',
          },
          {
            'title': '社區重陽敬老樂活健走嘉年華開放報名，鼓勵銀髮長青踴躍踏青',
            'content': '為提倡長者日常運動風氣，市府社會局將於十月舉辦千人健走嘉年華，現場設有健康量測、傳統童玩闖關與銀髮社交市集。',
            'category': '地方社區',
            'source': '市政快訊',
            'published_at': '2026-09-27 09:15',
          },
        ],
      ),
      'fig_12_2_3_news_player.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-4 Pet studio', (tester) async {
    await captureScreen(
      tester,
      const PetStudioScreen(
        userId: 1,
        userName: '王阿公',
        initialSteps: 4280,
      ),
      'fig_12_2_4_pet_studio.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-5 Zen pond', (tester) async {
    await captureScreen(
      tester,
      const ZenPondScreen(),
      'fig_12_2_5_zen_pond.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-6 Elder SOS emergency', (tester) async {
    await captureScreen(
      tester,
      const VideoCallScreen(
        roomId: '1001',
        isEmergency: true,
        isVideoCall: true,
      ),
      'fig_12_2_6_elder_sos.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-2-7 Elder video call', (tester) async {
    await captureScreen(
      tester,
      const VideoCallScreen(
        roomId: '1001',
        isEmergency: false,
        isVideoCall: true,
      ),
      'fig_12_2_7_elder_video_call.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-1 Family home tab', (tester) async {
    await captureScreen(
      tester,
      FamilyHomeTab(
        currentElder: mockElder,
        isElderOnline: true,
        elderZone: const {
          'zone': '客廳',
          'enteredAt': '10分鐘前',
          'present': true,
        },
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
      ),
      'fig_12_3_1_family_home.png',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: FamilyTheme.lightColorScheme,
        scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-2 Family interaction tab', (tester) async {
    await captureScreen(
      tester,
      FamilyInteractionTab(
        currentElder: mockElder,
        signaling: Signaling(),
        devicesMax: 5,
        tierDisplayName: '守護尊榮版',
        tierLevel: 'pro',
        userId: 1,
        monitorDevices: const [
          {'device_id': 'cctv_living', 'device_name': '客廳 AI 守護鏡頭', 'status': 'online', 'room_name': '客廳'},
          {'device_id': 'cctv_bedroom', 'device_name': '臥室監控鏡頭', 'status': 'online', 'room_name': '臥室'},
        ],
        elderZone: const {
          'zone': '客廳',
          'enteredAt': '10分鐘前',
          'present': true,
        },
        activeAlerts: const [],
      ),
      'fig_12_3_2_family_interaction.png',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: FamilyTheme.lightColorScheme,
        scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-3 Remote care hub', (tester) async {
    await captureScreen(
      tester,
      const RemoteCareHubScreen(
        elderId: 1,
        elderName: '王阿公',
      ),
      'fig_12_3_3_remote_care_hub.png',
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-4 Alert center', (tester) async {
    await captureScreen(
      tester,
      const AlertCenterScreen(
        elderName: '王阿公',
        elderId: 1,
        elderRoomId: '1001',
        activeAlerts: [
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
      ),
      'fig_12_3_4_alert_center.png',
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-5 Health reminder', (tester) async {
    await captureScreen(
      tester,
      const HealthReminderScreen(
        elderId: '1001',
        elderName: '王阿公',
        familyId: 1,
      ),
      'fig_12_3_5_health_reminder.png',
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-6 Memoirs gallery', (tester) async {
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_real_1',
      elderId: '1001',
      title: '廟口童玩與純真田埂時光',
      tag: '經典回憶',
      preview: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺...',
      fullStory: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺、彈彈珠，或者在剛收割完的稻田裡抓泥鰍烤地瓜。',
      promptQuestion: '小時候都玩什麼？',
      recordedDate: DateTime.now(),
    ));

    await captureScreen(
      tester,
      const MemoirsGalleryScreen(
        elderId: '1001',
        elderName: '王阿公',
      ),
      'fig_12_3_6_memoirs_gallery.png',
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-7 Caregiver pairing', (tester) async {
    await captureScreen(
      tester,
      const CaregiverPairingScreen(
        familyId: 1,
        familyName: '王大明',
      ),
      'fig_12_3_7_caregiver_pairing.png',
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-8 Family data tab', (tester) async {
    await captureScreen(
      tester,
      FamilyDataTab(
        currentElder: mockElder,
        userId: 1,
        userName: '王大明',
      ),
      'fig_12_3_8_family_data.png',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: FamilyTheme.lightColorScheme,
        scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('12-3-9 CCTV monitor', (tester) async {
    await captureScreen(
      tester,
      const VideoCallScreen(
        roomId: 'monitor_elder_1001',
        monitorViewOnly: true,
        isVideoCall: true,
        monitorDeviceName: '客廳 AI 守護鏡頭',
      ),
      'fig_12_3_9_cctv_monitor.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
