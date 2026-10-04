import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/api/api_client.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/screens/identification_screen.dart';
import 'package:flutter_application_1/screens/login_screen.dart';
import 'package:flutter_application_1/screens/elder_profile_onboarding_screen.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_home_tab.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_greeting_tab.dart';
import 'package:flutter_application_1/screens/elder_community_screen.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_chat_tab.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_profile_tab.dart';
import 'package:flutter_application_1/screens/almanac/farmer_almanac_screen.dart';
import 'package:flutter_application_1/screens/news_listen_player/news_listen_player_screen.dart';
import 'package:flutter_application_1/screens/elder_pairing_display_screen.dart';
import 'package:flutter_application_1/screens/video_call_screen.dart';
import 'package:flutter_application_1/screens/family/family_home_tab.dart';
import 'package:flutter_application_1/screens/family/family_interaction_tab.dart';
import 'package:flutter_application_1/screens/family/family_data_tab.dart';
import 'package:flutter_application_1/screens/family/elder_location_map_screen.dart';
import 'package:flutter_application_1/screens/family/family_ai_copilot_screen.dart';
import 'package:flutter_application_1/screens/family/family_friend_feed_body.dart';
import 'package:flutter_application_1/screens/family/alert_center_screen.dart';
import 'package:flutter_application_1/screens/family/health_reminder_screen.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';
import 'package:flutter_application_1/screens/caregiver_pairing_screen.dart';
import 'package:flutter_application_1/services/signaling.dart';
import 'package:flutter_application_1/services/memoir_service.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

final String outputDir = r'E:\114Project\Uban\Uban System Documents\章節性文件\Chapter 12\images';

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
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'checkPermission') return 3; // whileInUse
      if (methodCall.method == 'isLocationServiceEnabled') return true;
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC/Method'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'newVideoRenderer') return {'textureId': 1};
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC.Method'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'newVideoRenderer') return {'textureId': 1};
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC.Event'),
    (MethodCall methodCall) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC/Event'),
    (MethodCall methodCall) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.example.app/bring_to_front'),
    (MethodCall methodCall) async => true,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter_tts'),
    (MethodCall methodCall) async => 1,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall methodCall) async => 1,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (MethodCall methodCall) async => true,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (MethodCall methodCall) async => <String, Object>{},
  );
}

class RealFileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File('E:\\114Project\\Uban\\mobile_app\\$key');
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      return ByteData.view(bytes.buffer);
    }
    return rootBundle.load(key);
  }
}

