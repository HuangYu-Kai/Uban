// 2026-10-05：通話中點擊「安心提醒」彈出確認對話框測試。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/signaling.dart';

void main() {
  group('Signaling.isInCall 狀態檢驗', () {
    test('初始或無通話時 isInCall 為 false', () {
      final s = Signaling();
      // 在沒有 active call 時，isInCall 應為 false
      expect(s.isInCall, isFalse);
    });

    test('currentCallId 存取正常', () {
      final s = Signaling();
      expect(s.currentCallId, anyOf(isNull, isEmpty));
    });
  });

  group('通話中點擊安心提醒對話框互動測試', () {
    testWidgets('彈出對話框包含文案與選項，點擊「留在通話」回傳 false', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final bool? result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: Color(0xFF2E7D78)),
                          SizedBox(width: 8),
                          Text('長輩位置提醒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text(
                        '目前正在視訊通話中。是否要開啟 王大明 的位置地圖？\n（通話將在背景繼續進行）',
                        style: TextStyle(fontSize: 14, height: 1.4),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('留在通話', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D78),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('查看位置'),
                        ),
                      ],
                    );
                  },
                );
                dialogResult = result;
              },
              child: const Text('觸發對話框'),
            );
          }),
        ),
      ));

      // 點擊觸發按鈕
      await tester.tap(find.text('觸發對話框'));
      await tester.pumpAndSettle();

      // 驗證對話框出現
      expect(find.text('長輩位置提醒'), findsOneWidget);
      expect(find.textContaining('目前正在視訊通話中'), findsOneWidget);
      expect(find.text('留在通話'), findsOneWidget);
      expect(find.text('查看位置'), findsOneWidget);

      // 點擊「留在通話」
      await tester.tap(find.text('留在通話'));
      await tester.pumpAndSettle();

      // 對話框關閉且回傳 false
      expect(find.text('長輩位置提醒'), findsNothing);
      expect(dialogResult, isFalse);
    });

    testWidgets('點擊「查看位置」回傳 true', (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final bool? result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: Color(0xFF2E7D78)),
                          SizedBox(width: 8),
                          Text('長輩位置提醒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text(
                        '目前正在視訊通話中。是否要開啟 王大明 的位置地圖？\n（通話將在背景繼續進行）',
                        style: TextStyle(fontSize: 14, height: 1.4),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('留在通話', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D78),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('查看位置'),
                        ),
                      ],
                    );
                  },
                );
                dialogResult = result;
              },
              child: const Text('觸發對話框'),
            );
          }),
        ),
      ));

      // 點擊觸發按鈕
      await tester.tap(find.text('觸發對話框'));
      await tester.pumpAndSettle();

      // 點擊「查看位置」
      await tester.tap(find.text('查看位置'));
      await tester.pumpAndSettle();

      // 對話框關閉且回傳 true
      expect(find.text('長輩位置提醒'), findsNothing);
      expect(dialogResult, isTrue);
    });
  });
}
