// 長輩端浮層／新手教學換新設計後的版面回歸測試。
//
// 規則（CLAUDE.md §3.1 第 14 條）：360×640、textScaler 1.3、淺／深色下不得出現
// RenderFlex 溢位；長輩字級＝內文 ≥18、按鈕高 ≥60。另外鎖住教學「跳過」後仍寫入
// 原本的完成旗標（`tutorial_done_<id>`、`elder_all_tutorials_dismissed`）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/elder_overlay_button.dart';
import 'package:flutter_application_1/widgets/elder_reminder_dialog.dart';
import 'package:flutter_application_1/widgets/google_assistant_overlay.dart';
import 'package:flutter_application_1/widgets/heartbeat_overlay.dart';
import 'package:flutter_application_1/widgets/spotlight_tutorial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const MethodChannel _ttsChannel = MethodChannel('flutter_tts');
const StandardMethodCodec _codec = StandardMethodCodec();

const _longNote = '飯後半小時再吃，配一大杯溫開水，不要配茶或咖啡，吃完記得休息一下，'
    '如果有頭暈或不舒服要馬上跟我們說。';

ThemeData _theme(Brightness b) => ThemeData(
      brightness: b,
      useMaterial3: true,
      extensions: [b == Brightness.dark ? UbanColors.dark : UbanColors.light],
    );

Widget _app(Brightness b, double scale, Widget home) => MaterialApp(
      theme: _theme(b),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _installMocks(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_sttChannel, (call) async {
    switch (call.method) {
      case 'initialize':
      case 'listen':
      case 'has_permission':
        return true;
      case 'locales':
        return <String>[];
      default:
        return null;
    }
  });
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(_ttsChannel, (call) async => 1);
}

Future<void> _sendStt(WidgetTester tester, String method, dynamic args) async {
  final ByteData data = _codec.encodeMethodCall(MethodCall(method, args)) as ByteData;
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(_sttChannel.name, data, (_) {});
}

