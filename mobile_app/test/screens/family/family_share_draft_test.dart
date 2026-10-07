// 分享草稿（ShareDraft 解析、送出鈕啟停、草稿卡各狀態）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/family/family_share_draft.dart';
import 'package:flutter_application_1/theme/family_theme.dart';

void main() {
  group('ShareDraft.tryParse', () {
    test('缺席或 null 回 null（舊版後端）', () {
      expect(ShareDraft.tryParse(null), isNull);
      expect(ShareDraft.tryParse('x'), isNull);
      expect(ShareDraft.tryParse({'text': '  '}), isNull);
    });
    test('文字與照片', () {
      final d = ShareDraft.tryParse({'text': '孫子考 100 分', 'image_url': 'http://a/b.jpg'});
      expect(d!.text, '孫子考 100 分');
      expect(d.imageUrl, 'http://a/b.jpg');
    });
    test('只有照片也成立', () {
      final d = ShareDraft.tryParse({'text': '', 'image_url': 'http://a/b.jpg'});
      expect(d, isNotNull);
    });
  });

  test('canSendShare：空白且無照片、送出中皆不可送', () {
    expect(canSendShare(text: ' ', hasImage: false, sending: false), isFalse);
    expect(canSendShare(text: ' ', hasImage: true, sending: false), isTrue);
    expect(canSendShare(text: 'hi', hasImage: false, sending: false), isTrue);
    expect(canSendShare(text: 'hi', hasImage: false, sending: true), isFalse);
  });

  Widget host(Widget child) => MaterialApp(
        theme: FamilyTheme.buildTheme(_FakeContext(), isDark: false),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('草稿卡：送出給{稱呼}可點、清空後停用、錯誤顯示', (tester) async {
    final ctrl = TextEditingController(text: '今天去公園');
    var sent = 0;
    await tester.pumpWidget(host(ShareDraftCard(
      controller: ctrl,
      imageUrl: null,
      elderName: '奶奶',
      phase: ShareCardPhase.draft,
      errorText: '送出失敗，請檢查網路後再試一次',
      onSend: () => sent++,
      onCancel: () {},
    )));
    expect(find.text('送出給奶奶'), findsOneWidget);
    expect(find.text('送出失敗，請檢查網路後再試一次'), findsOneWidget);
    await tester.tap(find.text('送出給奶奶'));
    expect(sent, 1);
    ctrl.text = '';
    await tester.pump();
    await tester.tap(find.text('送出給奶奶'));
    expect(sent, 1);
  });

  testWidgets('草稿卡：已送出顯示確認句', (tester) async {
    await tester.pumpWidget(host(ShareDraftCard(
      controller: TextEditingController(text: 'x'),
      imageUrl: null,
      elderName: '奶奶',
      phase: ShareCardPhase.sent,
      errorText: null,
      onSend: () {},
      onCancel: () {},
    )));
    expect(find.text('已送出，小嘎會在奶奶下次聊天時轉達'), findsOneWidget);
    expect(find.text('送出給奶奶'), findsNothing);
  });
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
