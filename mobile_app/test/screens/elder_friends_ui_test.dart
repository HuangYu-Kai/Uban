// 長輩端朋友相關畫面換新設計後的 UI 迴歸測試：朋友圈、加好友（三模式）、
// 家庭生活時光牆（長輩端與包在 FamilyThemeScope 下的家屬端各一次）。
//
// 涵蓋（皆在 360x640、textScaler 1.3、淺色／深色主題下不得有 RenderFlex 溢位，
// CLAUDE.md §3.1 第 14 條）：
//   1. 朋友圈：離線錯誤態（重試鈕）、獨立畫面外殼、單則貼文卡、空狀態、共用小元件。
//   2. 加好友：我的條碼／掃描／輸入 ID 三模式切換、輸入 ID 的欄位與搜尋鈕。
//   3. 時光牆：空狀態、含貼文（本機快取注入）、開發文面板與留言面板、朋友分頁；
//      以及外層包 FamilyThemeScope 的家屬端版本（顏色必須換成海灣藍）。
//
// 網路相關的 service 在測試沙盒會快速失敗並落回既有錯誤分支，所以只用 pump() 固定
// 次數，不用 pumpAndSettle。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/community_post.dart';
import 'package:flutter_application_1/screens/elder_add_friend_screen.dart';
import 'package:flutter_application_1/screens/elder_community_screen.dart';
import 'package:flutter_application_1/screens/elder_friend_feed_screen.dart';
import 'package:flutter_application_1/screens/elder_tabs/profile/widgets/friend_id_card.dart';
import 'package:flutter_application_1/screens/elder_tabs/widgets/elder_social_widgets.dart';
import 'package:flutter_application_1/screens/widgets/polaroid_post_card.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

