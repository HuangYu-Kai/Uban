// 家屬端第 5 批（互動分頁、AI 照護秘書、加好友）新設計 UI 回歸測試。
//
// 目的：
//   (a) 互動分頁（通話大卡／留言／時光牆／遠端監控／遠端提醒）、AI 照護秘書、加好友畫面，
//       在 360×640、textScaler 1.3、家屬主題淺／深色下不得出現溢位（CLAUDE.md §3.1 第 14 條）。
//   (b) 「選擇通話方式」面板有「一般視訊通話」與「緊急強制通話」兩個選項。
//   (c) 留言送出鈕存在且可點（socket 未連線時走既有的「目前未連線」失敗路徑，訊息保留）。
//
// 純 UI 測試：不打網路（ApiService 失敗由各畫面既有 try/catch 吞掉）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/elder.dart';
import 'package:flutter_application_1/screens/family/family_add_friend_screen.dart';
import 'package:flutter_application_1/screens/family/family_ai_copilot_screen.dart';
import 'package:flutter_application_1/screens/family/family_interaction_tab.dart';
import 'package:flutter_application_1/screens/family/widgets/fam_interaction_ui.dart';
import 'package:flutter_application_1/services/signaling.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final elder = Elder(
    id: 7,
    elderId: '1234',
    name: '王大明爸爸這個名字故意取得很長很長很長',
    gender: 'M',
    age: 78,
  );

  Widget harness(Widget child, {required bool dark}) {
    return MaterialApp(
      theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(body: child),
    );
  }

  Future<void> pumpCase(WidgetTester tester, Widget child,
      {required bool dark}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(child, dark: dark));
    await tester.pump(const Duration(seconds: 2));
  }

  Widget interactionTab() => FamilyInteractionTab(
        currentElder: elder,
        signaling: Signaling(),
        userId: 1,
        devicesMax: 2,
        tierDisplayName: '黃金尊榮版會員超長名稱',
        monitorDevices: const [
          {
            'deviceId': 1,
            'deviceName': '客廳監視機名字也很長很長很長很長',
            'isOnline': true,
            'id': 'sock-1',
          },
          {'deviceId': 2, 'deviceName': '臥室', 'isOnline': false, 'id': 'sock-2'},
        ],
        activeAlerts: const [
          {
            'alert_id': 11,
            'device_id': 1,
            'alert_type': 'fall',
            'confidence': 0.93,
          },
        ],
      );

  for (final dark in [false, true]) {
    final mode = dark ? '深色' : '淺色';

    testWidgets('互動分頁 360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(tester, interactionTab(), dark: dark);
      expect(tester.takeException(), isNull);
      // 捲到底（遠端監控、遠端提醒）再檢查一次。
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI 照護秘書 360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(
        tester,
        FamilyAiCopilotScreen(currentElder: elder),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('AI 照護秘書'), findsWidgets);
    });

    testWidgets('加好友畫面 360×640 ×1.3 $mode 無溢位', (tester) async {
      await pumpCase(
        tester,
        const FamilyAddFriendScreen(familyId: 2, familyName: '測試家屬'),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('我的代碼'), findsOneWidget);
      expect(find.text('搜尋加好友'), findsOneWidget);
      await tester.tap(find.text('搜尋加好友'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('好友管理'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('選擇通話方式面板有一般視訊通話與緊急強制通話', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    expect(find.text('視訊通話'), findsOneWidget);
    expect(find.text('語音通話'), findsOneWidget);

    await tester.tap(find.text('視訊通話'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('選擇通話方式'), findsOneWidget);
    expect(find.text('一般視訊通話'), findsOneWidget);
    expect(find.text('緊急強制通話'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('留言送出鈕存在且可點，未連線時訊息保留在輸入框', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);

    final send = find.byTooltip('送出');
    expect(send, findsOneWidget);
    await tester.scrollUntilVisible(
      send,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // 捲到離視窗頂端一段距離再點（貼著頂邊的點擊會落在捲動容器上，與按鈕無關）。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 250));
    await tester.pump(const Duration(milliseconds: 500));

    final input = find.byType(TextField);
    expect(input, findsOneWidget);
    await tester.enterText(input, '中午記得吃藥喔');
    expect(tester.widget<FamRoundBtn>(find.byType(FamRoundBtn)).onTap, isNotNull);
    await tester.tap(find.byType(FamRoundBtn));
    await tester.pump(const Duration(milliseconds: 300));

    // Signaling 在測試環境未連線 → sendHeartbeat 回 false → 失敗提示，訊息不清空。
    expect(find.text('目前未連線，請稍後再試'), findsOneWidget);
    expect(find.text('中午記得吃藥喔'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有警報的監視機列出現語音通道鈕', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    final btn = find.text('開啟語音通道 30 分鐘');
    await tester.ensureVisible(btn);
    expect(btn, findsOneWidget);
  });
}

/// FamilyTheme.buildTheme 的 context 參數只是舊簽章，內部不使用；測試給個占位。
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
