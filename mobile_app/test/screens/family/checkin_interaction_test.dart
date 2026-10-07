// ★ 2026-10-07 打卡雙向互動（家屬端）：SendCheerSheet 基本行為、7 天歷史條、通知去重／payload。
//
// 純 UI／純函式測試：不打網路、不碰平台通道（錄音器／播放器延後建立，測試不觸發錄音）。
// 溢位以 360×640、textScaler 1.3、深淺色驗證（CLAUDE.md 規則 14）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/screens/family/home/widgets/home_checkin_card.dart';
import 'package:flutter_application_1/screens/family/sheets/send_cheer_sheet.dart';
import 'package:flutter_application_1/services/api/checkin_api.dart';
import 'package:flutter_application_1/services/checkin_notification.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget harness(Widget child, {bool dark = false}) => MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext(), isDark: dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      );

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('SendCheerSheet', () {
    testWidgets('預設送出鈕停用；點短句後填入文字並可送出，說明文字存在', (tester) async {
      await setPhone(tester);
      String? sentText;
      await tester.pumpWidget(harness(SendCheerSheet(
        elderName: '王大明爸爸這個名字故意取得很長很長很長很長',
        itemTitle: '早餐後吃降血壓藥而且事項名稱也很長很長很長很長很長',
        familyId: 1,
        elderId: '1234',
        reminderId: 5,
        sender: ({text, audioPath}) async {
          sentText = text;
          return const CheerResult(false, CheckinApi.networkErrorMessage);
        },
      )));
      await tester.pump();

      expect(find.text('文字會由小嘎唸給長輩聽，錄音會直接播放您的聲音'), findsOneWidget);
      for (final p in SendCheerSheet.presets) {
        expect(find.text(p), findsOneWidget);
      }
      FamSendButtonState state() {
        final btn = tester.widget(find.byKey(const ValueKey('cheer_send')));
        return FamSendButtonState(
            (btn as dynamic).onPressed != null);
      }

      expect(state().enabled, isFalse);

      await tester.tap(find.byKey(const ValueKey('preset_好棒！')));
      await tester.pump();
      expect(find.text('好棒！'), findsNWidgets(2)); // chip ＋ 輸入框
      expect(state().enabled, isTrue);

      await tester.tap(find.byKey(const ValueKey('cheer_send')));
      await tester.pump();
      await tester.pump();
      expect(sentText, '好棒！');
      // 失敗時顯示友善中文錯誤，面板留著可再試。
      expect(find.text(CheckinApi.networkErrorMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('輸入框限制 100 字', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(harness(const SendCheerSheet(
        elderName: '爺爺',
        itemTitle: '散步',
        familyId: 1,
        elderId: '1',
      )));
      final tf = tester.widget<TextField>(find.byKey(const ValueKey('cheer_text')));
      expect(tf.maxLength, 100);
    });

    testWidgets('深色＋360x640 無溢位', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(harness(
        const SendCheerSheet(
          elderName: '王大明爸爸這個名字故意取得很長很長很長很長',
          itemTitle: '很長的事項名稱很長的事項名稱很長的事項名稱很長的事項名稱',
          familyId: 1,
          elderId: '1',
        ),
        dark: true,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('CheckinHistoryStrip', () {
    final days = [
      {'date': '2026-10-01', 'done': 3, 'total': 3},
      {'date': '2026-10-02', 'done': 1, 'total': 3},
      {'date': '2026-10-03', 'done': 0, 'total': 2},
      {'date': '2026-10-04', 'done': 0, 'total': 0},
      {'date': '2026-10-05', 'done': 12, 'total': 12},
      {'date': '2026-10-06', 'done': 10, 'total': 12},
      {'date': '2026-10-07', 'done': 2, 'total': 4},
    ];

    for (final dark in [false, true]) {
      testWidgets('7 欄渲染且無溢位（dark=$dark）', (tester) async {
        await setPhone(tester);
        await tester.pumpWidget(harness(CheckinHistoryStrip(days: days), dark: dark));
        await tester.pump();
        expect(find.text('3/3'), findsOneWidget);
        expect(find.text('1/3'), findsOneWidget);
        expect(find.text('0/2'), findsOneWidget);
        expect(find.text('–'), findsOneWidget);
        expect(find.text('今'), findsOneWidget);
        expect(find.byType(Expanded), findsNWidgets(7));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('歷史取不到時整段隱藏', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(harness(
          CheckinHistorySection(history: Future.value(null))));
      await tester.pump();
      expect(find.text('近 7 天'), findsNothing);
    });
  });

  testWidgets('CheckinListSheet（漏打卡橫幅＋歷史＋鼓勵／打電話）360x640 無溢位', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(harness(CheckinListSheet(
      items: [
        {'id': 1, 'title': '早餐後吃降血壓藥而且名稱很長很長很長很長', 'time_str': '08:00', 'completed': true, 'created_by_role': 'elder'},
        {'id': 2, 'title': '下午散步三十分鐘名稱也很長很長很長很長', 'time_str': '15:00', 'completed': false, 'created_by_role': 'family'},
      ],
      sent: ValueNotifier<Set<int>>({1}),
      history: Future.value([
        for (var d = 1; d <= 7; d++) {'date': '2026-10-0$d', 'done': d % 3, 'total': 2},
      ]),
      elderName: '王大明爸爸這個名字故意取得很長很長很長很長',
      missedTitle: '下午散步三十分鐘名稱也很長很長很長很長',
      missedTimeStr: '15:00',
      onCheer: (_) {},
      onCall: () {},
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text('已鼓勵'), findsOneWidget);
    expect(find.byKey(const ValueKey('missed_call')), findsOneWidget);
    expect(find.byKey(const ValueKey('hist_2026-10-03')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('CheckinNotification', () {
    test('去重：同事件 10 分鐘內只放行一次，過期後可再放行', () {
      CheckinNotification.resetDedupe();
      final t0 = DateTime(2026, 10, 7, 9);
      expect(CheckinNotification.seenRecently('elder-checkin|5|2026-10-07', now: t0), isFalse);
      expect(CheckinNotification.seenRecently('elder-checkin|5|2026-10-07',
          now: t0.add(const Duration(minutes: 9))), isTrue);
      // 不同類型視為不同事件。
      expect(CheckinNotification.seenRecently('elder-checkin-missed|5|2026-10-07', now: t0), isFalse);
      expect(CheckinNotification.seenRecently('elder-checkin|5|2026-10-07',
          now: t0.add(const Duration(minutes: 11))), isFalse);
    });

    test('payload 解析：非打卡 payload 回傳 null', () {
      expect(CheckinNotification.parseTap(null), isNull);
      expect(CheckinNotification.parseTap('not json'), isNull);
      expect(CheckinNotification.parseTap('{"type":"location-alert","elderId":"1"}'), isNull);
      final tap = CheckinNotification.parseTap(
          '{"type":"elder-checkin-missed","elderId":"1234","elderName":"","reminderId":"5","title":"吃藥","localDate":"2026-10-07"}');
      expect(tap, isNotNull);
      expect(tap!.isMissed, isTrue);
      expect(tap.elderName, '長輩');
      expect(tap.reminderId, 5);
    });

    test('通知開關預設開、可關閉', () async {
      expect(await CheckinNotification.isEnabled(), isTrue);
      await CheckinNotification.setEnabled(false);
      expect(await CheckinNotification.isEnabled(), isFalse);
    });
  });
}

/// 只為了讓測試讀起來清楚的小包裝。
class FamSendButtonState {
  final bool enabled;
  const FamSendButtonState(this.enabled);
}
