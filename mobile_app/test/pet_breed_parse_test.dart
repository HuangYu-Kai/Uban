import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/elder_tabs/pet/pet_ear_anchors.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/services/pet_leaderboard_service.dart';

void main() {
  group('PetBreed.fromId', () {
    test('已知 key', () {
      expect(PetBreed.fromId('pink'), PetBreed.pink);
      expect(PetBreed.fromId('black'), PetBreed.black);
    });
    test('null／未知／空字串退回粉紅', () {
      expect(PetBreed.fromId(null), PetBreed.pink);
      expect(PetBreed.fromId('golden'), PetBreed.pink);
      expect(PetBreed.fromId(''), PetBreed.pink);
    });
  });

  group('PetLeaderboardService.extractBreed', () {
    test('優先取 breed', () {
      expect(
          PetLeaderboardService.extractBreed(
              {'breed': 'black', 'skin': {'breed_key': 'pink'}}),
          'black');
    });
    test('沒有 breed 時取 skin.breed_key', () {
      expect(
          PetLeaderboardService.extractBreed(
              {'skin': {'breed_key': 'black'}}),
          'black');
    });
    test('舊版後端／格式不符回 null', () {
      expect(PetLeaderboardService.extractBreed({'weight_grams': 1}), isNull);
      expect(PetLeaderboardService.extractBreed(null), isNull);
      expect(PetLeaderboardService.extractBreed({'breed': 5}), isNull);
    });
    test('未知 key 原樣回傳，再由 fromId 退回粉紅', () {
      final id = PetLeaderboardService.extractBreed({'breed': 'golden'});
      expect(id, 'golden');
      expect(PetBreed.fromId(id), PetBreed.pink);
    });
  });
}