Future<void> _pumpN(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 同 voice_confirm 測試的收尾手法：先排空 speech_to_text 殘留計時器再拆樹。
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void _expectElderButtons(WidgetTester tester) {
  for (final e in tester.widgetList<OverlayButton>(find.byType(OverlayButton))) {
    final size = tester.getSize(find.byWidget(e));
    expect(size.height, greaterThanOrEqualTo(60), reason: '「${e.label}」按鈕高需 ≥60');
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sttChannel, null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ttsChannel, null);
  });

  for (final brightness in Brightness.values) {
    final tag = brightness == Brightness.dark ? '深色' : '淺色';

    testWidgets('教學卡第 1 步與最後一步在 360x640、1.3 倍字無溢位（$tag）', (tester) async {
      _phone(tester);
      final targetKey = GlobalKey();
      await tester.pumpWidget(_app(
        brightness,
        1.3,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Container(key: targetKey, width: 200, height: 80, color: Colors.teal),
              ),
            ),
          ),
        ),
      ));

      final ctx = tester.element(find.byType(Scaffold));
      unawaited_(SpotlightTutorial.showForce(
        ctx,
        tutorialId: 'ui_test',
        steps: [
          TutorialStep(
              targetKey: targetKey,
              title: '今天要做的事',
              body: '圈圈是今天完成了幾件事，右邊是下一件。做好了按「打卡」，也可以點進去看全部。'),
          const TutorialStep(title: '都看完了', body: '之後想再看，可以到「我的」頁重新觀看教學。'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('第 1／共 2 步'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('跳過教學'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '第 1 步不得溢位');
      _expectElderButtons(tester);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('第 2／共 2 步'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '最後一步不得溢位');
      _expectElderButtons(tester);

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsNothing, reason: '按完成後教學關閉');
    });

    testWidgets('主動關懷在 360x640、1.3 倍字無溢位（$tag）', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(brightness, 1.3, const Scaffold()));
      final ctx = tester.element(find.byType(Scaffold));
      var dismissed = false;
      showDialog<void>(
        context: ctx,
        builder: (dctx) => HeartbeatOverlay(
          message: '阿嬤，下午有點熱，記得喝杯水、休息一下喔！今天也要把窗戶打開一點，讓空氣流通。',
          type: 'greeting',
          emotion: 'caring',
          onDismiss: () {
            dismissed = true;
            Navigator.of(dctx).pop();
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('溫馨問候'), findsOneWidget);
      expect(find.text('好喔，我知道了'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectElderButtons(tester);

      await tester.tap(find.text('好喔，我知道了'));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue, reason: 'onDismiss 回呼仍要被呼叫');
    });

    testWidgets('用藥提醒在 360x640、1.3 倍字無溢位（$tag）', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(brightness, 1.3, const Scaffold()));
      final ctx = tester.element(find.byType(Scaffold));
      ElderReminderDialog.show(
        ctx,
        reminderId: 0,
        title: '降血壓藥 1 顆與維他命 D',
        timeStr: '12:30',
        category: 'medication',
        note: _longNote,
        speak: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('用藥提醒'), findsOneWidget);
      expect(find.text('稍後提醒'), findsOneWidget);
      expect(find.text('我做好了！打卡 🥕+1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectElderButtons(tester);

      // 欄寬 2:3。
      final left = tester.getSize(find.ancestor(
          of: find.text('稍後提醒'), matching: find.byType(OverlayButton)));
      final right = tester.getSize(find.ancestor(
          of: find.text('我做好了！打卡 🥕+1'), matching: find.byType(OverlayButton)));
      expect(right.width / left.width, closeTo(1.5, 0.15));
    });

    testWidgets('小嘎助理面板（聆聽中與語音確認）在 360x640、1.3 倍字無溢位（$tag）', (tester) async {
      _phone(tester);
      _installMocks(tester);
      await tester.pumpWidget(_app(
        brightness,
        1.3,
        const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GoogleAssistantOverlay(userName: '測試長輩', aiName: '小嘎', userId: 1),
          ),
        ),
      ));
      await _pumpN(tester, 10);
      expect(tester.takeException(), isNull, reason: '初始狀態不得溢位');

      // 問候語念完 → 自動開始聆聽。
      final done = _codec.encodeMethodCall(const MethodCall('speak.onComplete')) as ByteData;
      await tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(_ttsChannel.name, done, (_) {});
      await _pumpN(tester, 10);
      expect(tester.takeException(), isNull, reason: '聆聽中不得溢位');

      // 辨識出一長句 → 顯示確認區塊（版面最高的狀態）。
      await _sendStt(
        tester,
        'textRecognition',
        jsonEncode({
          'alternates': [
            {
              'recognizedWords': '今天台北的天氣怎麼樣需不需要帶傘出門還有明天會不會下雨',
              'recognizedPhrases': null,
              'confidence': 0.85,
            },
          ],
          'finalResult': true,
        }),
      );
      await _pumpN(tester, 5);
      await _sendStt(tester, 'notifyStatus', 'done');
      await _pumpN(tester, 5);

      expect(find.text('送出'), findsOneWidget);
      expect(find.text('重新說一次'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '語音確認區塊不得溢位');
      _expectElderButtons(tester);

      await _drain(tester);
    });
  }

  testWidgets('教學按「跳過教學」後仍寫入原本的完成旗標', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(Brightness.light, 1.0, const Scaffold()));
    final ctx = tester.element(find.byType(Scaffold));

    unawaited_(SpotlightTutorial.showIfNeeded(
      ctx,
      tutorialId: 'ui_skip_test',
      steps: const [
        TutorialStep(title: '歡迎使用', body: '這裡會一步步帶您認識畫面。'),
        TutorialStep(title: '第二步', body: '第二步說明。'),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('跳過教學'), findsOneWidget);

    await tester.tap(find.text('跳過教學'));
    await tester.pumpAndSettle();
    expect(find.text('跳過教學'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('elder_all_tutorials_dismissed'), isTrue);
    expect(prefs.getBool('tutorial_done_ui_skip_test'), isTrue);
  });

  testWidgets('教學已看過或已全域跳過時不顯示（守門行為不變）', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'tutorial_done_seen_test': true});
    await tester.pumpWidget(_app(Brightness.light, 1.0, const Scaffold()));
    final ctx = tester.element(find.byType(Scaffold));

    await SpotlightTutorial.showIfNeeded(
      ctx,
      tutorialId: 'seen_test',
      steps: const [TutorialStep(title: 'x', body: 'y')],
    );
    await tester.pumpAndSettle();
    expect(find.text('跳過教學'), findsNothing);
  });
}

/// 不 await 的 fire-and-forget（對話框會一直開著直到被關閉）。
void unawaited_(Future<void> f) {}
