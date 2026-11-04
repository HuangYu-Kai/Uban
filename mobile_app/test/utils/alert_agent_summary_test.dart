// 2026-11：跌倒警報「情境摘要」與「長輩回覆」欄位的解析與顯示回歸測試。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_application_1/screens/family/widgets/alert_agent_summary.dart';
import 'package:flutter_application_1/utils/alert_display.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('parseAgentSummary', () {
    test('缺鍵、null、空白、字面 null 都回 null', () {
      expect(AlertDisplay.parseAgentSummary(null), isNull);
      expect(AlertDisplay.parseAgentSummary({}), isNull);
      expect(AlertDisplay.parseAgentSummary({'agent_summary': null}), isNull);
      expect(AlertDisplay.parseAgentSummary({'agent_summary': '  '}), isNull);
      expect(AlertDisplay.parseAgentSummary({'agentSummary': 'null'}), isNull);
    });
    test('snake_case 與 camelCase 都吃，並去頭尾空白', () {
      expect(AlertDisplay.parseAgentSummary({'agent_summary': ' 位置：家 '}), '位置：家');
      expect(AlertDisplay.parseAgentSummary({'agentSummary': 'x'}), 'x');
    });
  });

  group('parseElderResponse', () {
    test('缺鍵或未知值回 null', () {
      expect(AlertDisplay.parseElderResponse({}), isNull);
      expect(AlertDisplay.parseElderResponse({'elder_response': null}), isNull);
      expect(AlertDisplay.parseElderResponse({'elder_response': 'weird'}), isNull);
    });
    test('ok / need_help 標籤與原話、UTC 時間', () {
      final ok = AlertDisplay.parseElderResponse({
        'elder_response': 'ok',
        'elder_response_text': '我沒事',
        'elder_responded_at': '2026-11-07T01:02:03Z',
      })!;
      expect(ok.label, '長輩回覆：沒事');
      expect(ok.text, '我沒事');
      expect(ok.respondedAt!.toUtc().hour, 1);
      final help = AlertDisplay.parseElderResponse({'elder_response': 'need_help'})!;
      expect(help.label, '長輩回覆：需要協助');
      expect(help.text, isNull);
    });
  });

  group('AlertAgentSummary widget', () {
    Widget host(Widget child, {double w = 220}) => MaterialApp(
        home: Scaffold(body: SizedBox(width: w, child: child)));

    testWidgets('兩者皆無時不佔版面', (t) async {
      await t.pumpWidget(host(const AlertAgentSummary()));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('超長摘要與長輩原話在窄寬度下不溢位', (t) async {
      await t.pumpWidget(host(AlertAgentSummary(
        summary: '最後打卡 08:12 吃降血壓藥｜位置：家（5 分鐘前）｜' * 6,
        response: ElderResponseInfo(
            needHelp: true, text: '我跌倒了站不起來真的很痛請快點過來幫我' * 3),
      )));
      expect(tester(t), isNull);
      expect(find.text('長輩回覆：需要協助'), findsOneWidget);
    });
  });
}

Object? tester(WidgetTester t) => t.takeException();
