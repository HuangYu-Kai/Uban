import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/checkin_cheer_service.dart';

void main() {
  group('每日一問 questionText', () {
    test('文字回覆：附上截短到 12 字的題目', () {
      final c = CheckinCheer.tryParse({
        'cheerId': 7,
        'familyName': '璿OwO',
        'text': '好棒！',
        'questionText': '您小時候最喜歡吃的東西是什麼呢？',
      })!;
      expect(c.displayText, '璿OwO 回覆了您的回答：好棒！（「您小時候最喜歡吃的東西是…」）');
    });

    test('短題目不加刪節號；純語音回覆', () {
      final c = CheckinCheer.tryParse({
        'cheerId': 8,
        'familyName': '小美',
        'audioUrl': '/uploads/cheers/y.m4a',
        'questionText': '最愛吃什麼？',
      })!;
      expect(c.displayText, '小美 回覆了您的回答，傳了一段語音給您（「最愛吃什麼？」）');
    });
  });

  group('CheckinCheer.tryParse / displayText', () {
    test('文字 + 提醒標題', () {
      final c = CheckinCheer.tryParse({
        'cheerId': 3,
        'familyName': '小明',
        'text': '加油',
        'audioUrl': null,
        'reminderTitle': '吃藥',
      })!;
      expect(c.displayText, '小明：加油（為您完成「吃藥」加油）');
      expect(c.hasAudio, false);
    });

    test('純語音', () {
      final c = CheckinCheer.tryParse({
        'cheerId': 4,
        'familyName': '小美',
        'text': '',
        'audioUrl': '/uploads/cheers/x.m4a',
      })!;
      expect(c.displayText, '小美 傳了一段語音給您');
      expect(c.hasAudio, true);
      expect(c.hasText, false);
    });

    test('格式不合回傳 null', () {
      expect(CheckinCheer.tryParse(null), isNull);
      expect(CheckinCheer.tryParse({'familyName': 'a', 'text': 'x'}), isNull);
      expect(CheckinCheer.tryParse({'cheerId': 1}), isNull);
    });
  });

  test('CheerQueue 依序且去重', () {
    final q = CheerQueue();
    CheckinCheer mk(int id) =>
        CheckinCheer(cheerId: id, familyName: 'a', text: 't$id');
    expect(q.enqueue(mk(1)), true);
    expect(q.enqueue(mk(2)), true);
    expect(q.enqueue(mk(1)), false);
    expect(q.length, 2);
    expect(q.removeFirst()!.cheerId, 1);
    expect(q.enqueue(mk(1)), false); // 已處理過也不再收
    expect(q.removeFirst()!.cheerId, 2);
    expect(q.isEmpty, true);
  });
}
