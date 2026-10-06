import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_greeting_tab.dart';
import 'package:flutter_application_1/screens/elder_tabs/greeting/greeting_template_manifest.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// 測試用的暫時清單（正式清單由另一份資源提供）。
final String _fixtureManifest = jsonEncode([
  {
    'id': 'lotus_t1',
    'file': 'lotus_t1.jpg',
    'category': 'lotus',
    'title': '蓮開福至',
    'text_position': 'topRight',
    'dark_bg': true
  },
  {
    'id': 'koi_t1',
    'file': 'koi_t1.jpg',
    'category': 'koi',
    'title': '年年有餘',
    'text_position': 'bottomLeft',
    'dark_bg': false
  },
  {
    'id': 'koi_t2',
    'file': 'koi_t2.jpg',
    'category': 'koi',
    'title': '鯉躍龍門',
    'text_position': 'topCenter',
    'dark_bg': false
  },
  {
    'id': 'lake_t1',
    'file': 'lake_t1.jpg',
    'category': 'lake',
    'title': '湖光山色',
    'text_position': 'topLeft',
    'dark_bg': true
  },
]);

class _FakeBundle extends CachingAssetBundle {
  final String? manifest;
  _FakeBundle(this.manifest);

  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('no asset $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == kGreetingTemplateManifestPath && manifest != null) {
      return manifest!;
    }
    throw FlutterError('Unable to load asset: $key');
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('manifest 解析', () {
    test('合法清單全部讀入並對應欄位', () {
      final list = parseGreetingManifest(_fixtureManifest);
      expect(list.map((e) => e.id), ['lotus_t1', 'koi_t1', 'koi_t2', 'lake_t1']);
      expect(list.first.textPosition, 'topRight');
      expect(list.first.darkBg, isTrue);
      expect(list[1].darkBg, isFalse);
      expect(list.first.assetPath,
          'assets/images/greeting_templates/lotus_t1.jpg');
    });

    test('file 可為完整路徑或只有檔名，兩種都不會重複前綴', () {
      final list = parseGreetingManifest(jsonEncode([
        {'id': 'a', 'file': 'assets/images/greeting_templates/a.jpg', 'category': 'koi', 'title': '甲'},
        {'id': 'b', 'file': 'b.jpg', 'category': 'koi', 'title': '乙'},
      ]));
      expect(list[0].assetPath, 'assets/images/greeting_templates/a.jpg');
      expect(list[1].assetPath, 'assets/images/greeting_templates/b.jpg');
    });

    test('正式 manifest.json：全部可解析，且每個 assetPath 在磁碟上存在', () {
      final raw = File(kGreetingTemplateManifestPath).readAsStringSync();
      final list = parseGreetingManifest(raw);
      final rawCount = (jsonDecode(raw) as List).length;
      expect(list.length, rawCount, reason: '有項目被當成壞資料略過');
      expect(list, isNotEmpty);
      for (final e in list) {
        expect(File(e.assetPath).existsSync(), isTrue, reason: e.assetPath);
      }
    });

    test('缺檔案／空字串／非 JSON／非陣列 → 空清單', () {
      expect(parseGreetingManifest(null), isEmpty);
      expect(parseGreetingManifest('  '), isEmpty);
      expect(parseGreetingManifest('{bad json'), isEmpty);
      expect(parseGreetingManifest('{"id":"x"}'), isEmpty);
      expect(parseGreetingManifest('[]'), isEmpty);
    });

    test('壞的單筆被略過、好的保留；重複 id 只留第一筆', () {
      final raw = jsonEncode([
        {'id': 'ok1', 'file': 'a.jpg', 'category': 'tea', 'title': '好茶'},
        {'id': '', 'file': 'a.jpg', 'category': 'tea', 'title': '空id'},
        {'id': 'nofile', 'category': 'tea', 'title': '沒檔案'},
        {'id': 'badcat', 'file': 'a.jpg', 'category': 'ocean', 'title': '海'},
        {'id': 'notitle', 'file': 'a.jpg', 'category': 'tea'},
        {'id': 'evil', 'file': '../x.jpg', 'category': 'tea', 'title': '路徑'},
        {'id': 'ok1', 'file': 'b.jpg', 'category': 'tea', 'title': '重複'},
        {
          'id': 'ok2',
          'file': 'c.jpg',
          'category': 'flower',
          'title': '花',
          'text_position': 'nowhere',
          'dark_bg': 'yes'
        },
        'string',
        42,
        null,
      ]);
      final list = parseGreetingManifest(raw);
      expect(list.map((e) => e.id), ['ok1', 'ok2']);
      expect(list.first.title, '好茶');
      // 未知 text_position 退回 topLeft；dark_bg 不是 bool 視為 false
      expect(list[1].textPosition, 'topLeft');
      expect(list[1].darkBg, isFalse);
    });

    test('loadGreetingManifest：檔案不存在 → 空清單；有檔 → 解析', () async {
      expect(await loadGreetingManifest(_FakeBundle(null)), isEmpty);
      expect((await loadGreetingManifest(_FakeBundle(_fixtureManifest))).length, 4);
    });
  });

