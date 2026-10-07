// ★ 2026-10-07 小豬共養（家屬端）：小豬卡片各狀態、送點心面板、通知去重與偏好鍵。
// 溢位以 360×640、textScaler 1.3 驗證（CLAUDE.md 規則 14），亮／暗各一次。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/sheets/send_pet_gift_sheet.dart';
import 'package:flutter_application_1/screens/family/widgets/family_pet_card.dart';
import 'package:flutter_application_1/services/api/pet_gift_api.dart';
import 'package:flutter_application_1/services/checkin_notification.dart';
import 'package:flutter_application_1/theme/family_theme.dart';
import 'package:flutter_application_1/widgets/ui/uban_sheet.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Elder _elder() => Elder(id: 1, elderId: 'e1', name: '王大明爸爸這個名字故意取得很長很長很長');

PetGiftStatus _status({
  bool can = true,
  int today = 1,
  List<PetGiftRecent>? recent,
}) =>
    PetGiftStatus(
      weightGrams: 12500,
      breed: 'pink',
      canGiftToday: can,
      elderGiftsToday: today,
      recent: recent ??
          const [
            PetGiftRecent(
                giftId: 2,
                familyName: '璿OwO璿OwO璿OwO璿OwO',
                foodId: 'apple',
                foodName: '蘋果',
                fedAt: '2026-10-07T01:00:00Z'),
            PetGiftRecent(
                giftId: 1, familyName: '小明', foodId: 'carrot', foodName: '紅蘿蔔'),
          ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'caregiver_id': 7}));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Widget child, {bool dark = false}) => MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
        builder: (ctx, w) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: w!,
        ),
        home: child,
      );

  Widget cardHarness(FamilyPetCard card, {bool dark = false}) => harness(
        Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: card),
        ),
        dark: dark,
      );

  group('FamilyPetCard', () {
    for (final dark in [false, true]) {
      testWidgets('可送點心＋兩筆紀錄（已餵／等餵食），無溢位 dark=$dark', (tester) async {
        await phone(tester);
        await tester.pumpWidget(cardHarness(
          FamilyPetCard(
            currentElder: _elder(),
            loader: (_, __) async => PetGiftStatusResult(status: _status()),
          ),
          dark: dark,
        ));
        await tester.pumpAndSettle();
        expect(find.text('小豬'), findsOneWidget);
        expect(find.textContaining('今天家人送了 1/3 份點心'), findsOneWidget);
        expect(find.textContaining('12.5 kg'), findsOneWidget);
        expect(find.textContaining('✓ 已餵'), findsOneWidget);
        expect(find.textContaining('等'), findsWidgets);
        expect(find.text('送點心給小豬'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('今天已送過：按鈕停用並顯示原因', (tester) async {
      await phone(tester);
      var opened = 0;
      await tester.pumpWidget(cardHarness(FamilyPetCard(
        currentElder: _elder(),
        loader: (_, __) async => PetGiftStatusResult(status: _status(can: false)),
        sheetOpener: (_, __, ___, ____) async {
          opened++;
          return false;
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('今天已經送過了'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pet_card_gift')), warnIfMissed: false);
      await tester.pump();
      expect(opened, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('尚未綁定（404）與讀取失敗：顯示友善文字、無按鈕', (tester) async {
      await phone(tester);
      await tester.pumpWidget(cardHarness(FamilyPetCard(
        currentElder: _elder(),
        loader: (_, __) async => const PetGiftStatusResult(notBound: true),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('還沒有開始養小豬'), findsOneWidget);
      expect(find.byKey(const ValueKey('pet_card_gift')), findsNothing);

      await tester.pumpWidget(cardHarness(FamilyPetCard(
        key: const ValueKey('second'),
        currentElder: _elder(),
        loader: (_, __) async => const PetGiftStatusResult(),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('暫時讀不到'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('送出成功：SnackBar 並重讀', (tester) async {
      await phone(tester);
      var loads = 0;
      await tester.pumpWidget(cardHarness(FamilyPetCard(
        currentElder: Elder(id: 1, elderId: 'e1', name: '阿公'),
        loader: (_, __) async {
          loads++;
          return PetGiftStatusResult(status: _status());
        },
        sheetOpener: (_, __, ___, ____) async => true,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pet_card_gift')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已送出！等阿公餵小豬時會通知您'), findsOneWidget);
      expect(loads, 2);
    });

    test('體重格式與圖片路徑', () {
      expect(formatPetWeight(800), '800 g');
      expect(formatPetWeight(12500), '12.5 kg');
      expect(petCardImageAsset(0, 'pink'), 'assets/images/pet_breeds/pink_front_1.png');
      expect(petCardImageAsset(0, 'black'), 'assets/images/pet_breeds/black_front_1.png');
      expect(petCardImageAsset(0, 'weird'), 'assets/images/pet_breeds/pink_front_1.png');
    });
  });

  group('SendPetGiftSheet', () {
    Widget sheet(PetGiftSender sender, {bool dark = false}) => harness(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: UbanSheet(
                child: SendPetGiftSheet(
                  elderName: '王大明爸爸這個名字故意取得很長很長很長',
                  familyId: 7,
                  elderId: 'e1',
                  sender: sender,
                ),
              ),
            ),
          ),
          dark: dark,
        );

    for (final dark in [false, true]) {
      testWidgets('三種點心、說明文字、未選時送出停用，無溢位 dark=$dark', (tester) async {
        await phone(tester);
        await tester.pumpWidget(sheet((_) async => const PetGiftSendResult(true, ''), dark: dark));
        await tester.pumpAndSettle();
        expect(find.text('紅蘿蔔'), findsOneWidget);
        expect(find.text('蘋果'), findsOneWidget);
        expect(find.text('高麗菜'), findsOneWidget);
        expect(find.textContaining('小豬食物盒'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('選點心後送出：帶正確 foodId', (tester) async {
      await phone(tester);
      String? sent;
      await tester.pumpWidget(sheet((f) async {
        sent = f;
        return const PetGiftSendResult(true, '已送出');
      }));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pet_gift_food_apple')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pet_gift_send')));
      await tester.pumpAndSettle();
      expect(sent, 'apple');
    });

    testWidgets('後端 400 友善訊息顯示在面板內，不關閉', (tester) async {
      await phone(tester);
      await tester.pumpWidget(sheet((_) async =>
          const PetGiftSendResult(false, '今天已經送過點心了，明天再來吧')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pet_gift_food_carrot')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pet_gift_send')));
      await tester.pumpAndSettle();
      expect(find.text('今天已經送過點心了，明天再來吧'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PetGift 模型與通知', () {
    test('PetGiftStatus.fromJson', () {
      final s = PetGiftStatus.fromJson({
        'pet': {'weight_grams': 3000, 'breed': 'black'},
        'can_gift_today': false,
        'my_gift_today': 'apple',
        'elder_gifts_today': 2,
        'limits': {'per_family_per_day': 1, 'per_elder_per_day': 3},
        'recent': [
          {'gift_id': 5, 'familyName': 'A', 'food_id': 'apple', 'food_name': '蘋果', 'fed_at': null},
          {'gift_id': 4, 'familyName': 'B', 'food_id': 'carrot', 'food_name': '紅蘿蔔', 'fed_at': '2026-10-07T00:00:00Z'},
        ],
      });
      expect(s.canGiftToday, false);
      expect(s.myGiftToday, 'apple');
      expect(s.breed, 'black');
      expect(s.recent[0].fed, false);
      expect(s.recent[1].fed, true);
    });

    test('偏好鍵與去重（依 giftId）', () async {
      expect(CheckinNotification.petGiftPrefKey, 'pet_gift_notify_enabled');
      expect(await CheckinNotification.isPetGiftEnabled(), true);
      await CheckinNotification.setPetGiftEnabled(false);
      expect(await CheckinNotification.isPetGiftEnabled(), false);
      CheckinNotification.resetDedupe();
      expect(CheckinNotification.seenRecently('pet-gift-fed|9'), false);
      expect(CheckinNotification.seenRecently('pet-gift-fed|9'), true);
      expect(CheckinNotification.seenRecently('pet-gift-fed|10'), false);
    });
  });
}