Future<void> loadFonts() async {
  final fontDir = Directory(r'E:\114Project\Uban\mobile_app\assets\fonts');
  final regularFile = File(r'E:\114Project\Uban\mobile_app\assets\fonts\NotoSansTC-Regular.ttf');
  final regBytes = regularFile.existsSync() ? regularFile.readAsBytesSync() : null;

  // 1. StarPanda 字型 (僅載入至 StarPanda 家族，絕不污染 NotoSansTC)
  final starFile = File(r'E:\114Project\Uban\mobile_app\assets\fonts\StarPandaKids.otf');
  if (starFile.existsSync()) {
    final bytes = starFile.readAsBytesSync();
    for (final name in ['StarPanda', 'StarPandaKids', 'starPanda']) {
      try {
        final loader = FontLoader(name);
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  // 2. MaterialIcons 圖示字型 (專屬載入)
  final matFile = File(r'E:\114Project\Uban\mobile_app\assets\fonts\MaterialIcons-Regular.otf');
  if (matFile.existsSync()) {
    final bytes = matFile.readAsBytesSync();
    for (final name in ['MaterialIcons', 'materialicons', 'Material Icons', 'MaterialIcons-Regular']) {
      try {
        final loader = FontLoader(name);
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  // 3. CupertinoIcons 圖示字型 (專屬載入)
  final cupFile = File(r'E:\114Project\Uban\mobile_app\assets\fonts\CupertinoIcons.ttf');
  if (cupFile.existsSync()) {
    final bytes = cupFile.readAsBytesSync();
    for (final name in ['CupertinoIcons', 'packages/cupertino_icons/CupertinoIcons']) {
      try {
        final loader = FontLoader(name);
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  // 4. 為 GoogleFonts 與所有中文字重完整註冊 NotoSansTC
  if (regBytes != null) {
    for (final alias in [
      'NotoSansTC',
      'notoSansTc',
      'Noto Sans TC',
      'NotoSansTC_regular',
      'NotoSansTC_bold',
      'NotoSansTC_medium',
      'NotoSansTC_semiBold',
      'NotoSansTC_light',
      'NotoSansTC_thin',
      'NotoSansTC_black',
      'NotoSansTC_100',
      'NotoSansTC_200',
      'NotoSansTC_300',
      'NotoSansTC_400',
      'NotoSansTC_500',
      'NotoSansTC_600',
      'NotoSansTC_700',
      'NotoSansTC_800',
      'NotoSansTC_900',
      'NotoSansTC_w700',
      'NotoSansTC_normal',
      'Ahem', // 覆蓋 Ahem，杜絕任何可能的缺字方塊
      'Roboto',
      'Roboto-Regular',
      'Roboto_regular',
      'sans-serif',
    ]) {
      try {
        final loader = FontLoader(alias);
        loader.addFont(Future.value(ByteData.view(regBytes.buffer)));
        await loader.load();
      } catch (_) {}
    }
  }

  // 5. Inter 與通用英文字型
  if (fontDir.existsSync()) {
    for (final file in fontDir.listSync().whereType<File>()) {
      final p = file.path.toLowerCase();
      if (p.contains('inter') && (p.endsWith('.ttf') || p.endsWith('.otf'))) {
        final bytes = file.readAsBytesSync();
        final baseName = file.uri.pathSegments.last.replaceAll('.ttf', '').replaceAll('.otf', '');
        for (final name in [baseName, baseName.replaceAll('-', '_'), 'Inter']) {
          try {
            final loader = FontLoader(name);
            loader.addFont(Future.value(ByteData.view(bytes.buffer)));
            await loader.load();
          } catch (_) {}
        }
      }
    }
  }
}

Future<void> captureScreen(
  WidgetTester tester,
  Widget widget,
  String filename, {
  ThemeData? theme,
  Duration settleTime = const Duration(milliseconds: 600),
  Future<void> Function(WidgetTester)? onBeforeCapture,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final boundaryKey = GlobalKey();

  final baseTheme = theme ?? ThemeData(
    fontFamily: 'NotoSansTC',
    fontFamilyFallback: const ['NotoSansTC'],
    useMaterial3: true,
  );
  final effectiveTheme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(fontFamily: 'NotoSansTC'),
  );

  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: RealFileAssetBundle(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: effectiveTheme,
        home: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 411.4,
            height: 914.3,
            child: Scaffold(
              backgroundColor: effectiveTheme.scaffoldBackgroundColor,
              body: widget,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.runAsync(() async {
    await Future.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  if (onBeforeCapture != null) {
    await onBeforeCapture(tester);
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File('$outputDir\\$filename');
    await file.writeAsBytes(bytes);
    print('RENDERED_SUCCESS: $filename (${bytes.length} bytes)');
  });
}

class MapBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final roadPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 22
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), roadPaint);
    canvas.drawLine(Offset(0, size.height * 0.62), Offset(size.width, size.height * 0.62), roadPaint);
    canvas.drawLine(Offset(size.width * 0.45, 0), Offset(size.width * 0.45, size.height), roadPaint);
    canvas.drawLine(Offset(size.width * 0.8, 0), Offset(size.width * 0.8, size.height), roadPaint);

    final greenPaint = Paint()..color = const Color(0xFFDCFCE7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(20, size.height * 0.15, size.width * 0.35, 130), const Radius.circular(16)),
      greenPaint,
    );

    final geofencePaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.12)
      ..style = PaintingStyle.fill;
    final geofenceBorder = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width * 0.5, size.height * 0.45);
    canvas.drawCircle(center, 120, geofencePaint);
    canvas.drawCircle(center, 120, geofenceBorder);

    final trailPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.62)
      ..lineTo(size.width * 0.45, size.height * 0.62)
      ..lineTo(size.width * 0.45, size.height * 0.48)
      ..lineTo(center.dx, center.dy);
    canvas.drawPath(path, trailPaint);

    final dotPaint = Paint()..color = const Color(0xFF0284C7);
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.62), 5, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.62), 5, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.48), 5, dotPaint);

    final pinOuter = Paint()..color = const Color(0xFFEF4444).withOpacity(0.2);
    canvas.drawCircle(center, 20, pinOuter);
    final pinPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(center, 9, pinPaint);
    final pinCenter = Paint()..color = Colors.white;
    canvas.drawCircle(center, 3.5, pinCenter);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MockElderLocationMapScreen extends StatelessWidget {
  const MockElderLocationMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          '王阿公 的移動軌跡',
          style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Text('2026/10/03', style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F766E))),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: MapBackgroundPainter()),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
                ],
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '安全守護中：長輩目前位於常態生活圈（大安區新生南路）',
                      style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '目前即時位置',
                              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '台北市大安區新生南路二段 86 號',
                              style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text('最後定位：剛剛 (10:15)', style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.route_rounded, size: 15, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Text('今日累積移動 18 點', style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0284C7))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RealisticLivingRoomCctvPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Room Background
    final wallPaint = Paint()..color = const Color(0xFF1E2430);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.75), wallPaint);

    final floorPaint = Paint()..color = const Color(0xFF161B22);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.55, w, h * 0.45), floorPaint);

    // Floor perspective planks
    final floorLinePaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..strokeWidth = 1.5;
    for (int i = 0; i < 7; i++) {
      canvas.drawLine(
        Offset(w * (0.05 + i * 0.15), h * 0.55),
        Offset(w * (-0.1 + i * 0.2), h),
        floorLinePaint,
      );
    }

    // Modern Large Area Rug
    final rugRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.52, w * 0.84, h * 0.35),
      const Radius.circular(16),
    );
    final rugPaint = Paint()..color = const Color(0xFF2D3748);
    canvas.drawRRect(rugRect, rugPaint);

    // 2. Window on right with subtle sunlight
    final windowRect = Rect.fromLTWH(w * 0.68, h * 0.18, w * 0.26, h * 0.42);
    final winBorder = Paint()
      ..color = const Color(0xFF4A5568)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawRect(windowRect, winBorder);

    final sunGradient = ui.Gradient.linear(
      Offset(windowRect.left, windowRect.top),
      Offset(windowRect.right, windowRect.bottom),
      [const Color(0xFFEDF2F7), const Color(0xFFCBD5E0)],
    );
    canvas.drawRect(windowRect, Paint()..shader = sunGradient);
    canvas.drawLine(Offset(windowRect.center.dx, windowRect.top), Offset(windowRect.center.dx, windowRect.bottom), winBorder);
    canvas.drawLine(Offset(windowRect.left, windowRect.center.dy), Offset(windowRect.right, windowRect.center.dy), winBorder);

    // 3. Wall Art on left
    final artRect = Rect.fromLTWH(w * 0.10, h * 0.20, w * 0.22, h * 0.20);
    final artBorder = Paint()
      ..color = const Color(0xFF4A5568)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(artRect, artBorder);
    final artGrad = ui.Gradient.linear(
      Offset(artRect.left, artRect.top),
      Offset(artRect.right, artRect.bottom),
      [const Color(0xFF319795), const Color(0xFFD69E2E)],
    );
    canvas.drawRect(artRect, Paint()..shader = artGrad);

    // 4. Large Sectional Sofa
    final sofaBack = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.40, w * 0.58, h * 0.24),
      const Radius.circular(24),
    );
    canvas.drawRRect(sofaBack, Paint()..color = const Color(0xFF3B4A5A));

    final sofaCushion = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.48, w * 0.54, h * 0.16),
      const Radius.circular(18),
    );
    canvas.drawRRect(sofaCushion, Paint()..color = const Color(0xFF2A3644));

    // Throw pillow
    final pillowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.43, w * 0.12, h * 0.08),
      const Radius.circular(8),
    );
    canvas.drawRRect(pillowRect, Paint()..color = const Color(0xFFD97706));

    // Monstera houseplant on left
    final plantPot = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.47, w * 0.10, h * 0.09),
      const Radius.circular(6),
    );
    canvas.drawRRect(plantPot, Paint()..color = const Color(0xFFC05621));
    final leafPaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(Offset(w * 0.12, h * 0.44), 16, leafPaint);
    canvas.drawCircle(Offset(w * 0.08, h * 0.42), 14, leafPaint);
    canvas.drawCircle(Offset(w * 0.15, h * 0.41), 15, leafPaint);

    // 5. Elder Figure sitting on Sofa
    final elderX = w * 0.46;
    final elderY = h * 0.46;

    // Body / Cardigan (Warm Amber / Ochre)
    final bodyPaint = Paint()..color = const Color(0xFFD97706);
    final bodyPath = Path()
      ..moveTo(elderX - 30, elderY - 30)
      ..lineTo(elderX + 30, elderY - 30)
      ..lineTo(elderX + 36, elderY + 45)
      ..lineTo(elderX - 36, elderY + 45)
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // Legs / Pants (Deep Navy)
    final pantsPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Rect.fromLTWH(elderX - 28, elderY + 45, 24, 60), pantsPaint);
    canvas.drawRect(Rect.fromLTWH(elderX + 4, elderY + 45, 24, 60), pantsPaint);

    // Head / Face
    final facePaint = Paint()..color = const Color(0xFFFDE68A);
    canvas.drawCircle(Offset(elderX, elderY - 55), 20, facePaint);

    // Silver Hair
    final hairPaint = Paint()..color = const Color(0xFFE2E8F0);
    final hairPath = Path()
      ..addArc(Rect.fromCircle(center: Offset(elderX, elderY - 58), radius: 21), 3.14, 3.14);
    canvas.drawPath(hairPath, hairPaint);

    // Glasses
    final glassesPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(elderX - 7, elderY - 55), 5, glassesPaint);
    canvas.drawCircle(Offset(elderX + 7, elderY - 55), 5, glassesPaint);
    canvas.drawLine(Offset(elderX - 2, elderY - 55), Offset(elderX + 2, elderY - 55), glassesPaint);

    // Book/Tablet in hands
    final tabletRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(elderX, elderY + 12), width: 34, height: 22),
      const Radius.circular(4),
    );
    canvas.drawRRect(tabletRect, Paint()..color = Colors.white);

    // 6. Wooden Coffee Table in foreground
    final tableRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.28, h * 0.60, w * 0.36, h * 0.08),
      const Radius.circular(8),
    );
    canvas.drawRRect(tableRect, Paint()..color = const Color(0xFF78350F));
    final legPaint = Paint()
      ..color = const Color(0xFF451A03)
      ..strokeWidth = 5;
    canvas.drawLine(Offset(w * 0.32, h * 0.68), Offset(w * 0.31, h * 0.74), legPaint);
    canvas.drawLine(Offset(w * 0.60, h * 0.68), Offset(w * 0.61, h * 0.74), legPaint);

    // Teacup on table
    final cupPaint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.34, h * 0.58, 14, 12), const Radius.circular(2)),
      cupPaint,
    );

    // 7. Edge AI Bounding Box & Pose Skeleton
    final boxRect = Rect.fromLTWH(elderX - 60, elderY - 85, 120, 205);

    // Cyan Bounding Box
    final boxPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final cornerLen = 16.0;
    final bp = Path()
      ..moveTo(boxRect.left, boxRect.top + cornerLen)
      ..lineTo(boxRect.left, boxRect.top)
      ..lineTo(boxRect.left + cornerLen, boxRect.top)
      ..moveTo(boxRect.right - cornerLen, boxRect.top)
      ..lineTo(boxRect.right, boxRect.top)
      ..lineTo(boxRect.right, boxRect.top + cornerLen)
      ..moveTo(boxRect.left, boxRect.bottom - cornerLen)
      ..lineTo(boxRect.left, boxRect.bottom)
      ..lineTo(boxRect.left + cornerLen, boxRect.bottom)
      ..moveTo(boxRect.right - cornerLen, boxRect.bottom)
      ..lineTo(boxRect.right, boxRect.bottom)
      ..lineTo(boxRect.right, boxRect.bottom - cornerLen);
    canvas.drawPath(bp, boxPaint);

    // AI Confidence Tag
    final tagBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(boxRect.left + 5, boxRect.top - 24, 145, 20),
      const Radius.circular(6),
    );
    canvas.drawRRect(tagBg, Paint()..color = const Color(0xFF00C853));

    final tagTp = TextPainter(
      text: const TextSpan(
        text: '長輩 (98%) • 姿態正常',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'NotoSansTC',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tagTp.paint(canvas, Offset(boxRect.left + 12, boxRect.top - 21));

    // 17-Point Pose Skeleton
    final jointPaint = Paint()..color = const Color(0xFFE0F7FA);
    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.85)
      ..strokeWidth = 2.0;

    final nose = Offset(elderX, elderY - 55);
    final lShoulder = Offset(elderX - 22, elderY - 26);
    final rShoulder = Offset(elderX + 22, elderY - 26);
    final lElbow = Offset(elderX - 32, elderY + 2);
    final rElbow = Offset(elderX + 32, elderY + 2);
    final lWrist = Offset(elderX - 16, elderY + 14);
    final rWrist = Offset(elderX + 16, elderY + 14);
    final lHip = Offset(elderX - 16, elderY + 45);
    final rHip = Offset(elderX + 16, elderY + 45);
    final lKnee = Offset(elderX - 18, elderY + 80);
    final rKnee = Offset(elderX + 18, elderY + 80);
    final lAnkle = Offset(elderX - 20, elderY + 102);
    final rAnkle = Offset(elderX + 20, elderY + 102);

    void drawBone(Offset p1, Offset p2) => canvas.drawLine(p1, p2, bonePaint);
    drawBone(nose, Offset(elderX, elderY - 26));
    drawBone(lShoulder, rShoulder);
    drawBone(lShoulder, lElbow);
    drawBone(lElbow, lWrist);
    drawBone(rShoulder, rElbow);
    drawBone(rElbow, rWrist);
    drawBone(lShoulder, lHip);
    drawBone(rShoulder, rHip);
    drawBone(lHip, rHip);
    drawBone(lHip, lKnee);
    drawBone(lKnee, lAnkle);
    drawBone(rHip, rKnee);
    drawBone(rKnee, rAnkle);

    for (final pt in [nose, lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist, lHip, rHip, lKnee, rKnee, lAnkle, rAnkle]) {
      canvas.drawCircle(pt, 3.5, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MockCctvMonitorScreen extends StatelessWidget {
  const MockCctvMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 沉浸式視訊畫面 (含邊緣 AI 姿態辨識與綠色標籤)
          Positioned.fill(
            child: CustomPaint(painter: RealisticLivingRoomCctvPainter()),
          ),

          // 2. 頂部返回膠囊 (比照 video_call_screen.dart:1115 widget.returnByPop == true)
          Positioned(
            top: 56,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white30, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '返回',
                    style: GoogleFonts.notoSansTc(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. 底部懸浮毛玻璃控制列 (比照 video_call_screen.dart:1224 monitorViewOnly == true 僅有擴音與麥克風)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 擴音監聽
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Colors.white12,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.volume_up,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      // 麥克風對講
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Colors.white12,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  HttpServer? mockServer;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    registerMocks();
    await loadFonts();

    mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiClient.overrideBaseUrl = 'http://127.0.0.1:${mockServer!.port}/api';
    mockServer!.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path.contains('emotion_events')) {
        request.response.write(jsonEncode({
          'status': 'success',
          'data': {
            'available': true,
            'events': [],
          }
        }));
      } else if (path.contains('subscription')) {
        request.response.write(jsonEncode({
          'status': 'success',
          'tier_level': 'diamond',
        }));
      } else if (path.contains('elder')) {
        request.response.write(jsonEncode({
          'status': 'success',
          'data': {
            'id': 1001,
            'name': '王阿公',
            'age': 78,
          }
        }));
      } else {
        request.response.write(jsonEncode({
          'status': 'success',
          'data': {}
        }));
      }
      request.response.close();
    });
  });

  tearDownAll(() async {
    await mockServer?.close(force: true);
  });

  setUp(() {
    registerMocks();
    SharedPreferences.setMockInitialValues({
      'caregiver_id': 1,
      'caregiver_name': '王大明',
      'user_role': 'family',
      'elder_id': '1001',
      'elder_name': '王阿公',
      'dark_mode': false,
      'access_token': 'dummy_token',
    });
  });

  final mockElder = Elder(
    id: 1001,
    elderId: '1001',
    name: '王阿公',
    gender: '男',
    age: 78,
    location: '客廳',
    appellation: '爸爸',
  );

  // ==========================================
  // 12-1 系統通用登入與身分確認
  // ==========================================
  testWidgets('12-1-1 Role identification', (tester) async {
    SharedPreferences.setMockInitialValues({}); // No active session to prevent releaseIfBound hang
    await captureScreen(tester, const IdentificationScreen(), 'fig_12_1_1_role_identification.png');
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-1-2 Login', (tester) async {
    await captureScreen(
      tester,
      const LoginScreen(),
      'fig_12_1_2_login.png',
      onBeforeCapture: (tester) async {
        final textFields = find.byType(TextField);
        if (textFields.evaluate().isNotEmpty) {
          await tester.enterText(textFields.first, 'Boyo@uban.com');
        }
        if (textFields.evaluate().length > 1) {
          await tester.enterText(textFields.at(1), 'robert20040924');
        }
      },
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-1-3 Elder onboarding', (tester) async {
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
  }, timeout: const Timeout(Duration(seconds: 15)));

  // ==========================================
  // 12-2 長者專用端操作手冊
  // ==========================================
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
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-2 Farmer almanac', (tester) async {
    await captureScreen(
      tester,
      const FarmerAlmanacScreen(),
      'fig_12_2_2_farmer_almanac.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

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
            'published_at': '2026-10-02 08:30',
            'audio_url': '/api/static/sample.mp3',
          },
          {
            'title': '社區重陽敬老樂活健走嘉年華開放報名，鼓勵銀髮長青踴躍踏青',
            'content': '為提倡長者日常運動風氣，市府社會局將於十月舉辦千人健走嘉年華，現場設有健康量測、傳統童玩闖關與銀髮社交市集。',
            'category': '地方社區',
            'source': '市政快訊',
            'published_at': '2026-10-02 09:15',
            'audio_url': '/api/static/sample2.mp3',
          },
        ],
      ),
      'fig_12_2_3_news_player.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-4 Elder greeting phone tab', (tester) async {
    await captureScreen(
      tester,
      const ElderGreetingTab(
        userId: 1,
        userName: '王阿公',
      ),
      'fig_12_2_4_elder_greeting_phone.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-5 Elder community', (tester) async {
    await captureScreen(
      tester,
      const ElderCommunityScreen(
        userId: 1,
        userName: '王阿公',
        showFriendTab: false,
      ),
      'fig_12_2_5_elder_community.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-6 Elder chat tab', (tester) async {
    await captureScreen(
      tester,
      ElderChatTab(
        userId: 1,
        onBackToHome: () {},
      ),
      'fig_12_2_6_elder_chat.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-7 Elder profile pet tab', (tester) async {
    await captureScreen(
      tester,
      const ElderProfileTab(
        userId: 1,
        userName: '王阿公',
      ),
      'fig_12_2_7_elder_profile_pet.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-8 Global assistant help dialog', (tester) async {
    final helpDialog = Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '阿公阿嬤安心救生圈',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              '遇到看不懂或按不出來？點選下方隨時幫您：',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.mic_rounded, size: 28),
              label: const Text('聽小嘎說話（語音幫忙）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D78),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.menu_book_rounded, size: 24),
              label: const Text('觀看本頁功能導覽', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D78),
                side: const BorderSide(color: Color(0xFF2E7D78), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.phone_rounded, color: Color(0xFF0284C7), size: 24),
              label: const Text('撥打電話給家人', style: TextStyle(fontSize: 17, color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    await captureScreen(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Center(child: helpDialog),
      ),
      'fig_12_2_8_global_assistant.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-9 Elder SOS emergency', (tester) async {
    await captureScreen(
      tester,
      const VideoCallScreen(
        roomId: '1001',
        isEmergency: true,
        isVideoCall: true,
      ),
      'fig_12_2_9_elder_sos.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-10 Elder video call', (tester) async {
    await captureScreen(
      tester,
      const VideoCallScreen(
        roomId: '1001',
        isEmergency: false,
        isVideoCall: true,
      ),
      'fig_12_2_10_elder_video_call.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-2-11 Elder pairing display', (tester) async {
    await captureScreen(
      tester,
      const ElderPairingDisplayScreen(),
      'fig_12_2_11_elder_pairing_display.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  // ==========================================
  // 12-3 家屬守護端操作手冊
  // ==========================================
  testWidgets('12-3-1 Family home tab', (tester) async {
    await captureScreen(
      tester,
      FamilyHomeTab(
        currentElder: mockElder,
        isElderOnline: true,
        userId: 1,
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
            'timestamp': '2026-10-02 10:15:20',
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
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-2 Elder location map', (tester) async {
    await captureScreen(
      tester,
      const MockElderLocationMapScreen(),
      'fig_12_3_2_elder_location_map.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-3 Family AI copilot', (tester) async {
    await captureScreen(
      tester,
      FamilyAiCopilotScreen(currentElder: mockElder),
      'fig_12_3_3_family_ai_copilot.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-4 Family interaction tab', (tester) async {
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
      'fig_12_3_4_family_interaction.png',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: FamilyTheme.lightColorScheme,
        scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-5 Family friend feed', (tester) async {
    await captureScreen(
      tester,
      Scaffold(
        appBar: AppBar(
          title: const Text('家庭生活時光牆', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
        ),
        body: const FamilyFriendFeedBody(
          familyId: 1,
          familyName: '王大明',
        ),
      ),
      'fig_12_3_5_family_friend_feed.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-6 CCTV monitor', (tester) async {
    await captureScreen(
      tester,
      const MockCctvMonitorScreen(),
      'fig_12_3_6_cctv_monitor.png',
    );
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('12-3-7 Alert center', (tester) async {
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
            'timestamp': '2026-10-02 10:15:20',
            'severity': 'critical',
            'message': 'AI 影像偵測到疑似跌倒姿態，請立即確認！',
          }
        ],
      ),
      'fig_12_3_7_alert_center.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-8 Health reminder', (tester) async {
    await captureScreen(
      tester,
      const HealthReminderScreen(
        elderId: '1001',
        elderName: '王阿公',
        familyId: 1,
      ),
      'fig_12_3_8_health_reminder.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-9 Memoirs gallery', (tester) async {
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
      'fig_12_3_9_memoirs_gallery.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-10 Caregiver pairing', (tester) async {
    await captureScreen(
      tester,
      const CaregiverPairingScreen(
        familyId: 1,
        familyName: '王大明',
      ),
      'fig_12_3_10_caregiver_pairing.png',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('12-3-11 Family data tab', (tester) async {
    await captureScreen(
      tester,
      FamilyDataTab(
        currentElder: mockElder,
        userId: 1,
        userName: '王大明',
      ),
      'fig_12_3_11_family_data.png',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: FamilyTheme.lightColorScheme,
        scaffoldBackgroundColor: FamilyTheme.lightColorScheme.surface,
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
