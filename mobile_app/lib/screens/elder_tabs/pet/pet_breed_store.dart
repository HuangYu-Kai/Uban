import 'package:shared_preferences/shared_preferences.dart';

import 'pet_ear_anchors.dart';

/// 小豬品種（粉紅豬／黑豬）的本機持久化。
///
/// 小豬品種由後端指派（隨機，開發者可覆寫），App 不能自行切換。
/// 這裡只是離線快取（SharedPreferences key `pet_breed`）：先讀它讓畫面
/// 立刻有品種，拿到後端回應後再用伺服器值覆寫。
class PetBreedStore {
  PetBreedStore._();

  static const String prefKey = 'pet_breed';

  static Future<PetBreed> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PetBreed.fromId(prefs.getString(prefKey));
    } catch (_) {
      return PetBreed.pink;
    }
  }

  static Future<void> save(PetBreed breed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, breed.id);
    } catch (_) {
      // 存不進去就只在這次執行期間有效，不打斷長輩操作。
    }
  }
}
