import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/data/privacy_policy_content.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/policy_detail_dialog.dart';

/// 條款視窗在深色模式下不得白字壓淺底（2026-10-06 回報）：
/// 內文色與卡片底色都必須來自 UbanColors，且對比足夠。
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Brightness b) {
    final tokens = b == Brightness.dark ? UbanColors.dark : UbanColors.light;
    return MaterialApp(
      theme: ThemeData(
        brightness: b,
        extensions: <ThemeExtension<dynamic>>[tokens],
      ),
      home: const Scaffold(
        body: PolicyDetailDialog(
          title: '測試條款',
          introText: '簡介文字',
          primaryColor: Color(0xFF3D9C7C),
          secondaryColor: Color(0xFF1F7A5C),
          headerIcon: Icons.shield_outlined,
          sections: [
            PrivacyPolicySection(
              title: '第一節',
              icon: Icons.lock_outline,
              bulletPoints: ['一般文字與**粗體關鍵字**'],
            ),
          ],
        ),
      ),
    );
  }

  double luminance(Color c) => c.computeLuminance();

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('條款視窗 ${b.name} 模式：內文色來自色票且與卡片底色有對比', (tester) async {
      await tester.pumpWidget(host(b));
      await tester.pump();
      final tokens = b == Brightness.dark ? UbanColors.dark : UbanColors.light;

      // 標題列壓在品牌色上：標題字色 = onBrand（深色模式為深字）
      expect(tester.widget<Text>(find.text('測試條款')).style?.color, tokens.onBrand);
      expect(tester.widget<Text>(find.text('我已閱讀並理解')).style?.color, tokens.onBrand);

      // 章節標題 Text 的顏色 = 色票 text
      final title = tester.widget<Text>(find.text('第一節'));
      expect(title.style?.color, tokens.text);

      // 內文 RichText 的 span 顏色 = 色票 text2 / text
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains('一般文字'));
      final spans = (rich.text as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.style?.color, tokens.text2);
      expect(spans.last.style?.color, tokens.text);

      // 內文與卡片底色亮度差要夠大（深色不得白字壓淺底）
      final diff = (luminance(tokens.text2) - luminance(tokens.surface)).abs();
      expect(diff, greaterThan(0.2));
      if (b == Brightness.dark) {
        expect(luminance(tokens.surface), lessThan(0.2));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
