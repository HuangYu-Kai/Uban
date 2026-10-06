import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/services/pet_weight_sync.dart';

void main() {
  group('decideWeightAction', () {
    test('伺服器無資料 → 推本機', () {
      expect(decideWeightAction(local: 1250, server: null),
          PetWeightAction.pushLocal);
    });
    test('本機較重（離線餵過）→ 推本機', () {
      expect(decideWeightAction(local: 3000, server: 2000),
          PetWeightAction.pushLocal);
    });
    test('伺服器較重（換機／重裝）→ 採用伺服器', () {
      expect(decideWeightAction(local: 1250, server: 52000),
          PetWeightAction.adoptServer);
    });
    test('相同 → 不動作', () {
      expect(decideWeightAction(local: 1250, server: 1250),
          PetWeightAction.keepLocal);
    });
  });

  group('賽季感知', () {
    test('伺服器賽季較新 → 即使本機較重也採用伺服器', () {
      expect(
          decideWeightAction(
              local: 90000, server: 1250, localSeason: 2, serverSeason: 3),
          PetWeightAction.adoptServer);
    });
    test('同賽季 → 本機較重仍推本機', () {
      expect(
          decideWeightAction(
              local: 3000, server: 2000, localSeason: 3, serverSeason: 3),
          PetWeightAction.pushLocal);
    });
    test('本機賽季未知 → 套用一般取較重規則', () {
      expect(decideWeightAction(local: 3000, server: 1250, serverSeason: 3),
          PetWeightAction.pushLocal);
      expect(decideWeightAction(local: 1250, server: 3000, serverSeason: 3),
          PetWeightAction.adoptServer);
    });
    test('伺服器無體重列 → 仍推本機（不因賽季採用 null）', () {
      expect(
          decideWeightAction(
              local: 5000, server: null, localSeason: 1, serverSeason: 3),
          PetWeightAction.pushLocal);
    });
    test('isNewerSeason', () {
      expect(isNewerSeason(local: 2, server: 3), isTrue);
      expect(isNewerSeason(local: 3, server: 3), isFalse);
      expect(isNewerSeason(local: null, server: 3), isFalse);
      expect(isNewerSeason(local: 2, server: null), isFalse);
    });
  });

  group('mergeFedWeight', () {
    test('取較大者，本機領先不倒退', () {
      expect(mergeFedWeight(local: 3000, server: 2050), 3000);
      expect(mergeFedWeight(local: 1300, server: 5000), 5000);
    });
  });

  test('newEventId 唯一且不超過 64 字元', () {
    final a = PetWeightSync.newEventId();
    final b = PetWeightSync.newEventId();
    expect(a, isNot(b));
    expect(a.length, lessThanOrEqualTo(64));
  });
}
