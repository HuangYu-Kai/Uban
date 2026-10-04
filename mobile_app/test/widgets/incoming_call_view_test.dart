// 全螢幕來電畫面（IncomingCallView）回歸測試。
//
// 規則（CLAUDE.md §3.1 第 14 條）：360×640、textScaler 1.3 不得出現 RenderFlex 溢位；
// 長名稱必須可收縮。另外鎖住：拒接／接聽各只呼叫對應 callback 一次、widget 本身不導航。
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/incoming_call_view.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {double scale = 1.3, bool disableAnimations = false}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: home,
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('360x640 + textScaler 1.3：無溢位、文案正確', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(IncomingCallView(
      callerName: '宇璿',
      subtitle: '您的家人正在呼叫您！',
      onDecline: () {},
      onAccept: () {},
    )));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('宇璿 來電'), findsOneWidget);
    expect(find.text('您的家人正在呼叫您！'), findsOneWidget);
    expect(find.text('拒接'), findsOneWidget);
    expect(find.text('接聽'), findsOneWidget);
    // 脈動進行中再推進幾格仍無例外。
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('長名稱可收縮（含緊急外觀、橫放矮螢幕）不溢位', (tester) async {
    _phone(tester);
    const longName = '這是一個非常非常長的來電者名稱王小明的大女兒陳美麗女士';
    await tester.pumpWidget(_app(IncomingCallView(
      callerName: longName,
      subtitle: '$longName 正在呼叫您！$longName',
      onDecline: () {},
      onAccept: () {},
    )));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_app(IncomingCallView(
      callerName: longName,
      subtitle: '正在呼叫您！',
      isEmergency: true,
      onDecline: () {},
      onAccept: () {},
    )));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // 橫放（360 高）＋大字級。
    tester.view.physicalSize = const Size(640, 360);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('點拒接／接聽各只呼叫對應 callback 一次，且不自行導航', (tester) async {
    _phone(tester);
    int declined = 0, accepted = 0;
    await tester.pumpWidget(_app(IncomingCallView(
      callerName: '宇璿',
      subtitle: '您的家人正在呼叫您！',
      onDecline: () => declined++,
      onAccept: () => accepted++,
    )));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('拒接'));
    await tester.pump();
    expect(declined, 1);
    expect(accepted, 0);

    await tester.tap(find.text('接聽'));
    await tester.pump();
    expect(declined, 1);
    expect(accepted, 1);

    // 畫面仍在（pop 由呼叫端的 callback 決定，widget 本身不導航）。
    expect(find.byType(IncomingCallView), findsOneWidget);
  });

  testWidgets('reduceMotion：不啟動脈動動畫（可 pumpAndSettle）', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      IncomingCallView(
        callerName: '宇璿',
        subtitle: '您的家人正在呼叫您！',
        onDecline: () {},
        onAccept: () {},
      ),
      disableAnimations: true,
    ));
    // 若脈動仍在重複，pumpAndSettle 會逾時失敗。
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
