import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_home_screen.dart';

// 驗證各分頁導覽步驟：小豬／我的不可退回通用「歡迎使用」單步導覽。
void main() {
  ElderTutorialKeys keys() => ElderTutorialKeys(
        homeDateCard: GlobalKey(),
        homeNewsCard: GlobalKey(),
        homeMoreNews: GlobalKey(),
        phoneTabBar: GlobalKey(),
        phoneCall: GlobalKey(),
        phoneVideo: GlobalKey(),
        pet: GlobalKey(),
        petGreeting: GlobalKey(),
        chatVoiceToggle: GlobalKey(),
        chatInputArea: GlobalKey(),
        chatLanguageToggle: GlobalKey(),
        profileTasks: GlobalKey(),
        profileFamilyPairing: GlobalKey(),
        profileAiAssistant: GlobalKey(),
      );

  test('五個分頁皆有專屬導覽，且非通用歡迎頁', () {
    final k = keys();
    for (var i = 0; i < 5; i++) {
      final steps = elderTabTutorialSteps(i, k);
      expect(steps, isNotEmpty, reason: 'tab $i');
      expect(steps.any((s) => s.title.contains('歡迎使用')), isFalse,
          reason: 'tab $i');
    }
    expect(elderTabTutorialSteps(2, k).length, greaterThan(1));
    expect(elderTabTutorialSteps(4, k).length, greaterThan(1));
    expect(elderTabTutorialSteps(5, k), isEmpty);
  });

  test('小豬分頁第 2 步（每日吉利祝賀圖）有高光目標', () {
    final k = keys();
    final steps = elderTabTutorialSteps(2, k);
    expect(steps[1].title, contains('祝賀圖'));
    expect(steps[1].targetKey, isNotNull);
    expect(steps[1].targetKey, same(k.petGreeting));
  });
}
