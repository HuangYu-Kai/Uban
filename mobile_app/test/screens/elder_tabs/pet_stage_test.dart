// 長輩端「小豬」分頁的寶可夢 GO 夥伴舞台（PetBuddyStage）測試。
//
// 舞台刻意不依賴 geolocator／pedometer／後端，可以單獨在 360×640 pump。
// 涵蓋：舞台可在小螢幕＋大字下掛載不溢位、耳標錨點 JSON 20 筆齊全、
// 朝右翻轉時耳標畫在頭後、胡蘿蔔 0 根時為停用外觀、減少動態時沒有持續動畫、
// 耳標鐘擺週期，以及一般模式下會自己走路。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_buddy_stage.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_carrot_button.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_ear_anchors.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_pig_sprite.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_scene.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_stat_card.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_tag_pendulum.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/models/pet_growth_state.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/widgets/pet_evolution_dialog.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/widgets/pet_leaderboard_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

PetEarAnchors _loadAnchors() => PetEarAnchors.fromJsonString(
    File('assets/images/pet_breeds/ear_anchors.json').readAsStringSync());

Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

PetBuddyStage _stage({
  required PetEarAnchors anchors,
  int carrots = 3,
  bool reduce = true,
  PetWeather weather = PetWeather.shower,
  bool Function()? onFeed,
  VoidCallback? onDone,
  VoidCallback? onEmpty,
  Future<int> Function()? onRefresh,
}) =>
    PetBuddyStage(
      stage: 3,
      breed: PetBreed.pink,
      time: PetTimeOfDay.day,
      weather: weather,
      carrotCount: carrots,
      anchors: anchors,
      reduceMotionOverride: reduce,
      onFeedRequest: onFeed ?? () => true,
      onFeedDone: onDone,
      onEmptyCarrot: onEmpty,
      onRefreshCarrot: onRefresh,
      cornerAction: const SizedBox(width: 44, height: 44),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('耳標錨點 JSON', () {
    test('可解析且 2 品種 × 2 視角 × 5 階共 20 筆齊全', () {
      final a = _loadAnchors();
      expect(a.entries.length, 20);
      for (final b in PetBreed.values) {
        for (final v in PetView.values) {
          for (var stage = 1; stage <= 5; stage++) {
            final e = a.lookup(b, v, stage);
            expect(e, isNotNull, reason: '${b.id}_${v.id}_$stage');
            expect(e!.x, inInclusiveRange(0, 1));
            expect(e.y, inInclusiveRange(0, 1));
            expect(e.scale, greaterThan(0));
            // 側面（會朝右走、整個身體翻轉）要求翻轉時畫在頭後；正面不會翻轉。
            expect(e.behindHeadWhenFlipped, v == PetView.side);
          }
        }
      }
    });

    test('數值與設計稿 ui.js 的 EAR 表一致（抽查）', () {
      final a = _loadAnchors();
      expect(a.lookup(PetBreed.pink, PetView.front, 1)!.x, .82);
      expect(a.lookup(PetBreed.pink, PetView.front, 1)!.y, .17);
      expect(a.lookup(PetBreed.black, PetView.side, 5)!.x, .15);
      expect(a.lookup(PetBreed.black, PetView.side, 5)!.y, .47);
      expect(a.lookup(PetBreed.pink, PetView.side, 3)!.scale, .2);
      expect(a.lookup(PetBreed.pink, PetView.front, 3)!.scale, .15);
    });

    test('每張小豬圖與耳標圖資產都存在', () {
      for (final b in PetBreed.values) {
        for (final v in PetView.values) {
          for (var stage = 1; stage <= 5; stage++) {
            expect(File(petSpriteAsset(b, v, stage)).existsSync(), isTrue);
            expect(kPetSpriteSize[PetEarAnchors.keyOf(b, v, stage)], isNotNull);
          }
        }
      }
      for (var stage = 1; stage <= 5; stage++) {
        expect(File(petEarTagAsset(stage)).existsSync(), isTrue);
      }
    });
  });

  group('耳標鐘擺', () {
    test('週期約 0.9 秒、會逐漸停下來', () {
      final p = PetTagPendulum()..kick(-140);
      const dt = 1 / 120;
      var t = 0.0;
      final crossings = <double>[];
      var prev = p.angle;
      while (t < 20 && !(t > 1 && p.settled)) {
        p.step(dt);
        t += dt;
        if (prev < 0 && p.angle >= 0) crossings.add(t); // 由負到正的過零點
        prev = p.angle;
      }
      expect(crossings.length, greaterThanOrEqualTo(3));
      final period = crossings[2] - crossings[1];
      expect(period, inInclusiveRange(.85, .95));
      expect(p.settled, isTrue);
    });
  });

  group('PetPigSprite 耳標層次', () {
    List<Key?> zOrder(WidgetTester tester) => tester
        .widgetList(find.byWidgetPredicate((w) =>
            w.key == PetPigSprite.earTagKey || w.key == PetPigSprite.pigImageKey))
        .map((w) => w.key)
        .toList();

    Widget sprite(PetEarAnchors a, {required bool flip, PetView view = PetView.side}) =>
        Center(
          child: PetPigSprite(
            breed: PetBreed.pink,
            view: view,
            stage: 3,
            flip: flip,
            tagAngle: 0,
            anchors: a,
            width: 160,
            height: 120,
          ),
        );

    testWidgets('朝右走（翻轉）：耳標在頭後（豬圖之下）', (tester) async {
      final a = _loadAnchors();
      await tester.pumpWidget(_host(sprite(a, flip: true)));
      expect(tester.takeException(), isNull);
      final sp = tester.widget<PetPigSprite>(find.byType(PetPigSprite));
      expect(sp.tagBehindHead, isTrue);
      expect(zOrder(tester), [PetPigSprite.earTagKey, PetPigSprite.pigImageKey]);
      // 翻轉時耳標調暗（ColorFiltered），且位置往後上挪。
      expect(find.descendant(
          of: find.byKey(PetPigSprite.earTagKey),
          matching: find.byType(ColorFiltered)), findsOneWidget);
    });

    testWidgets('朝左（不翻轉）：耳標在豬圖上面、不調暗', (tester) async {
      final a = _loadAnchors();
      await tester.pumpWidget(_host(sprite(a, flip: false)));
      final sp = tester.widget<PetPigSprite>(find.byType(PetPigSprite));
      expect(sp.tagBehindHead, isFalse);
      expect(zOrder(tester), [PetPigSprite.pigImageKey, PetPigSprite.earTagKey]);
      expect(find.descendant(
          of: find.byKey(PetPigSprite.earTagKey),
          matching: find.byType(ColorFiltered)), findsNothing);
    });

    testWidgets('正面：耳標永遠在豬圖上面', (tester) async {
      final a = _loadAnchors();
      await tester.pumpWidget(_host(sprite(a, flip: false, view: PetView.front)));
      expect(zOrder(tester), [PetPigSprite.pigImageKey, PetPigSprite.earTagKey]);
    });

    testWidgets('翻轉時耳標位置往遠側耳朵挪（x 往後、y 往上）', (tester) async {
      final a = _loadAnchors();
      Offset tagTopLeft() => tester.getTopLeft(find.byKey(PetPigSprite.earTagKey));
      await tester.pumpWidget(_host(sprite(a, flip: false)));
      final plain = tagTopLeft();
      await tester.pumpWidget(_host(sprite(a, flip: true)));
      final flipped = tagTopLeft();
      expect(flipped.dx - plain.dx, closeTo(a.flipDx * 160, .01));
      expect(flipped.dy - plain.dy, closeTo(a.flipDy * 160, .01));
    });
  });

  group('PetBuddyStage', () {
    testWidgets('360×640、字級 1.3 可掛載且不溢位（含雨天、角落鈕）', (tester) async {
      phone(tester);
      final a = _loadAnchors();
      await tester.pumpWidget(_host(_stage(anchors: a), textScale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PetBuddyStage), findsOneWidget);
      expect(find.byType(PetPigSprite), findsOneWidget);
      expect(find.text('白天・局部陣雨'), findsOneWidget);
      // 舞台高度依寬度等比：基準寬 390 → 高 300。
      final size = tester.getSize(find.byType(PetBuddyStage));
      expect(size.width, 328); // 360 - 2×16
      expect(size.height, closeTo(300 * 328 / 390, .01));
    });

    testWidgets('三種天氣、四種時段都能畫出來', (tester) async {
      phone(tester);
      final a = _loadAnchors();
      for (final t in PetTimeOfDay.values) {
        for (final w in PetWeather.values) {
          await tester.pumpWidget(_host(PetBuddyStage(
            stage: 5,
            breed: PetBreed.black,
            time: t,
            weather: w,
            carrotCount: 1,
            anchors: a,
            reduceMotionOverride: true,
            onFeedRequest: () => true,
          )));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$t $w');
        }
      }
    });

    testWidgets('減少動態：沒有持續動畫，pumpAndSettle 可結束', (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_stage(anchors: _loadAnchors())));
      await tester.pumpAndSettle(); // 若有常駐 Ticker 會逾時失敗
      expect(tester.hasRunningAnimations, isFalse);
      final st = tester.state<PetBuddyStageState>(find.byType(PetBuddyStage));
      expect(st.isBusy, isFalse);
      expect(st.view, PetView.front);
    });

    testWidgets('胡蘿蔔 0 根：按鈕為停用外觀、點了只提示不餵', (tester) async {
      phone(tester);
      var fed = 0, empty = 0;
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        carrots: 0,
        onFeed: () {
          fed++;
          return true;
        },
        onEmpty: () => empty++,
      )));
      await tester.pumpAndSettle();
      final btn = tester.widget<PetCarrotButton>(find.byType(PetCarrotButton));
      expect(btn.empty, isTrue);
      expect(find.descendant(
          of: find.byType(PetCarrotButton),
          matching: find.byType(ColorFiltered)), findsOneWidget);
      expect(find.descendant(of: find.byType(PetCarrotButton), matching: find.text('0')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pumpAndSettle();
      expect(fed, 0);
      expect(empty, 1);
    });

    testWidgets('胡蘿蔔 > 0：正常外觀（無灰階濾鏡），點一下就餵，減少動態時瞬間完成',
        (tester) async {
      phone(tester);
      var fed = 0, done = 0;
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        carrots: 2,
        onFeed: () {
          fed++;
          return true;
        },
        onDone: () => done++,
      )));
      await tester.pumpAndSettle();
      expect(tester.widget<PetCarrotButton>(find.byType(PetCarrotButton)).empty, isFalse);
      expect(find.descendant(
          of: find.byType(PetCarrotButton),
          matching: find.byType(ColorFiltered)), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pumpAndSettle();
      expect(fed, 1);
      expect(done, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('數量 0 但帳本刷新後變 1：先 refresh 再餵，不提示', (tester) async {
      phone(tester);
      final log = <String>[];
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        carrots: 0,
        onRefresh: () async {
          log.add('refresh');
          return 1;
        },
        onFeed: () {
          log.add('feed');
          return true;
        },
        onEmpty: () => log.add('empty'),
        onDone: () => log.add('done'),
      )));
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pumpAndSettle();
      expect(log, ['refresh', 'feed', 'done']);
    });

    testWidgets('數量 0 且刷新後仍為 0：才提示，不餵', (tester) async {
      phone(tester);
      final log = <String>[];
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        carrots: 0,
        onRefresh: () async {
          log.add('refresh');
          return 0;
        },
        onFeed: () {
          log.add('feed');
          return true;
        },
        onEmpty: () => log.add('empty'),
      )));
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pumpAndSettle();
      expect(log, ['refresh', 'empty']);
    });

    testWidgets('數量 > 0：不呼叫 refresh，直接餵', (tester) async {
      phone(tester);
      final log = <String>[];
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        carrots: 2,
        onRefresh: () async {
          log.add('refresh');
          return 2;
        },
        onFeed: () {
          log.add('feed');
          return true;
        },
      )));
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pumpAndSettle();
      expect(log, ['feed']);
    });

    testWidgets('餵食失敗（onFeedRequest 回傳 false）：不播動畫、不呼叫完成', (tester) async {
      phone(tester);
      var done = 0;
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        reduce: false,
        weather: PetWeather.sunny,
        onFeed: () => false,
        onDone: () => done++,
      )));
      await tester.pump(const Duration(milliseconds: 33));
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      final st = tester.state<PetBuddyStageState>(find.byType(PetBuddyStage));
      expect(st.isBusy, isFalse);
      expect(done, 0);
    });

    testWidgets('一般模式：成功餵食播完整段動畫（飛行→咀嚼→愛心→跳）後呼叫完成',
        (tester) async {
      phone(tester);
      var done = 0;
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        reduce: false,
        weather: PetWeather.sunny,
        onDone: () => done++,
      )));
      await tester.pump(const Duration(milliseconds: 33));
      await tester.tap(find.byKey(const ValueKey('pet-carrot-button')));
      await tester.pump(const Duration(milliseconds: 33));
      final st = tester.state<PetBuddyStageState>(find.byType(PetBuddyStage));
      expect(st.isBusy, isTrue);
      var frames = 0;
      while (done == 0 && frames < 400) {
        await tester.pump(const Duration(milliseconds: 33));
        frames++;
      }
      expect(tester.takeException(), isNull);
      expect(done, 1);
      expect(st.isBusy, isFalse);
      // 飛行 .52 + 咀嚼 1.25 + 跳後 .6 ≈ 2.4 秒
      expect(frames * 33 / 1000, inInclusiveRange(2.0, 3.2));
    });

    testWidgets('一般模式：每 9 秒換側面圖走一段，走完轉回正面', (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_stage(
        anchors: _loadAnchors(),
        reduce: false,
        weather: PetWeather.rain, // 同時跑雨粒子
      )));
      final st = tester.state<PetBuddyStageState>(find.byType(PetBuddyStage));
      var sawSide = false, sawFlip = false;
      for (var i = 0; i < 520; i++) {
        await tester.pump(const Duration(milliseconds: 33));
        if (st.view == PetView.side) sawSide = true;
        if (st.isFlipped) sawFlip = true;
      }
      expect(tester.takeException(), isNull);
      expect(sawSide, isTrue, reason: '約 9 秒後應換側面圖開始走');
      expect(sawFlip || sawSide, isTrue);
      // 走完後（約 9 + 5 秒）回到正面
      for (var i = 0; i < 200 && st.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(st.isBusy, isFalse);
      expect(st.view, PetView.front);
      expect(st.isFlipped, isFalse);
      // 換掉舞台，確認 Ticker 乾淨釋放
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('舞台下方的卡片與進化畫面（360×640、字級 1.3 不溢位）', () {
    const growth = PetGrowthState(
      weightGrams: 39820,
      vitality: 80,
      todaySteps: 0,
      fedFoodIds: {},
      lastDateStr: '',
      isCrownUnlocked: false,
    );

    testWidgets('數值卡：第 N 階、體重、進度條、品種切換', (tester) async {
      phone(tester);
      PetBreed? picked;
      await tester.pumpWidget(_host(
        PetStatCard(
            growth: growth, breed: PetBreed.pink, onBreedChanged: (b) => picked = b),
        textScale: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('第 2 階'), findsOneWidget);
      expect(find.textContaining('39.82'), findsOneWidget);
      await tester.tap(find.text('黑豬'));
      await tester.pumpAndSettle();
      expect(picked, PetBreed.black);
    });

    testWidgets('排行榜卡 .board 外觀：標題與賽季膠囊同列放不下會換行', (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(
        const PetLeaderboardCard(
          myElderId: null,
          boardStyle: true,
          headerTrailing: Chip(label: Text('第 3 季・還有 12 天')),
        ),
        textScale: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('好友排行榜'), findsOneWidget);
      expect(find.text('第 3 季・還有 12 天'), findsOneWidget);
    });

    testWidgets('進化畫面：顯示「長大到第 N 階了！」，按「太棒了」關閉', (tester) async {
      phone(tester);
      await tester.pumpWidget(MaterialApp(
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: w!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => PetEvolutionDialog.show(
                context,
                PetGrowthStage.plumpPig,
                oldStage: PetGrowthStage.chubbyPig,
                breedId: 'pink',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('長大到第 3 階了！'), findsOneWidget);
      expect(find.text('福氣小豬變得更有精神了'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pet-evo-close')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('長大到第 3 階了！'), findsNothing);
    });
  });
}
