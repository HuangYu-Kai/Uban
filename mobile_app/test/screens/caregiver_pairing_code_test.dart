import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/caregiver_pairing_screen.dart';

void main() {
  group('extractPairingCode', () {
    test('4 位數字回傳原值', () {
      expect(extractPairingCode('1234'), '1234');
    });

    test('前後空白與換行會被去除', () {
      expect(extractPairingCode(' 1234\n'), '1234');
    });

    test('超過 4 位數回傳 null', () {
      expect(extractPairingCode('12345'), isNull);
    });

    test('非數字回傳 null', () {
      expect(extractPairingCode('abcd'), isNull);
    });

    test('含大括號的雜訊回傳 null', () {
      expect(extractPairingCode('12{4}'), isNull);
      expect(extractPairingCode(r'\d{4}'), isNull);
    });

    test('空字串回傳 null', () {
      expect(extractPairingCode(''), isNull);
    });
  });
}