  group('圖庫分組', () {
    test('依固定順序分組、zh-TW 標題、空分類不出現', () {
      final entries = parseGreetingManifest(_fixtureManifest)
          .map(classicTemplateFromEntry)
          .toList();
      final sections = groupGalleryByCategory<ClassicPhotoTemplate>(
          entries, (t) => t.category);
      expect(sections.map((s) => s.label), ['蓮花', '錦鯉', '湖景']);
      expect(sections[1].items.length, 2);
    });

    test('未知分類歸到最後的「其他」', () {
      final sections = groupGalleryByCategory<String>(
          ['a:koi', 'b:???', 'c:lotus'], (s) => s.split(':')[1]);
      expect(sections.map((s) => s.label), ['蓮花', '錦鯉', '其他']);
    });

    test('8 個新分類標題完整', () {
      expect(
        [for (final c in kGreetingManifestCategories) kGreetingCategoryLabels[c]]
          ..sort(),
        (['蓮花', '錦鯉', '日出', '竹林', '高山雲海', '茶園', '花卉', '湖景']..sort()),
      );
    });

    test('text_position 與 dark_bg 轉成既有的對齊與字色系統', () {
      final e = parseGreetingManifest(_fixtureManifest);
      final lotus = classicTemplateFromEntry(e[0]);
      expect(lotus.textAlign, Alignment.topRight);
      expect(lotus.defaultColor, const Color(0xFFFEF08A)); // 深色底 → 亮字
      final koi = classicTemplateFromEntry(e[1]);
      expect(koi.textAlign, Alignment.bottomLeft);
      expect(koi.defaultColor, const Color(0xFF0052D4)); // 淺色底 → 寶藍字
      expect(classicTemplateFromEntry(e[2]).textAlign, Alignment.topCenter);
      expect(classicTemplateFromEntry(e[3]).textAlign, Alignment.topLeft);
      expect(koi.defaultMain.split('\n').length, 3);
    });
  });

