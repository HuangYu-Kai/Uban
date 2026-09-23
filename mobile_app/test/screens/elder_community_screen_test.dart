// 第五十二輪任務 A：長輩端「社群 → 朋友」加好友入口回歸測試。
//
// 背景：使用者實機回報「長輩端社群的加好友功能被拔除」。查證後發現功能本身
// （ElderAddFriendScreen）沒被刪，真正的問題是「社群 → 朋友」分頁裡完全沒有
// 按鈕導去那個畫面——只有一張顯示自己 ID 的唯讀 FriendIdCard，長輩只能繞去
// 「電話 → 朋友」才找得到入口。本測試驗證新加的「加好友」按鈕確實存在、
// 確實可點擊、點擊後確實會 push 到 ElderAddFriendScreen（不是原地沒反應）。
//
// CommunityService.getPosts / FriendService.resolveMyElderId 會打真實 HTTP，
// 測試沙盒沒有對應網路，會以連線失敗快速落回既有的錯誤處理分支（兩者皆已
// try/catch，見 lib/services/community_service.dart、lib/services/friend_service.dart）
// ——用固定時長的 pump 讓這些分支跑完即可，不用 pumpAndSettle()。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/elder_add_friend_screen.dart';
import 'package:flutter_application_1/screens/elder_community_screen.dart';

void main() {
  setUpAll(() {
    // 避免測試沙盒對外抓 Google Fonts CDN 造成未處理 Future rejection。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness() {
    return const MaterialApp(
      home: ElderCommunityScreen(
        userId: 1,
        userName: '測試長輩',
        showFriendTab: true,
      ),
    );
  }

  // 不用 find.text('朋友') 去點——實測過會 tap 在 Tab 的文字本身（Icon 在上、
  // Text 在下，兩者中心點不同），該座標有時會落在 TabBar 的量測範圍之外而
  // 完全點不中、頁面也不會切換。改成點擊 Tab 本身（整個分頁區塊的中心點）。
  // tester.tap 對 Tab 這種抽象設定用 widget 一律會印出 hitTest 警告（配置
  // widget 本身沒有對應的 RenderObject，是已知的良性誤報，不代表沒點中），
  // 故加 warnIfMissed: false 消音。
  //
  // 单一次大跨度 pump（例如直接 pump 1 秒）在本機實測會偶爾（非每次）停在
  // 舊分頁——這個畫面同時有兩支背景 Future（_loadPosts／
  // _loadMyFriendElderId）在跑，一次性跳過 1 秒可能與 TabController 的
  // animateTo 動畫在同一輪 microtask 卡到不確定的時序。改成多次小步 pump
  // 更穩定（實測連續重跑多次皆通過，單次 1 秒跳躍有時失敗）。也不能用
  // pumpAndSettle()——這個畫面的載入態動畫會讓它 5 秒都不 settle（已實測逾時）。
  Future<void> pumpToFriendTab(WidgetTester tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('社群「朋友」分頁存在明確的「加好友」按鈕', (WidgetTester tester) async {
    await pumpToFriendTab(tester);

    expect(
      find.widgetWithText(ElevatedButton, '加好友'),
      findsOneWidget,
      reason: '第五十二輪任務 A：社群「朋友」分頁必須要有明確可點擊的加好友按鈕，'
          '不能只靠唯讀的 FriendIdCard',
    );
  });

  testWidgets('點擊「加好友」按鈕會真的 push 到 ElderAddFriendScreen', (WidgetTester tester) async {
    await pumpToFriendTab(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, '加好友'));
    await tester.pump(); // Navigator.push 觸發
    await tester.pump(const Duration(milliseconds: 300)); // 轉場動畫

    expect(
      find.byType(ElderAddFriendScreen),
      findsOneWidget,
      reason: '點擊後必須真的導頁到 ElderAddFriendScreen，不是手勢被擋住、原地沒反應',
    );
  });

  testWidgets('「電話→朋友」既有入口的用詞（加好友）與新按鈕一致', (WidgetTester tester) async {
    // 不重新開一份 friends_screen.dart 的測試（不在本輪允許修改的檔案清單
    // 內），只驗證本檔新增按鈕的文案與既有入口一致，避免長輩因為兩個入口
    // 用詞不同而懷疑是不是不同功能。
    await pumpToFriendTab(tester);
    expect(find.text('加好友'), findsWidgets);
    expect(find.text('加朋友'), findsNothing,
        reason: '文案必須與 friends_screen.dart 既有的 _buildAddFriendButton 一致（「加好友」），'
            '不要另外造一個「加朋友」的說法');
  });
}
