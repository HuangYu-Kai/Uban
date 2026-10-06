import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/api/ai_chat_api.dart';

void main() {
  group('AiChatApi.isTranscriptionError', () {
    test('null 與空字串視為失敗', () {
      expect(AiChatApi.isTranscriptionError(null), isTrue);
      expect(AiChatApi.isTranscriptionError(''), isTrue);
      expect(AiChatApi.isTranscriptionError('   '), isTrue);
    });

    test('整串被 [] 包住視為失敗', () {
      expect(AiChatApi.isTranscriptionError('[遠端 ASR 連線異常且本地模型未加載]'), isTrue);
      expect(AiChatApi.isTranscriptionError('[無法辨識]'), isTrue);
      expect(AiChatApi.isTranscriptionError('  [轉錄失敗: x]  '), isTrue);
    });

    test('正常文字不是失敗', () {
      expect(AiChatApi.isTranscriptionError('今天天氣很好'), isFalse);
      expect(AiChatApi.isTranscriptionError('[好] 我吃飽了'), isFalse);
      expect(AiChatApi.isTranscriptionError('我說[好]'), isFalse);
    });
  });
}
