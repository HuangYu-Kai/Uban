import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/chat/chat_images.dart';
import 'package:flutter_application_1/services/api/family_updates_api.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

Future<void> pumpBubble(WidgetTester t, List<String> urls,
    {bool dark = false}) async {
  t.view.physicalSize = const Size(360, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: [dark ? UbanColors.dark : UbanColors.light]),
    home: MediaQuery(
      data: const MediaQueryData(
          size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ChatImageGallery(images: urls),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  test('聊天紀錄照片解碼：舊紀錄（無欄位）→ 空；有欄位原樣還原', () {
    expect(decodeChatImages(null), isEmpty);
    expect(decodeChatImages('x'), isEmpty);
    expect(decodeChatImages(['/uploads/a.jpg', '', null, ' b.jpg ']),
        ['/uploads/a.jpg', 'b.jpg']);
  });

  test('opening 解析：有內容／無內容／格式不合', () {
    final o = FamilyOpening.tryParse({
      'status': 'success',
      'data': {
        'message': '璿OwO 分享了今天的午餐',
        'images': ['/uploads/community/x.jpg', ''],
        'items': [
          {'kind': 'post', 'item_id': 7},
          'bad',
        ],
      }
    })!;
    expect(o.message, '璿OwO 分享了今天的午餐');
    expect(o.images, ['/uploads/community/x.jpg']);
    expect(o.items, [
      {'kind': 'post', 'item_id': 7}
    ]);
    expect(
        FamilyOpening.tryParse({
          'status': 'success',
          'data': {'message': null, 'images': [], 'items': []}
        }),
        isNull);
    expect(FamilyOpening.tryParse({'status': 'error'}), isNull);
    expect(FamilyOpening.tryParse(null), isNull);
  });

  test('imageUrl：相對路徑補主機、絕對網址原樣', () {
    expect(ElderFamilyUpdatesApi.imageUrl('https://a.b/c.jpg'),
        'https://a.b/c.jpg');
    expect(ElderFamilyUpdatesApi.imageUrl('/uploads/c.jpg'),
        endsWith('/uploads/c.jpg'));
    expect(ElderFamilyUpdatesApi.imageUrl('/uploads/c.jpg'),
        startsWith('http'));
  });

  for (final dark in [false, true]) {
    for (final n in [1, 2, 3]) {
      testWidgets('照片氣泡 $n 張 360x640 1.3x ${dark ? "深" : "淺"}色無 overflow',
          (t) async {
        await pumpBubble(t, [for (var i = 0; i < n; i++) '/uploads/$i.jpg'],
            dark: dark);
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('chat_image_tile')), findsNWidgets(n));
      });
    }
  }

  testWidgets('點照片開全螢幕、可關閉', (t) async {
    await pumpBubble(t, ['/uploads/0.jpg']);
    await t.tap(find.byKey(const ValueKey('chat_image_tile')));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chat_image_close')));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
