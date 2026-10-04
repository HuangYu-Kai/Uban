import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/glass_card.dart';
import 'package:flutter_application_1/widgets/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _host(ThemeData theme, Widget child,
    {double width = 390, double textScale = 1.0}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

const _navItems = [
  Icons.home_outlined,
  Icons.call_outlined,
  Icons.pets_outlined,
  Icons.chat_bubble_outline,
  Icons.person_outline,
];

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('UbanGlassNavBar', () {
    testWidgets('點第 i 項呼叫 onTap(i)，5 個傳入 key 都找得到', (tester) async {
      final keys = List.generate(5, (_) => GlobalKey());
      final taps = <int>[];
      int current = 0;
      await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
        return MaterialApp(
          theme: ThemeData(extensions: const [UbanColors.light]),
          home: Scaffold(
            body: Stack(children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: UbanGlassNavBar(
                  currentIndex: current,
                  onTap: (i) => setState(() {
                    taps.add(i);
                    current = i;
                  }),
                  items: [
                    for (var i = 0; i < 5; i++)
                      UbanNavItem(
                        icon: _navItems[i],
                        selectedIcon: _navItems[i],
                        label: '項目$i',
                        key: keys[i],
                      ),
                  ],
                ),
              ),
            ]),
          ),
        );
      }));
      for (final k in keys) {
        expect(find.byKey(k), findsOneWidget);
      }
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(keys[i]));
        await tester.pumpAndSettle();
      }
      expect(taps, [0, 1, 2, 3, 4]);
      expect(tester.takeException(), isNull);
    });
  });

  for (final entry in {
    'light': buildAppTheme,
    'dark': buildAppDarkTheme,
  }.entries) {
    testWidgets('全部元件在 ${entry.key} 主題下可 pump 無例外', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
        theme = entry.value(ctx);
        return const SizedBox();
      })));

      final controller = TextEditingController();
      await tester.pumpWidget(_host(
        theme,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final v in UbanButtonVariant.values)
                UbanButton(label: v.name, onPressed: () {}, variant: v),
              UbanButton(
                  label: 'xl',
                  icon: Icons.call,
                  size: UbanButtonSize.xl,
                  onPressed: () {}),
              UbanButton(label: 'loading', onPressed: () {}, loading: true),
              const UbanButton(label: 'disabled', onPressed: null),
              UbanCard(onTap: () {}, child: const Text('card')),
              UbanActionTile(
                icon: Icons.favorite,
                title: '標題',
                subtitle: '副標題',
                tone: UbanTone.warm,
                trailing: UbanSwitch(value: true, onChanged: (_) {}),
              ),
              Builder(
                  builder: (ctx) => UbanActionTile(
                        icon: Icons.info,
                        title: '資訊',
                        tone: UbanTone.info,
                        trailing: UbanActionTile.chevron(ctx),
                        onTap: () {},
                      )),
              const UbanActionTile(
                  icon: Icons.warning, title: '危險', tone: UbanTone.danger),
              UbanSegmented(
                  labels: const ['甲', '乙', '丙'], index: 1, onChanged: (_) {}),
              UbanSegmented(
                  small: true,
                  labels: const ['甲', '乙'],
                  index: 0,
                  onChanged: (_) {}),
              UbanTextField(
                  label: '姓名', hintText: '請輸入', controller: controller),
              UbanStepper(value: 3, onChanged: (_) {}),
              const Center(child: UbanProgressRing(done: 2, total: 5)),
              UbanTopBar(
                  title: '很長很長很長很長很長很長很長很長的標題',
                  trailing: const Icon(Icons.add)),
              const UbanDialog(child: Text('dialog')),
              const GlassCard(child: Text('glass')),
              const GlassCard(useUbanColors: true, child: Text('glass2')),
              SizedBox(
                height: 130,
                child: Stack(children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: UbanGlassNavBar(
                      currentIndex: 2,
                      onTap: (_) {},
                      items: [
                        for (var i = 0; i < 5; i++)
                          UbanNavItem(
                              icon: _navItems[i],
                              selectedIcon: _navItems[i],
                              label: '項目$i'),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ));
      // loading 的 CircularProgressIndicator 永不停止，故不用 pumpAndSettle。
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // 互動：按下按鈕觸發暈開與縮放、切換 segmented / switch。
      await tester.tap(find.text('filled'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('乙').first);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('UbanColors：lerp / copyWith / of 退回 light', (tester) async {
    final mid = UbanColors.light.lerp(UbanColors.dark, .5);
    expect(mid.brand,
        Color.lerp(UbanColors.light.brand, UbanColors.dark.brand, .5));
    expect(UbanColors.light.copyWith(brand: Colors.red).brand, Colors.red);
    late UbanColors got;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(),
        home: Builder(builder: (c) {
          got = UbanColors.of(c);
          return const SizedBox();
        })));
    expect(got.brand, UbanColors.light.brand);
  });

  testWidgets('UbanButton 在 textScaler 1.3、寬 320 下無 overflow', (tester) async {
    await tester.pumpWidget(_host(
      ThemeData(extensions: const [UbanColors.light]),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          UbanButton(
              label: '這是一個相當長的按鈕文字用來測試溢位情形',
              icon: Icons.call,
              size: UbanButtonSize.xl,
              onPressed: () {}),
          UbanButton(label: '確認送出', onPressed: () {}),
          UbanButton(
              label: '取消', variant: UbanButtonVariant.ghost, onPressed: () {}),
          UbanActionTile(
              icon: Icons.person,
              title: '一個非常非常長的長輩姓名與裝置名稱',
              subtitle: '一段很長的副標題說明文字，會在窄螢幕上換行或被省略',
              trailing: UbanSwitch(value: false, onChanged: (_) {})),
          const UbanTopBar(title: '很長很長很長很長很長很長的標題文字'),
        ]),
      ),
      width: 320,
      textScale: 1.3,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
