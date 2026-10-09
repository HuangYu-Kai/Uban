import 'package:flutter_application_1/services/care_message_store.dart';
import 'package:flutter_application_1/services/checkin_cheer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CareMessage audioUrl json', () {
    final t = DateTime.utc(2026, 10, 9, 8);
    test('有 audioUrl：來回保留', () {
      final m = CareMessage(
          text: '媽：加油',
          type: 'family',
          emotion: 'happy',
          receivedAt: t,
          audioUrl: '/uploads/cheers/x.m4a');
      final back = CareMessage.fromJson(m.toJson())!;
      expect(back.audioUrl, '/uploads/cheers/x.m4a');
      expect(back.text, '媽：加油');
    });
    test('無 audioUrl：不寫欄位、讀回為 null', () {
      final m = CareMessage(
          text: 'hi', type: 'chat', emotion: 'caring', receivedAt: t);
      expect(m.toJson().containsKey('audioUrl'), isFalse);
      expect(CareMessage.fromJson(m.toJson())!.audioUrl, isNull);
    });
    test('舊版 JSON（無欄位）仍可讀', () {
      final old = {
        'text': '舊訊息',
        'type': 'chat',
        'emotion': 'caring',
        'receivedAt': t.toIso8601String(),
      };
      expect(CareMessage.fromJson(old)!.audioUrl, isNull);
    });
  });

  group('聊天重播來源', () {
    test('有錄音 → 重播錄音、標籤「家人的聲音」', () {
      expect(chatReplaysRecording('/uploads/cheers/x.m4a'), isTrue);
      expect(chatReplayLabel(audioUrl: '/a.m4a', ttsLanguage: 'taigi'),
          '家人的聲音');
    });
    test('純文字 → 維持 TTS 國語／台語', () {
      expect(chatReplaysRecording(null), isFalse);
      expect(chatReplaysRecording(''), isFalse);
      expect(chatReplayLabel(ttsLanguage: 'mandarin'), '國語');
      expect(chatReplayLabel(ttsLanguage: 'taigi'), '台語');
      expect(chatReplayLabel(), '國語');
    });
    test('resolveCheerAudioUrl 相對路徑接根網址、http 原樣', () {
      expect(resolveCheerAudioUrl('/uploads/x.m4a', root: 'https://h'),
          'https://h/uploads/x.m4a');
      expect(resolveCheerAudioUrl('https://c/x.m4a', root: 'https://h'),
          'https://c/x.m4a');
    });
  });
}