  group('畫面', () {
    Widget host(AssetBundle? bundle) => MaterialApp(
          theme: ThemeData(
              extensions: <ThemeExtension<dynamic>>[UbanColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ElderGreetingTab(
                  userId: 1, userName: '測試', embedded: true, assetBundle: bundle),
            ),
          ),
        );

    Future<void> boot(WidgetTester tester, AssetBundle bundle) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(bundle));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('AI 智能生圖已移除：沒有模式切換與 AI 按鈕', (tester) async {
      await boot(tester, _FakeBundle(null));
      expect(find.text('經典圖文組合'), findsNothing);
      expect(find.text('AI 智能生圖'), findsNothing);
      expect(find.textContaining('AI 重新繪製'), findsNothing);
      expect(find.textContaining('3D 萌寵立體日曆'), findsNothing);
      expect(find.text('換句好話'), findsOneWidget);
      expect(find.text('換字體款式'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting_pig_toggle')), findsOneWidget);
    });

    testWidgets('清單不存在：圖庫只有內建範本（無例外）', (tester) async {
      await boot(tester, _FakeBundle(null));
      await tester.tap(find.text('挑選圖庫'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('greeting_gallery_sheet')), findsOneWidget);
      expect(find.textContaining('精選長輩圖庫 (9 款)'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting_gallery_header_lotus')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有清單：新範本併入圖庫、依分類出現 zh-TW 標題，點選可套用', (tester) async {
      await boot(tester, _FakeBundle(_fixtureManifest));
      await tester.tap(find.text('挑選圖庫'));
      await tester.pumpAndSettle();
      expect(find.textContaining('精選長輩圖庫 (13 款)'), findsOneWidget);
      // 內建的 9 款（節慶祝賀在最前面）與新分類同時存在
      expect(find.byKey(const ValueKey('greeting_gallery_header_festival')),
          findsOneWidget);
      expect(find.text('錦鯉（2）'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting_gallery_chip_koi')),
          findsOneWidget);

      // 篩選到錦鯉：只剩錦鯉兩張
      await tester.tap(find.byKey(const ValueKey('greeting_gallery_chip_koi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('greeting_gallery_header_festival')),
          findsNothing);
      expect(find.byKey(const ValueKey('greeting_gallery_tile_koi_t1')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('greeting_gallery_tile_koi_t1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('greeting_gallery_sheet')), findsNothing);
      // 目前範本列顯示新範本名稱
      expect(find.text('年年有餘'), findsWidgets);
      // 文字落點：koi_t1 為 bottomLeft（靠下）→ 小豬改放右上，拖動元素仍存在
      expect(find.byKey(const ValueKey('greeting_drag_text')), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting_pig_overlay')), findsOneWidget);
    });

    testWidgets('新範本的拖動位置以範本 id 為鍵儲存', (tester) async {
      await boot(tester, _FakeBundle(_fixtureManifest));
      await tester.tap(find.text('挑選圖庫'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('greeting_gallery_tile_lake_t1')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
      final text = find.byKey(const ValueKey('greeting_drag_text'));
      await tester.dragFrom(tester.getCenter(text), const Offset(30, 40));
      await tester.pump(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('greeting_layout_lake_t1'), isNotNull);
      expect(prefs.getString('greeting_layout_classic_lotus'), isNull);
    });

    for (final width in [360.0, 412.0]) {
      testWidgets('所有 text_position（$width 寬）：文字在對的位置、小豬預設落點不蓋到字', (tester) async {
        final manifest = jsonEncode([
          for (final pos in ['topLeft', 'topCenter', 'topRight', 'bottomLeft'])
            for (final cat in ['sunrise', 'mountain'])
              {
                'id': '${cat}_$pos',
                'file': 'x.jpg',
                'category': cat,
                'title': pos,
                'text_position': pos,
                'dark_bg': true
              },
        ]);
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(_FakeBundle(manifest)));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        final text = find.byKey(const ValueKey('greeting_drag_text'));
        final pig = find.byKey(const ValueKey('greeting_drag_pig'));
        for (final cat in ['sunrise', 'mountain']) {
          for (final pos in ['topLeft', 'topCenter', 'topRight', 'bottomLeft']) {
            await tester.tap(find.text('挑選圖庫'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('greeting_gallery_tile_${cat}_$pos')));
            await tester.pumpAndSettle();
            await tester.runAsync(
                () => Future.delayed(const Duration(milliseconds: 150)));
            for (var i = 0; i < 3; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            final sq = tester.getRect(find.byType(AspectRatio).first);
            final t = tester.getRect(text);
            final p = tester.getRect(pig);
            final reason = '$cat/$pos w=$width text=$t pig=$p square=$sq';
            if (pos == 'bottomLeft') {
              expect(t.center.dy, greaterThan(sq.center.dy), reason: reason);
            } else {
              expect(t.center.dy, lessThan(sq.center.dy), reason: reason);
            }
            if (pos == 'topCenter') {
              expect((t.center.dx - sq.center.dx).abs(), lessThan(sq.width * 0.15),
                  reason: reason);
            }
            expect(t.overlaps(p), isFalse, reason: reason);
          }
        }
      });
    }

    testWidgets('在範本 A 拖動文字後經圖庫切到 B：B 用自己的預設位置，A 的位置留在 A', (tester) async {
      await boot(tester, _FakeBundle(_fixtureManifest));
      final text = find.byKey(const ValueKey('greeting_drag_text'));
      Future<void> pick(String id) async {
        await tester.tap(find.text('挑選圖庫'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('greeting_gallery_tile_$id')));
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      await pick('koi_t2'); // topCenter
      final sq = tester.getRect(find.byType(AspectRatio).first);
      final defaultA = tester.getTopLeft(text);
      await tester.dragFrom(tester.getCenter(text), const Offset(0, 90));
      await tester.pump(const Duration(milliseconds: 100));
      final movedA = tester.getTopLeft(text);
      expect(movedA.dy, closeTo(defaultA.dy + 90, 1.5));

      await pick('lake_t1'); // topLeft、沒有存過位置
      expect(find.byKey(const ValueKey('greeting_layout_reset')), findsNothing);
      final b = tester.getTopLeft(text);
      expect(b.dx - sq.left, lessThan(sq.width * 0.2)); // 靠左，不是 A 的置中
      expect(b.dy - sq.top, lessThan(sq.height * 0.2)); // 靠上，沒有 A 的下移
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('greeting_layout_koi_t2'), isNotNull);
      expect(prefs.getString('greeting_layout_lake_t1'), isNull);

      await pick('koi_t2'); // 切回 A：位置仍在
      expect(tester.getTopLeft(text).dy, closeTo(movedA.dy, 1.5));
    });

    testWidgets('換句好話：產生符合規則且與上一句不同的新句', (tester) async {
      await boot(tester, _FakeBundle(null));
      final before = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toSet();
      await tester.ensureVisible(find.text('換句好話'));
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('換句好話'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      final after = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toSet();
      expect(after, isNot(equals(before)));
      expect(tester.takeException(), isNull);
    });
  });
}
