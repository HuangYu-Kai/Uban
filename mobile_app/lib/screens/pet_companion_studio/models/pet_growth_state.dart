import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// 🐷 小豬五大圓潤成長階段
enum PetGrowthStage {
  miniMochi(
    level: 1,
    title: '一口小粉糰',
    minWeightGrams: 0,
    maxWeightGrams: 500,
    icon: '🥟',
    description: '剛出生像顆粉嫩小麻糬，頭頂的小橡實帽比腦袋還大～',
    accessory: '小橡實帽',
  ),
  chubbyPig(
    level: 2,
    title: '圓滾小福豬',
    minWeightGrams: 500,
    maxWeightGrams: 2000,
    icon: '🍙',
    description: '肚子圓了一圈，腮幫子鼓鼓的，摸起來Q彈飽滿！',
    accessory: '小橡實帽',
  ),
  plumpPig(
    level: 3,
    title: '白胖肉肉豬',
    minWeightGrams: 2000,
    maxWeightGrams: 5000,
    icon: '🍮',
    description: '吃得白白胖胖、健康有福氣，戴上了長輩專屬小金鈴！',
    accessory: '吉祥小金鈴 🔔',
  ),
  auspiciousIngot(
    level: 4,
    title: '富貴大元寶',
    minWeightGrams: 5000,
    maxWeightGrams: 10000,
    icon: '🏮',
    description: '體態圓潤如金元寶，身穿吉祥大紅肚兜，走起路來福氣生風！',
    accessory: '富貴紅肚兜 🏮',
  ),
  goldenFortunePig(
    level: 5,
    title: '福氣招財金豬',
    minWeightGrams: 10000,
    maxWeightGrams: 999999,
    icon: '👑',
    description: '【終極祥瑞神獸】全身散發溫暖金光，腳踏祥雲，福壽安康！',
    accessory: '祥雲金光光環 🌟',
  );

  final int level;
  final String title;
  final int minWeightGrams;
  final int maxWeightGrams;
  final String icon;
  final String description;
  final String accessory;

  const PetGrowthStage({
    required this.level,
    required this.title,
    required this.minWeightGrams,
    required this.maxWeightGrams,
    required this.icon,
    required this.description,
    required this.accessory,
  });

  static PetGrowthStage fromWeight(int grams) {
    if (grams < 500) return PetGrowthStage.miniMochi;
    if (grams < 2000) return PetGrowthStage.chubbyPig;
    if (grams < 5000) return PetGrowthStage.plumpPig;
    if (grams < 10000) return PetGrowthStage.auspiciousIngot;
    return PetGrowthStage.goldenFortunePig;
  }
}

/// 🏡 小豬整體狀態模型
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

  String get weightFormatted {
    if (weightGrams < 1000) {
      return '$weightGrams g';
    }
    return '${(weightGrams / 1000.0).toStringAsFixed(2)} kg';
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
