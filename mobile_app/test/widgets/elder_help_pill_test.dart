import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/elder_floating_chrome.dart';

/// 測試用外殼：expanded 由外層決定（對應首頁的「捲到底」），點擊一律觸發 onTap。
class _Host extends StatelessWidget {
  final VoidCallback? onHelp;
  final bool forceExpanded;
  const _Host({this.onHelp, this.forceExpanded = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: ElderHelpPill(
              expanded: forceExpanded,
              onTap: onHelp ?? () {},
            ),
          ),
        ]),
      ),
    );
  }
}

void main() {
  testWidgets('預設縮進右緣：標籤在螢幕外、突起可見', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final label = tester.getTopLeft(find.text('怎麼用？'));
    expect(label.dx, greaterThan(w - 1)); // 標籤整個在螢幕右外
    final icon = tester.getRect(find.byIcon(Icons.help_outline_rounded));
    expect(icon.right, lessThanOrEqualTo(w));
    expect(icon.left, greaterThan(w - 60));
  });

  testWidgets('縮進突起為展開時的 1.5 倍（圖示 30、高 72、露出 45）', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    final icon = tester.getRect(find.byIcon(Icons.help_outline_rounded));
    expect(icon.width, closeTo(30, 0.5));
    final bump = tester.getRect(find.descendant(
        of: find.byType(ElderHelpPill), matching: find.byType(Container)).first);
    expect(bump.height, closeTo(72, 0.5));
    expect(412 - bump.left, closeTo(ElderHelpPill.bumpVisible, 0.5));

    // 展開後圖示回到原本 20
    await tester.pumpWidget(const _Host(forceExpanded: true));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byIcon(Icons.help_outline_rounded)).width,
        closeTo(20, 0.5));
  });

  testWidgets('縮進時點突起直接觸發 onTap（不用先展開）', (tester) async {
    var helps = 0;
    await tester.pumpWidget(_Host(onHelp: () => helps++));
    await tester.pumpAndSettle();
    final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(helps, 1);
    expect(tester.getTopLeft(find.text('怎麼用？')).dx, greaterThan(w - 1));
  });

  testWidgets('展開時為原本大小：寬 < 220、左緣完整在螢幕內（412 寬）', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _Host(forceExpanded: true));
    await tester.pumpAndSettle();
    final pill = tester.getRect(find.descendant(
        of: find.byType(ElderHelpPill), matching: find.byType(Container)).first);
    expect(pill.width, lessThan(220));
    expect(pill.left, greaterThanOrEqualTo(0));
    expect(pill.right, closeTo(412 - 16, 1));
    expect(tester.getRect(find.byIcon(Icons.help_outline_rounded)).left,
        greaterThanOrEqualTo(0));
  });

  testWidgets('forceExpanded（捲到底）直接展開', (tester) async {
    await tester.pumpWidget(const _Host(forceExpanded: true));
    await tester.pumpAndSettle();
    final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getRect(find.text('怎麼用？')).right, lessThanOrEqualTo(w));
  });

  group('底部偵測', () {
    ScrollMetrics m({
      double pixels = 0,
      double max = 1000,
      double viewport = 800,
      AxisDirection dir = AxisDirection.down,
    }) =>
        FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: max,
          pixels: pixels,
          viewportDimension: viewport,
          axisDirection: dir,
          devicePixelRatio: 1,
        );

    test('elderScrolledToBottom：底部、差 20px、不可捲', () {
      expect(elderScrolledToBottom(m(pixels: 1000)), isTrue);
      expect(elderScrolledToBottom(m(pixels: 995)), isTrue);
      expect(elderScrolledToBottom(m(pixels: 980)), isFalse);
      expect(elderScrolledToBottom(m(max: 0)), isTrue);
    });

    test('Tracker：逐分頁記錄、忽略水平、忽略較小的內層捲動區', () {
      final t = ElderBottomTracker();
      expect(t.atBottom(0), isFalse);
      expect(t.update(0, m(pixels: 1000)), isTrue);
      expect(t.atBottom(0), isTrue);
      expect(t.atBottom(2), isFalse);
      // 水平捲動忽略
      expect(t.update(0, m(pixels: 0, dir: AxisDirection.right)), isFalse);
      expect(t.atBottom(0), isTrue);
      // 內層小清單（viewport 較小）不得覆蓋主捲動區
      expect(t.update(0, m(pixels: 0, max: 500, viewport: 300), 'inner'), isTrue);
      expect(t.atBottom(0), isTrue);
      // 主捲動區離開底部
      expect(t.update(0, m(pixels: 200)), isTrue);
      expect(t.atBottom(0), isFalse);
      // 主捲動區 viewport 縮小後仍以它自己的最新狀態為準
      t.update(0, m(pixels: 1000, viewport: 500));
      expect(t.atBottom(0), isTrue);
    });
  });

  testWidgets('小豬分頁結構（SafeArea > RefreshIndicator > 捲動區 + 內層小清單）捲到底會偵測到',
      (tester) async {
    final tracker = ElderBottomTracker();
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationListener<Notification>(
          onNotification: (n) {
            if (n is ScrollNotification) {
              tracker.update(2, n.metrics, n.context ?? 0);
            } else if (n is ScrollMetricsNotification) {
              tracker.update(2, n.metrics, n.context);
            }
            return false;
          },
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {},
              child: SingleChildScrollView(
                controller: ctrl,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 200),
                child: Column(children: [
                  const SizedBox(height: 900),
                  SizedBox(
                    height: 120,
                    child: ListView(children: const [
                      SizedBox(height: 400),
                    ]),
                  ),
                  const SizedBox(height: 300),
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tracker.atBottom(2), isFalse);
    ctrl.jumpTo(ctrl.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(tracker.atBottom(2), isTrue);
    ctrl.jumpTo(0);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(tracker.atBottom(2), isFalse);
  });
}
