// 第五十二輪任務 B：家屬端「互動 → 朋友」加好友入口回歸測試。
//
// 背景：使用者回報「家屬端仍舊沒看到像長輩端的社群設計，沒有加好友設計」。
// 查證後發現入口其實一直都在（FamilyFriendFeedBody._buildFriendEntryCard，
// 第五項需求就有），但主標「我的好友」讀起來像「管理現有好友」而非「新增」，
// 容易被略過——本輪只在卡片上補一個明確的「＋加好友」小標籤（純視覺補強），
// 不改動既有的 onTap／導頁邏輯。本測試證明：
//   a. 卡片上真的看得到「加好友」字樣
//   b. 點擊卡片仍然會（一如既往）導到 FamilyAddFriendScreen——證明本輪視覺
//      調整沒有動到既有的可點擊行為
//
// FamilyFriendService 的 getFeed / getIncomingRequests 會打真實 HTTP，測試
// 沙盒沒有對應網路，會以連線失敗落回既有的錯誤處理分支（皆已 try/catch，
// 見 lib/services/family_friend_service.dart）——用固定時長的 pump 讓這些
// 分支跑完即可，不用 pumpAndSettle()。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/family_add_friend_screen.dart';
import 'package:flutter_application_1/screens/family/family_friend_feed_body.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness() {
    return const MaterialApp(
      home: Scaffold(
        body: FamilyFriendFeedBody(familyId: 2, familyName: '測試家屬'),
      ),
    );
  }

  testWidgets('入口卡片上有明確的「加好友」標籤', (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('＋加好友'),
      findsOneWidget,
      reason: '第五十二輪任務 B：入口卡片必須有明確的「加好友」字樣，'
          '不能只靠「我的好友」這種容易被誤讀成純管理功能的標題',
    );
    expect(find.text('我的好友'), findsOneWidget, reason: '既有標題文字不應被取代，只是新增標籤');
  });

  testWidgets('點擊入口卡片仍然會導到 FamilyAddFriendScreen（既有行為未被破壞）',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('我的好友'));
    await tester.pump(); // Navigator.push 觸發
    await tester.pump(const Duration(milliseconds: 300)); // 轉場動畫

    expect(
      find.byType(FamilyAddFriendScreen),
      findsOneWidget,
      reason: '視覺調整（加上「加好友」標籤）不應該影響既有的 onTap 導頁行為',
    );
  });
}