Widget _app({
  required Widget child,
  bool dark = false,
  double textScale = 1.3,
  bool scaffold = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Theme(
        data: dark ? buildAppDarkTheme(context) : buildAppTheme(context),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: scaffold ? Scaffold(body: child) : child,
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 等到 [finder] 出現（最多 3 秒），避免依賴固定步數造成偶發失敗。
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

CommunityPost _post({
  String id = 'p1',
  String author = '美玉',
  String role = 'elder',
  String content = '今天跟社區的姊妹去公園健走，走了快五千步！天氣好舒服，大家都很開心。',
  String? stamp = 'walk',
  bool liked = false,
  int likes = 3,
  String? image,
  int minutesAgo = 15,
  List<CommunityComment> comments = const [],
}) =>
    CommunityPost(
      id: id,
      authorName: author,
      authorRole: role,
      content: content,
      mood: '😊',
      stampType: stamp,
      imageUrl: image,
      createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      likeCount: likes,
      isLiked: liked,
      comments: comments,
    );

final _comments = <CommunityComment>[
  CommunityComment(
    id: 'c1',
    authorName: '金花',
    message: '好厲害！下次約我一起去',
    createdAt: DateTime.now(),
  ),
  CommunityComment(
    id: 'c2',
    authorName: '宇璿',
    authorRole: 'family',
    message: '媽，記得多喝水喔',
    createdAt: DateTime.now(),
  ),
];

/// 假後端：個人資料→elder_id K7Q2、搜尋→M3T8 金花、動態→[feedCount] 則貼文、其餘→成功。
http.Client _fakeBackend({int feedCount = 2}) => MockClient((req) async {
      Map<String, dynamic> ok(dynamic data) => {'status': 'success', 'data': data};
      final path = req.url.path;
      late Map<String, dynamic> body;
      if (path.contains('/user/profile/')) {
        body = ok({'elder_id': 'K7Q2'});
      } else if (path.endsWith('/friend/search')) {
        body = ok({'elder_id': 'M3T8', 'elder_name': '金花', 'avatar_url': null});
      } else if (path.endsWith('/friend/feed')) {
        body = ok([
          for (var i = 0; i < feedCount; i++)
            {
              'id': i + 1,
              'author_name': i == 0 ? '美玉' : '金花',
              'content': '今天跟社區的姊妹去公園健走，走了快五千步！天氣好舒服。',
              'like_count': 3 + i,
              'is_liked': i == 0,
              'created_at':
                  DateTime.now().subtract(Duration(minutes: 15 + i)).toIso8601String(),
              'comments': [
                {'author_name': '宇璿', 'content': '媽，記得多喝水喔'},
              ],
            },
        ]);
      } else {
        body = ok({});
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // PolaroidPostCard 的 FlutterTts：沙盒沒有原生端，吃掉所有 channel 呼叫。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '淺色';

    group('朋友圈（$mode）', () {
      testWidgets('獨立畫面外殼：離線時顯示錯誤態與「重試」鈕，不溢位', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderFriendFeedScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);

        expect(find.text('朋友圈'), findsOneWidget);
        expect(find.text('重試'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('FriendFeedBody 本體（社群「朋友」分頁嵌入用）離線不溢位', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          scaffold: true,
          child: const FriendFeedBody(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('貼文卡、空狀態、錯誤塊、提示條、留言泡泡、虛線加照片鈕', (tester) async {
        _phone(tester);
        var liked = 0, commented = 0, photo = 0, retry = 0;
        await tester.pumpWidget(_app(
          dark: dark,
          scaffold: true,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ElderFriendPostCard(
                authorName: '一個名字非常非常非常長的朋友使用者',
                avatarUrl: null,
                timeText: '15 分鐘前',
                content: '今天跟社區的姊妹去公園健走，走了快五千步！天氣好舒服。',
                imageUrl: 'http://example.invalid/a.png',
                likeCount: 12,
                isLiked: true,
                commentCount: 5,
                onLike: () => liked++,
                onComment: () => commented++,
              ),
              const SizedBox(height: 12),
              const ElderEmptyCard(
                icon: Icons.groups_rounded,
                message: '還沒有朋友圈動態，加好友後就能看到彼此的近況！',
              ),
              const SizedBox(height: 12),
              const ElderNoticeBanner(message: '這不是 Uban 好友的 QR 碼，請確認掃描的對象'),
              const SizedBox(height: 12),
              const ElderNoticeBanner(message: '已送出邀請，等待對方同意', isError: false),
              const SizedBox(height: 12),
              const ElderCommentTile(
                name: '金花',
                message: '好厲害！下次約我一起去',
                badge: '家人',
                badgeIsFamily: true,
                timeText: '剛剛',
              ),
              const SizedBox(height: 12),
              ElderPhotoAddButton(label: '加張照片（選填）', onTap: () => photo++),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ElderErrorBlock(
                    message: '目前無法取得您的資料，請檢查網路後重試', onRetry: () => retry++),
              ),
            ],
          ),
        ));
        await _settle(tester, 3);

        await tester.tap(find.text('讚 12'));
        await tester.tap(find.text('留言 5'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(liked, 1);
        expect(commented, 1);

        final likeBtn = tester.getSize(find.ancestor(
          of: find.text('讚 12'),
          matching: find.byType(Container),
        ).first);
        expect(likeBtn.height, greaterThanOrEqualTo(56));
        expect(photo, 0);
        expect(retry, 0);
        expect(tester.takeException(), isNull);
      });
    });

    group('加好友（$mode）', () {
      testWidgets('三模式切換：我的條碼／掃描／輸入 ID，離線不溢位', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderAddFriendScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);

        expect(find.text('加好友'), findsOneWidget);
        expect(find.text('我的條碼'), findsOneWidget);
        expect(find.text('掃描'), findsOneWidget);
        expect(find.text('輸入 ID'), findsOneWidget);
        // 離線取不到自己的 ID：顯示錯誤塊與重試鈕。
        expect(find.text('重試'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('掃描'));
        await _settle(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('輸入 ID'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
      });
    });

    group('時光牆（$mode）', () {
      testWidgets('無貼文：空狀態、分享鈕、單一畫面（無分頁）', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderCommunityScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);

        expect(find.text('家庭社群'), findsOneWidget);
        expect(find.text('分享我的近況'), findsOneWidget);
        expect(find.text('還沒有近況，點上方按鈕發佈第一則吧！'), findsOneWidget);
        expect(find.byType(Tab), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('有貼文：貼文卡、留言面板、發文面板都不溢位', (tester) async {
        _phone(tester);
        final posts = [
          _post(
            comments: _comments,
            liked: true,
            stamp: 'tea',
            image: 'http://example.invalid/a.png',
          ),
          _post(
              id: 'p2',
              minutesAgo: 120,
              author: '宇璿',
              role: 'family',
              stamp: 'flower',
              content: '媽，今天記得吃藥。'),
        ];
        SharedPreferences.setMockInitialValues({
          'elder_community_posts_1':
              jsonEncode(posts.map((p) => p.toJson()).toList()),
        });
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderCommunityScreen(
              userId: 1, userName: '測試長輩', showFriendTab: true),
        ));
        await _pumpUntil(tester, find.byType(PolaroidPostCard));
        await _settle(tester, 3);

        expect(find.byType(PolaroidPostCard), findsWidgets);
        expect(find.text('讚 1'), findsNothing);
        expect(find.text('讚 3'), findsWidgets);
        expect(tester.takeException(), isNull);

        // 留言面板
        await tester.ensureVisible(find.text('留言 2'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('留言 2'));
        await _settle(tester, 10);
        expect(find.text('留言（2）'), findsOneWidget);
        expect(find.text('好厲害！下次約我一起去'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 關閉面板（點遮罩），再開發文面板
        await tester.tapAt(const Offset(180, 10));
        await _settle(tester, 15);
        // 列表剛為了點留言往下捲過，先捲回頂端才找得到分享鈕。
        await tester.drag(
          find.descendant(
              of: find.byType(RefreshIndicator), matching: find.byType(ListView)),
          const Offset(0, 1500),
        );
        await _settle(tester, 3);
        await tester.ensureVisible(find.text('分享我的近況'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('分享我的近況'));
        await _settle(tester, 10);
        expect(find.text('分享近況'), findsOneWidget);
        expect(find.text('發佈近況'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('朋友分頁：ID 卡、加好友鈕（ElevatedButton）、不出現「加朋友」', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderCommunityScreen(
              userId: 1, userName: '測試長輩', showFriendTab: true),
        ));
        await _settle(tester);
        await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
        await _settle(tester, 10);

        expect(find.widgetWithText(ElevatedButton, '加好友'), findsOneWidget);
        expect(find.text('加朋友'), findsNothing);
        expect(find.text('我的好友 ID'), findsOneWidget);
        final h = tester.getSize(find.widgetWithText(ElevatedButton, '加好友')).height;
        expect(h, greaterThanOrEqualTo(76));
        expect(tester.takeException(), isNull);
      });

      testWidgets('家屬端：外層包 FamilyThemeScope，顏色換成海灣藍且不溢位', (tester) async {
        _phone(tester);
        final posts = [_post(comments: _comments, liked: true)];
        SharedPreferences.setMockInitialValues({
          'elder_community_posts_1':
              jsonEncode(posts.map((p) => p.toJson()).toList()),
        });
        // FamilyThemeScope 自己建立家屬 Theme（淺／深由 FamilyThemeController 決定）。
        final ctrl = FamilyThemeController(dark);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: FamilyThemeScope(
              controller: ctrl,
              child: const ElderCommunityScreen(
                userId: 1,
                userName: '測試家屬',
                familyId: 1,
                showFriendTab: true,
                familyTabLabel: '家庭',
                friendTabContent: Center(child: Text('家屬朋友圈內容')),
              ),
            ),
          ),
        ));
        await _settle(tester);

        expect(find.text('家庭'), findsOneWidget);
        expect(find.byType(PolaroidPostCard), findsOneWidget);

        // 顏色確實跟著家屬主題：取到的 UbanColors 是海灣藍那組。
        final ctx = tester.element(find.byType(PolaroidPostCard));
        final c = UbanColors.of(ctx);
        final expected = dark ? UbanColors.familyDark : UbanColors.familyLight;
        expect(c.brandFill, expected.brandFill);
        expect(c.brandFill, isNot(dark ? UbanColors.dark.brandFill : UbanColors.light.brandFill));

        await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
        await _settle(tester, 10);
        expect(find.text('家屬朋友圈內容'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '淺色';

    testWidgets('朋友圈有貼文：貼文卡、已經到底囉、留言面板、發文面板（$mode）', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderFriendFeedScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);

        expect(find.byType(ElderFriendPostCard), findsWidgets);
        await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
        await _settle(tester, 3);
        expect(find.text('已經到底囉'), findsOneWidget);
        expect(find.text('載入更多'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
        await _settle(tester, 3);
        await tester.tap(find.text('留言 1').first);
        await _settle(tester, 10);
        expect(find.text('留言（1）'), findsOneWidget);
        expect(find.text('媽，記得多喝水喔'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.tapAt(const Offset(180, 10));
        await _settle(tester, 10);
        await tester.tap(find.text('分享到朋友圈'));
        await _settle(tester, 10);
        expect(find.text('好友都看得到這則貼文'), findsOneWidget);
        expect(find.text('發佈'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, _fakeBackend);
    });

    testWidgets('朋友圈滿一頁顯示「載入更多」（$mode）', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderFriendFeedScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);
        for (var i = 0; i < 12; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -900));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('載入更多'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => _fakeBackend(feedCount: 20));
    });

    testWidgets('加好友：我的條碼顯示 ID、輸入 ID 搜尋→結果卡→送出邀請（$mode）', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          dark: dark,
          child: const ElderAddFriendScreen(userId: 1, userName: '測試長輩'),
        ));
        await _settle(tester);

        // 我的條碼
        expect(find.text('K7Q2'), findsOneWidget);
        expect(find.textContaining('唸給朋友聽'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 掃描：框框說明＋掃描框疊層（沙盒沒有相機，掃描器本身會走錯誤分支）
        await tester.tap(find.text('掃描'));
        await _settle(tester);
        expect(find.text('把朋友的 Uban 條碼對準框框'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 輸入 ID
        await tester.tap(find.text('輸入 ID'));
        await _settle(tester);
        expect(find.text('輸入朋友的 4 碼 ID'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'm3t8');
        await tester.pump();
        expect(find.text('M3T8'), findsOneWidget); // 自動轉大寫
        await tester.tap(find.text('搜尋'));
        await _settle(tester);
        expect(find.text('金花'), findsOneWidget);
        expect(find.text('ID：M3T8'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 頁面標題也叫「加好友」，按鈕是結果卡裡的最後一個。
        await tester.ensureVisible(find.text('加好友').last);
        await tester.tap(find.text('加好友').last);
        await _settle(tester);
        expect(find.text('已送出邀請，等待對方同意'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 自己的 ID 與格式錯誤的提示
        await tester.enterText(find.byType(TextField), 'K7Q2');
        await tester.pump();
        await tester.tap(find.text('搜尋'));
        await _settle(tester);
        expect(find.textContaining('這是您自己的 ID'), findsOneWidget);
      }, _fakeBackend);
    });
  }

  testWidgets('FriendIdCard：有 ID、載入中兩種狀態不溢位', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      scaffold: true,
      child: const Column(children: [
        FriendIdCard(myFriendElderId: 'K7Q2'),
        FriendIdCard(myFriendElderId: null),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('K7Q2'), findsOneWidget);
    expect(find.text('載入中…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
