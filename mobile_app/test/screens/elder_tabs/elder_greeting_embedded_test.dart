// ElderGreetingTab embedded 模式（嵌入「小豬」分頁下半）：放進無限高度的捲動
// 容器不得拋出無限高度等版面例外（Expanded／內部捲動在捲動容器內的典型錯誤）。
// 注意：flutter_test 用等寬的 Ahem 後備字型，祝福圖內容區（本批原封不動）的
// 窄列會出現與實機無關的 RenderFlex 溢位，所以這裡只擋「非溢位」的版面錯誤；
// 溢位以實機為準。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/elder_greeting_tab.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('embedded：在 SingleChildScrollView 內可建構',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldHandler);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: ElderGreetingTab(userId: 1, userName: '王阿公', embedded: true),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('每日吉祥祝賀圖'), findsOneWidget);
    final nonOverflow = errors
        .where((e) => !e.exceptionAsString().contains('overflowed'))
        .map((e) => e.exceptionAsString())
        .toList();
    expect(nonOverflow, isEmpty);
  });
}
