import 'package:shared_preferences/shared_preferences.dart';

import 'pet_ear_anchors.dart';

/// 小豬品種（粉紅豬／黑豬）的本機持久化。
///
/// 新功能：只存在這台裝置的 SharedPreferences（key `pet_breed`），
/// 不上傳後端，所以好友排行榜上別人的小豬一律畫粉紅豬。
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
