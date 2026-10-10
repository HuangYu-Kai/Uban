import 'package:flutter_application_1/services/checkin_cheer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseChatHistoryItem', () {
    test('family 有錄音：帶出 audioUrl', () {
      final h = parseChatHistoryItem({
        'role': 'family',
        'text': '女兒小美 傳了一段語音給您',
        'audio_url': '/uploads/cheers/a.m4a',
        'cheer_id': 5,
      })!;
      expect(h.isFamily, isTrue);
      expect(h.isUser, isFalse);
      expect(h.audioUrl, '/uploads/cheers/a.m4a');
      expect(chatReplaysRecording(h.audioUrl), isTrue);
    });
    test('family 無錄音（null／空字串）：audioUrl 為 null', () {
      expect(
          parseChatHistoryItem(
                  {'role': 'family', 'text': '媽：加油', 'audio_url': null})!
              .audioUrl,
          isNull);
      expect(
          parseChatHistoryItem({'role': 'family', 'text': 'x', 'audio_url': ''})!
              .audioUrl,
          isNull);
    });
    test('user／assistant：不帶 audioUrl；缺 role 視為 user', () {
      expect(parseChatHistoryItem({'role': 'assistant', 'text': 'hi'})!.isUser,
          isFalse);
      expect(parseChatHistoryItem({'text': 'hi'})!.isUser, isTrue);
      expect(
          parseChatHistoryItem({'role': 'user', 'text': 'hi', 'audio_url': '/a'})!
              .audioUrl,
          isNull);
    });
    test('空文字或非 Map：回 null', () {
      expect(parseChatHistoryItem({'role': 'family', 'text': ''}), isNull);
      expect(parseChatHistoryItem('x'), isNull);
      expect(parseChatHistoryItem(null), isNull);
    });
  });
}
