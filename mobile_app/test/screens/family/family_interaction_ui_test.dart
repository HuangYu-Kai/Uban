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

  testWidgets('互動分頁只剩單一 AI 照護秘書入口（無留言／時光牆卡），三顆快捷鈕在', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    expect(find.text('AI 照護秘書'), findsOneWidget);
    expect(find.text('分享近況'), findsOneWidget);
    expect(find.text('問近況'), findsOneWidget);
    // ★ 2026-10-07 交接 A2：第三顆快捷鈕改為「想問○○一個問題」。
    expect(find.text('想問${elder.displayName}一個問題'), findsOneWidget);
    expect(find.text('設提醒'), findsNothing);
    // 每日一問卡已移除；A3 新增「家庭近況」卡。
    expect(find.text('每日一問'), findsNothing);
    expect(find.text('家庭近況'), findsOneWidget);
    expect(find.text('家庭生活時光牆'), findsNothing);
    expect(find.textContaining('留言給'), findsNothing);
    expect(find.byTooltip('送出'), findsNothing);
  });

  testWidgets('點「分享近況」開啟秘書並預填、不自動送出', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    await tester.ensureVisible(find.text('分享近況'));
    await tester.pump();
    await tester.tap(find.text('分享近況'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '跟${elder.displayName}說：');
    expect(tester.takeException(), isNull);
  });

  testWidgets('點「想問○○一個問題」開啟秘書並預填「想問{稱呼}：」', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    final chip = find.text('想問${elder.displayName}一個問題');
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '想問${elder.displayName}：');
    expect(tester.takeException(), isNull);
  });

  testWidgets('有警報的監視機列出現語音通道鈕', (tester) async {
    await pumpCase(tester, interactionTab(), dark: false);
    final btn = find.text('開啟語音通道 30 分鐘');
    // 2026-10-07 每日一問卡片讓內容變長，SliverList 懶建構：先捲到按鈕再驗證。
    await tester.scrollUntilVisible(btn, 300,
        scrollable: find.byType(Scrollable).first);
    expect(btn, findsOneWidget);
  });
}

/// FamilyTheme.buildTheme 的 context 參數只是舊簽章，內部不使用；測試給個占位。
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
