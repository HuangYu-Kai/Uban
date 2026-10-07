import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_layout.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_gift_banner.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/widgets/garden_feeding_sheet.dart';
import 'package:flutter_application_1/services/api/elder_pet_gift_api.dart';
import 'package:flutter_application_1/widgets/ui/uban_glass_nav_bar.dart';

PetGift g(int id, String food, String name, [String who = '璿OwO']) => PetGift(
    giftId: id, familyName: who, foodId: food, foodName: name);

Future<void> pumpAt360(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(360, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
          size: Size(360, 640), textScaler: TextScaler.linear(1.3)),
      child: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  ));
}

void main() {
  test('禮物訊息格式與解析', () {
    final p = PetGift.tryParse({
      'giftId': 3, 'familyName': '璿OwO', 'foodId': 'apple', 'foodName': '蜜糖紅蘋果'
    })!;
    expect(p.careMessage, '璿OwO 送了一份「蜜糖紅蘋果」給小豬，快去餵牠吧！');
    expect(PetGift.tryParse({'foodId': 'apple'}), isNull);
    expect(PetGift.tryParse('x'), isNull);
  });

  test('橫幅文字最多 3 份並加「等 N 份」', () {
    final three = [g(1, 'apple', '蜜糖紅蘋果'), g(2, 'corn', '玉米')];
    expect(petGiftBannerText(three, emojiOf: (_) => '🍎'),
        '家人送的點心：🍎 蜜糖紅蘋果（璿OwO）、🍎 玉米（璿OwO）');
    final five = [for (var i = 0; i < 5; i++) g(i, 'apple', '蜜糖紅蘋果')];
    expect(petGiftBannerText(five), endsWith('等 5 份'));
    expect('、'.allMatches(petGiftBannerText(five)).length, 2);
  });

  testWidgets('橫幅 360x640 textScale1.3 不溢出；空清單不佔位', (t) async {
    final n = ValueNotifier<List<PetGift>>([
      for (var i = 0; i < 5; i++)
        g(i, 'apple', '蜜糖紅蘋果超級長名字測試', '一個很長很長的家人暱稱OwO')
    ]);
    PetGift? fed;
    await pumpAt360(t, PetGiftBanner(listenable: n, onFeed: (x) => fed = x));
    expect(find.byKey(const ValueKey('pet_gift_banner')), findsOneWidget);
    expect(find.textContaining('等 5 份'), findsOneWidget);
    expect(find.text('餵牠吃'), findsNWidgets(3));
    await t.tap(find.byKey(const ValueKey('pet_gift_feed_1')));
    expect(fed?.giftId, 1);
    expect(t.takeException(), isNull);
    n.value = const [];
    await t.pump();
    expect(find.byKey(const ValueKey('pet_gift_banner')), findsNothing);
  });

  testWidgets('導覽列「小豬」小紅點開關', (t) async {
    Future<void> pump(bool on) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            bottomNavigationBar: UbanGlassNavBar(
              items: buildElderNavItems(const [], false, on),
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ));
    await pump(false);
    expect(find.byKey(const ValueKey('nav_badge_dot')), findsNothing);
    await pump(true);
    expect(find.byKey(const ValueKey('nav_badge_dot')), findsOneWidget);
    expect(find.bySemanticsLabel('小豬，有家人送的點心'), findsOneWidget);
  });

  testWidgets('食物挑選抽屜：有未餵禮物的食物顯示「家人送的」', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GardenFeedingSheet(
          isLandscape: false,
          foodInventory: const {'apple': 3},
          currentSteps: 99999,
          medicationCheckinsToday: 9,
          giftFoodIds: const {'apple'},
          onFeedFood: (_) {},
          onClose: () {},
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('家人送的'), findsOneWidget);
  });
}
