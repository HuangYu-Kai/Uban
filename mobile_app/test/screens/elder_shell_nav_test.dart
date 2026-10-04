// 長輩外殼導覽列回歸測試（v3 分頁重排）。
//
// ElderHomeScreen 依賴 Signaling／CallKit／Firebase 等 plugin，無法在 widget
// test 中 pump，所以改測抽出來的純函式 `buildElderNavItems()`（外殼的
// `_buildFloatingNavBar` 就是用它餵 UbanGlassNavBar），確認：
//  1. 五個 label 依序為 首頁／電話／小豬／聊天／我的
//  2. 傳入的 keys（外殼的 _navItemKeys，新手指引 spotlight 用）逐項掛到對應項目
//  3. 點第 i 項會回呼 onTap(i)
//  4. 360x640、textScaler 1.3 不溢位
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_layout.dart';
import 'package:flutter_application_1/widgets/ui/ui.dart';

void main() {
  const labels = ['首頁', '電話', '小豬', '聊天', '我的'];

  test('buildElderNavItems：五項順序與 key 對應', () {
    final keys = List<GlobalKey>.generate(5, (_) => GlobalKey());
    final items = buildElderNavItems(keys);
    expect(items.map((e) => e.label).toList(), labels);
    for (var i = 0; i < 5; i++) {
      expect(items[i].key, same(keys[i]));
      expect(items[i].icon, isNot(items[i].selectedIcon));
    }
    // 沒給 keys 也要能建
    expect(buildElderNavItems().map((e) => e.key), everyElement(isNull));
  });

  testWidgets('UbanGlassNavBar 在長輩外殼：label 依序、點擊回呼、不溢位',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final keys = List<GlobalKey>.generate(5, (_) => GlobalKey());
    final taps = <int>[];
    var current = 0;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [UbanColors.light]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: UbanGlassNavBar(
                  items: buildElderNavItems(keys),
                  currentIndex: current,
                  onTap: (i) {
                    taps.add(i);
                    setState(() => current = i);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    // label 由左到右依序
    final xs = <double>[];
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
      xs.add(tester.getCenter(find.text(l)).dx);
    }
    final sorted = [...xs]..sort();
    expect(xs, sorted);

    for (var i = 0; i < 5; i++) {
      expect(find.byKey(keys[i]), findsOneWidget);
    }

    await tester.tap(find.byKey(keys[2]));
    await tester.pump();
    await tester.tap(find.byKey(keys[4]));
    await tester.pump(const Duration(milliseconds: 600));
    expect(taps, [2, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elderNavClearance = 導覽列高 + 安全區 + 16', (tester) async {
    late double v;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 20)),
        child: Builder(builder: (context) {
          v = elderNavClearance(context);
          return const SizedBox();
        }),
      ),
    ));
    expect(v, UbanGlassNavBar.totalHeight + 20 + 16);
  });
}
