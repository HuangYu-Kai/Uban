import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/display_text.dart';

void main() {
  group('stripEmoji', () {
    test('去掉標題尾端 emoji', () {
      expect(stripEmoji('下午補充溫開水 💧'), '下午補充溫開水');
      expect(stripEmoji('吃下午降壓藥 💊'), '吃下午降壓藥');
      expect(stripEmoji('傍晚伸展運動 🧘‍♂️'), '傍晚伸展運動');
    });

    test('純文字不變', () {
      expect(stripEmoji('吃早餐'), '吃早餐');
    });

    test('只有 emoji 時保留原字串，避免標題消失', () {
      expect(stripEmoji('💊'), '💊');
    });
  });
}
