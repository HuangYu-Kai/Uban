import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/family/memoirs_gallery_screen.dart';
import 'package:flutter_application_1/models/memoir_story.dart';
import 'package:flutter_application_1/services/memoir_service.dart';

Future<void> loadFonts() async {
  final iconBytes = File(r'C:\Users\OuO\.vscode\extensions\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf').readAsBytesSync();
  final iconLoader = FontLoader('MaterialIcons');
  iconLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
  await iconLoader.load();

  final fontBytes = File(r'C:\Windows\Fonts\kaiu.ttf').readAsBytesSync();
  for (final name in [
    'NotoSansTC_regular',
    'NotoSansTC_bold',
    'NotoSansTC_medium',
    'NotoSansTC_black',
    'NotoSansTC_300',
    'NotoSansTC_400',
    'NotoSansTC_500',
    'NotoSansTC_700',
    'NotoSansTC',
    'Roboto_regular',
    'Roboto_bold',
    'Roboto',
  ]) {
    try {
      final loader = FontLoader(name);
      loader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
      await loader.load();
    } catch (e) {
      print('Error loading $name: $e');
    }
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Capture MemoirsGalleryScreen screenshot with exact font families', (WidgetTester tester) async {
    await MemoirService.instance.saveMemoir(MemoirStory(
      id: 'story_real_1',
      elderId: 'elder_test',
      title: '廟口童玩與純真田埂時光',
      tag: '經典回憶',
      preview: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺...',
      fullStory: '那時候放學鞋子一脫，大家就衝到廟埕前打陀螺、彈彈珠，或者在剛收割完的稻田裡抓泥鰍烤地瓜。',
      promptQuestion: '小時候都玩什麼？',
      recordedDate: DateTime.now(),
    ));

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: boundaryKey,
          child: const SizedBox(
            width: 400,
            height: 800,
            child: MemoirsGalleryScreen(
              elderId: 'elder_test',
              elderName: '王阿公',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File('test_memoirs_output.png');
    file.writeAsBytesSync(bytes);
    print('Screenshot saved successfully: ${file.lengthSync()} bytes');
  });
}
