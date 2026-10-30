import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_chat_screen.dart';

void main() {
  test('家人撥號標記可解析並剝除', () {
    const t = '好的，我幫您打視訊電話！[AUTO_CALL:video]';
    final r = parseAutoCallMarker(t);
    expect(r?.isVideo, true);
    expect(r?.friendElderId, isNull);
    expect(stripAutoCallMarkers(t), '好的，我幫您打視訊電話！');
  });

  test('好友撥號標記優先、語音通話', () {
    const t = '打給老王[AUTO_CALL_FRIEND:audio:abc123]';
    final r = parseAutoCallMarker(t);
    expect(r?.isVideo, false);
    expect(r?.friendElderId, 'abc123');
    expect(stripAutoCallMarkers(t), '打給老王');
  });

  test('無標記回 null；串流中未收完的標記前綴不外露', () {
    expect(parseAutoCallMarker('你好'), isNull);
    expect(stripAutoCallMarkers('請稍等[AUTO_CA'), '請稍等[AUTO_CA');
    expect(stripAutoCallMarkers('請稍等[AUTO_CALL:vid'), '請稍等');
  });
}
