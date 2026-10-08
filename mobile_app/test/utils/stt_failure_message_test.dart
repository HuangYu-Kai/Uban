import 'package:flutter_application_1/utils/stt_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('沒有錯誤或聽不到內容時，請長輩再說一次', () {
    expect(sttFailureMessage(null), contains('沒聽清楚'));
    expect(sttFailureMessage('error_no_match'), contains('沒聽清楚'));
    expect(sttFailureMessage('error_speech_timeout'), contains('沒聽清楚'));
  });

  test('麥克風被佔用時提示關掉其他程式', () {
    expect(sttFailureMessage('error_audio'), contains('麥克風正在被其他程式使用'));
    expect(sttFailureMessage('error_busy'), contains('麥克風正在被其他程式使用'));
  });

  test('網路與權限錯誤各自提示', () {
    expect(sttFailureMessage('error_network'), contains('網路'));
    expect(sttFailureMessage('error_permission'), contains('權限'));
  });
}
