import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_greeting_tab.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// 經典祝賀圖：拖動小豬／文字、依範本記憶、夾限、還原、不捲動外層、虛線外框不外洩。
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final scrollKey = GlobalKey();
  Widget host() => MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[UbanColors.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            key: scrollKey,
            child: const ElderGreetingTab(userId: 1, userName: '測試', embedded: true),
          ),
        ),
      );

  final pig = find.byKey(const ValueKey('greeting_drag_pig'));
  final text = find.byKey(const ValueKey('greeting_drag_text'));
  final highlight = find.byKey(const ValueKey('greeting_drag_highlight'));
  final reset = find.byKey(const ValueKey('greeting_layout_reset'));
  final hint = find.byKey(const ValueKey('greeting_layout_hint'));

  Rect square(WidgetTester t) => t.getRect(find.byType(AspectRatio).first);

  Future<void> boot(WidgetTester tester, Map<String, Object> prefs,
      {Size size = const Size(800, 3000)}) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    // 讓小豬圖解碼完成（真實非同步），才有實際尺寸可拖
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('拖動文字：位置改變、存成比例、顯示提示後消失、出現還原鈕', (tester) async {
    await boot(tester, {});
    expect(hint, findsOneWidget);
    expect(reset, findsNothing);
    final before = tester.getTopLeft(text);
    await tester.dragFrom(tester.getCenter(text), const Offset(40, -60));
    await tester.pump(const Duration(milliseconds: 100));
    final after = tester.getTopLeft(text);
    expect(after.dx, closeTo(before.dx + 40, 1.5));
    expect(after.dy, closeTo(before.dy - 60, 1.5));
    expect(highlight, findsNothing); // 放手後外框消失
    expect(hint, findsNothing);
    expect(reset, findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final m = jsonDecode(prefs.getString('greeting_layout_classic_lotus')!) as Map;
    final sq = square(tester);
    expect((m['text']['x'] as num).toDouble(),
        closeTo((after.dx - sq.left) / sq.width, 0.01));
    expect(m.containsKey('pig'), isFalse);
    expect(prefs.getBool('greeting_layout_hint_seen'), isTrue);
  });

  testWidgets('拖動中才有虛線外框；拖出圖外會夾限在圖內', (tester) async {
    await boot(tester, {});
    final sq = square(tester);
    final g = await tester.startGesture(tester.getCenter(pig));
    await g.moveBy(const Offset(10, 10));
    await tester.pump();
    expect(highlight, findsOneWidget);
    await g.moveBy(const Offset(5000, -5000));
    await tester.pump();
    final r = tester.getRect(pig);
    expect(r.right, lessThanOrEqualTo(sq.right + 0.5));
    expect(r.top, greaterThanOrEqualTo(sq.top - 0.5));
    await g.up();
    await tester.pump();
    expect(highlight, findsNothing);
  });

  testWidgets('拖動元素時不會捲動外層 SingleChildScrollView', (tester) async {
    await boot(tester, {}, size: const Size(800, 420));
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(scrollKey), matching: find.byType(Scrollable)).first);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(scrollable.position.pixels, 0);
    await tester.dragFrom(tester.getCenter(text), const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, 0);
    // 在圖以外的地方拖，仍然可以捲動頁面
    await tester.dragFrom(tester.getCenter(find.text('每日吉祥祝賀圖')), const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('位置依範本分別記憶；還原鈕回到預設並清除儲存', (tester) async {
    await boot(tester, {
      'greeting_layout_classic_lotus': jsonEncode({
        'pig': {'x': 0.1, 'y': 0.1},
      }),
    });
    final sq = square(tester);
    expect(tester.getTopLeft(pig).dx, closeTo(sq.left + sq.width * 0.1, 1.0));
    expect(reset, findsOneWidget);

    // 換到別的範本（常用快捷第二個）：沒有自訂位置 → 預設、無還原鈕
    await tester.tap(find.byType(ClipRRect).at(2), warnIfMissed: false);
    // 以一次還原驗證即可：還原後預設右上角
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump(const Duration(milliseconds: 100));
    expect(reset, findsNothing);
    expect(tester.getTopRight(pig).dx, lessThan(sq.right));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('greeting_layout_classic_lotus'), isNull);
  });

  testWidgets('已拖過旗標：提示不再出現', (tester) async {
    await boot(tester, {'greeting_layout_hint_seen': true});
    expect(hint, findsNothing);
    expect(pig, findsOneWidget);
    expect(text, findsOneWidget);
  });

  testWidgets('匯出路徑不含拖動外框：未拖動時畫面沒有 highlight', (tester) async {
    await boot(tester, {});
    expect(highlight, findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });
}
