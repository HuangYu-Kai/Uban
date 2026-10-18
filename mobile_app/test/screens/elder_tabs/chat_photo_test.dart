// ★ 2026-10-17 拍照問小嘎：聊天頁傳照片相關元件的測試。
//
// 涵蓋：選照片底部選單（拍照／從相簿選／取消）、使用者照片氣泡、輸入列的相機鈕
// （360dp 不溢位、停用時不回應）、上傳回應解析、選圖錯誤訊息。
// 整頁 ElderChatScreen 依賴語音辨識、TTS、喚醒詞等外掛，無法在 widget test 載入，
// 所以只測抽出來的小元件。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/chat/chat_photo.dart';
import 'package:flutter_application_1/screens/elder_tabs/chat/chat_widgets.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

// 1x1 透明 PNG
final _png = MemoryImage(Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]));

Widget _app(Widget child, {bool dark = false, double textScale = 1.0}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Theme(
        data: dark ? buildAppDarkTheme(context) : buildAppTheme(context),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('extractUploadedImageUrl', () {
    test('成功回應取出相對網址', () {
      expect(
        extractUploadedImageUrl({
          'status': 'success',
          'data': {'image_url': '/uploads/abc.jpg'},
        }),
        '/uploads/abc.jpg',
      );
    });

    test('錯誤或格式不符一律回 null', () {
      expect(extractUploadedImageUrl({'error': 'Failed: 500'}), isNull);
      expect(extractUploadedImageUrl({'status': 'error'}), isNull);
      expect(extractUploadedImageUrl({'status': 'success'}), isNull);
      expect(
          extractUploadedImageUrl(
              {'status': 'success', 'data': {'image_url': ' '}}),
          isNull);
      expect(
          extractUploadedImageUrl({'status': 'success', 'data': 'x'}), isNull);
    });
  });

  group('chatPhotoPickErrorMessage', () {
    test('相機／相簿權限被拒給出對應說明', () {
      expect(
          chatPhotoPickErrorMessage(
              PlatformException(code: 'camera_access_denied'),
              ImageSource.camera),
          contains('相機權限'));
      expect(
          chatPhotoPickErrorMessage(
              PlatformException(code: 'photo_access_denied'),
              ImageSource.gallery),
          contains('相簿權限'));
    });

    test('其他錯誤依來源給通用說明', () {
      expect(chatPhotoPickErrorMessage(Exception('x'), ImageSource.camera),
          contains('相機暫時無法使用'));
      expect(chatPhotoPickErrorMessage(Exception('x'), ImageSource.gallery),
          contains('相簿暫時無法開啟'));
    });
  });

  group('ChatPhotoSourceSheet', () {
    Future<ImageSource?> open(WidgetTester tester, Finder tapTarget) async {
      ImageSource? result;
      var done = false;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showChatPhotoSourceSheet(context);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('從相簿選'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(tapTarget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(done, isTrue);
      return result;
    }

    testWidgets('點「拍照」回傳 camera', (tester) async {
      expect(
          await open(tester, find.byKey(const ValueKey('chat_photo_camera'))),
          ImageSource.camera);
    });

    testWidgets('點「從相簿選」回傳 gallery', (tester) async {
      expect(
          await open(tester, find.byKey(const ValueKey('chat_photo_gallery'))),
          ImageSource.gallery);
    });

    testWidgets('點「取消」回傳 null', (tester) async {
      expect(
          await open(tester, find.byKey(const ValueKey('chat_photo_cancel'))),
          isNull);
    });

    for (final dark in [false, true]) {
      testWidgets('360x640、字級 1.5、${dark ? "深色" : "淡色"}無溢位且按鈕高 ≥72',
          (tester) async {
        _phone(tester, const Size(360, 640));
        await tester.pumpWidget(_app(
          const Align(
              alignment: Alignment.bottomCenter, child: ChatPhotoSourceSheet()),
          dark: dark,
          textScale: 1.5,
        ));
        await tester.pump();
        for (final k in [
          'chat_photo_camera',
          'chat_photo_gallery',
          'chat_photo_cancel'
        ]) {
          expect(tester.getSize(find.byKey(ValueKey(k))).height,
              greaterThanOrEqualTo(72));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ChatPhotoBubbleContent', () {
    testWidgets('縮圖 160x160 並顯示文字，窄螢幕不溢位', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: ChatBubbleFrame(
            isUser: true,
            child: ChatPhotoBubbleContent(
              image: _png,
              text: kChatPhotoDefaultText,
              textColor: Colors.white,
            ),
          ),
        ),
        textScale: 1.3,
      ));
      await tester.pump();
      expect(find.text('請幫我看這張照片'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('chat_photo_thumb'))),
          const Size(kChatPhotoThumbSize, kChatPhotoThumbSize));
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatInputBar 相機鈕', () {
    Widget bar({
      required bool voiceMode,
      VoidCallback? onCamera,
      bool cameraEnabled = true,
    }) =>
        Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            voiceMode: voiceMode,
            isListening: false,
            onToggleMode: () {},
            onHoldStart: () {},
            onHoldEnd: () {},
            controller: TextEditingController(),
            onSend: () {},
            bottomPadding: 16,
            onCamera: onCamera,
            cameraEnabled: cameraEnabled,
          ),
        );

    testWidgets('沒給 onCamera 時不顯示相機鈕（舊呼叫端不受影響）', (tester) async {
      await tester.pumpWidget(_app(bar(voiceMode: true)));
      await tester.pump();
      expect(find.byKey(const ValueKey('chat_camera_button')), findsNothing);
    });

    for (final voice in [true, false]) {
      for (final dark in [false, true]) {
        testWidgets(
            '360x640、字級 1.3、${voice ? "語音" : "鍵盤"}列、${dark ? "深色" : "淡色"}：相機鈕 56x56 且無溢位',
            (tester) async {
          _phone(tester, const Size(360, 640));
          await tester.pumpWidget(_app(bar(voiceMode: voice, onCamera: () {}),
              dark: dark, textScale: 1.3));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
              tester.getSize(find.byKey(const ValueKey('chat_camera_button'))),
              const Size(56, 56));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('啟用時點擊會呼叫回呼；停用時不回應', (tester) async {
      var taps = 0;
      await tester
          .pumpWidget(_app(bar(voiceMode: true, onCamera: () => taps++)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_camera_button')));
      await tester.pump();
      expect(taps, 1);

      await tester.pumpWidget(_app(
          bar(voiceMode: true, onCamera: () => taps++, cameraEnabled: false)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_camera_button')),
          warnIfMissed: false);
      await tester.pump();
      expect(taps, 1);
    });
  });
}
