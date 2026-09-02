import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// 🐷 小豬五大圓潤成長階段 (對應長輩身體數據 ✕ 純重量 kg)
enum PetGrowthStage {
  miniMochi(
    title: '一口小粉糰',
    minWeightGrams: 0,
    maxWeightGrams: 15000,
    icon: '🥟',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_1.png',
    description: '身形苗條精瘦的小乳豬，剛加入健康生活，散步步數 0~3 萬步！',
    accessory: '小橡實帽 🌰',
  ),
  chubbyPig(
    title: '元氣小福豬',
    minWeightGrams: 15000,
    maxWeightGrams: 35000,
    icon: '🍙',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_2.png',
    description: '臉頰微鼓、步伐輕盈，散步習慣逐漸養成，累計步數達 3~9 萬步！',
    accessory: '活力小草帽 👒',
  ),
  plumpPig(
    title: '白胖肉肉豬',
    minWeightGrams: 35000,
    maxWeightGrams: 65000,
    icon: '🍮',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_3.png',
    description: '肚子圓滾滾、Q彈飽滿！連續規律吃藥且日均步數達標，長輩福氣滿滿！',
    accessory: '吉祥小金鈴 🔔',
  ),
  auspiciousIngot(
    title: '富貴大元寶',
    minWeightGrams: 65000,
    maxWeightGrams: 90000,
    icon: '🏮',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_4.png',
    description: '體態圓潤如金元寶，日均步數破 6,000 步的長者健步達人！',
    accessory: '富貴紅肚兜 🏮',
  ),
  goldenFortunePig(
    title: '招財金光大富豬',
    minWeightGrams: 90000,
    maxWeightGrams: 999999,
    icon: '👑',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_5.png',
    description: '【終極祥瑞神獸】渾身福氣特大圓球，散發溫暖金光，全家福壽安康！',
    accessory: '祥雲金光光環 🌟',
  );

  final String title;
  final int minWeightGrams;
  final int maxWeightGrams;
  final String icon;
  final String imageAssetPath;
  final String description;
  final String accessory;

  const PetGrowthStage({
    required this.title,
    required this.minWeightGrams,
    required this.maxWeightGrams,
    required this.icon,
    required this.imageAssetPath,
    required this.description,
    required this.accessory,
  });

  static PetGrowthStage fromWeight(int grams) {
    if (grams < 15000) return PetGrowthStage.miniMochi;
    if (grams < 35000) return PetGrowthStage.chubbyPig;
    if (grams < 65000) return PetGrowthStage.plumpPig;
    if (grams < 90000) return PetGrowthStage.auspiciousIngot;
    return PetGrowthStage.goldenFortunePig;
  }
}

/// 🏡 小豬整體狀態模型 (純重量 kg 制)
class PetGrowthState {
  final int weightGrams;
  final int vitality;
  final int todaySteps;
  final Set<String> fedFoodIds;
  final String lastDateStr;
  final bool isCrownUnlocked;

  const PetGrowthState({
    required this.weightGrams,
    required this.vitality,
    required this.todaySteps,
    required this.fedFoodIds,
    required this.lastDateStr,
    required this.isCrownUnlocked,
  });

  PetGrowthStage get stage => PetGrowthStage.fromWeight(weightGrams);

  /// 格式化體重（純 kg）
  String get weightFormatted {
    final double kg = weightGrams / 1000.0;
    return '${kg.toStringAsFixed(1)} kg';
  }

  /// 距離下一階段還差多少 kg
  String get kgToNextStageFormatted {
    if (stage == PetGrowthStage.goldenFortunePig) return '已達成最高形態';
    final double diffKg = (stage.maxWeightGrams - weightGrams) / 1000.0;
    return '${diffKg.toStringAsFixed(1)} kg';
  }

  double get stageProgress {
    if (stage == PetGrowthStage.goldenFortunePig) return 1.0;
    final int currentSpan = weightGrams - stage.minWeightGrams;
    final int totalSpan = stage.maxWeightGrams - stage.minWeightGrams;
    return (currentSpan / totalSpan).clamp(0.0, 1.0);
  }

  int get gramsToNextStage {
    if (stage == PetGrowthStage.goldenFortunePig) return 0;
    return (stage.maxWeightGrams - weightGrams).clamp(0, 999999);
  }

  PetGrowthState copyWith({
    int? weightGrams,
    int? vitality,
    int? todaySteps,
    Set<String>? fedFoodIds,
    String? lastDateStr,
    bool? isCrownUnlocked,
  }) {
    return PetGrowthState(
      weightGrams: weightGrams ?? this.weightGrams,
      vitality: vitality ?? this.vitality,
      todaySteps: todaySteps ?? this.todaySteps,
      fedFoodIds: fedFoodIds ?? this.fedFoodIds,
      lastDateStr: lastDateStr ?? this.lastDateStr,
      isCrownUnlocked: isCrownUnlocked ?? this.isCrownUnlocked,
    );
  }
}

/// 💾 本地持久化存檔服務 (SharedPreferences)
class PetStorageService {
  static const String _keyWeight = 'uban_pet_weight_grams';
  static const String _keyVitality = 'uban_pet_vitality';
  static const String _keyLastDate = 'uban_pet_last_date';
  static const String _keyFedFoods = 'uban_pet_fed_foods_json';
  static const String _keyCrownUnlocked = 'uban_pet_crown_unlocked';

  static Future<PetGrowthState> loadState({int currentSensorSteps = 3500}) async {
    final prefs = await SharedPreferences.getInstance();
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final int savedWeight = prefs.getInt(_keyWeight) ?? 1250; // 預設 1.25kg (Lv.2 圓滾小福豬)
    int savedVitality = prefs.getInt(_keyVitality) ?? 85;
    final String lastDate = prefs.getString(_keyLastDate) ?? todayStr;
    bool isCrownUnlocked = prefs.getBool(_keyCrownUnlocked) ?? false;

    Set<String> fedFoods = {};
    final String? foodsJson = prefs.getString(_keyFedFoods);
    if (foodsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(foodsJson);
        fedFoods = list.map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    // 跨日自動重置 (零懲罰：體重/成長永久保留，今日食物盤與每日活力重置)
    if (lastDate != todayStr) {
      fedFoods.clear();
      savedVitality = 80; // 晨間基礎活力
      isCrownUnlocked = currentSensorSteps >= 8000;
      await saveState(PetGrowthState(
        weightGrams: savedWeight,
        vitality: savedVitality,
        todaySteps: currentSensorSteps,
        fedFoodIds: fedFoods,
        lastDateStr: todayStr,
        isCrownUnlocked: isCrownUnlocked,
      ));
    }

    return PetGrowthState(
      weightGrams: savedWeight,
      vitality: savedVitality.clamp(0, 100),
      todaySteps: currentSensorSteps,
      fedFoodIds: fedFoods,
      lastDateStr: todayStr,
      isCrownUnlocked: isCrownUnlocked || currentSensorSteps >= 8000,
    );
  }

  static Future<void> saveState(PetGrowthState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWeight, state.weightGrams);
    await prefs.setInt(_keyVitality, state.vitality);
    await prefs.setString(_keyLastDate, state.lastDateStr);
    await prefs.setString(_keyFedFoods, jsonEncode(state.fedFoodIds.toList()));
    await prefs.setBool(_keyCrownUnlocked, state.isCrownUnlocked);
  }
}
