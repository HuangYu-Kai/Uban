import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/pet_progress_service.dart';

/// 🐷 小豬五大圓潤成長階段 (對應長輩身體數據 ✕ 純重量 kg)
///
/// ⚠️ `minWeightGrams`/`maxWeightGrams` 只是**離線 fallback**——本輪起，
/// 「目前生效中」的門檻改讀 [PetProgressService.stageBounds]（來自後端
/// `GET /api/pet/thresholds`，取不到時退回這裡的值）。判斷階段與計算
/// 進度請用 [PetGrowthStage.fromWeight] 與 [PetGrowthState] 的
/// getter，不要在別處直接讀這兩個欄位。
/// 這裡的數字已改成與後端 seed 值相同的線性曲線（每階等距 20 公斤），
/// 取代舊版非線性門檻（15000/35000/65000/90000）——兩邊必須一致，否則
/// 離線與連線時長輩會看到不同的成長階段判定。
enum PetGrowthStage {
  miniMochi(
    title: '一口小粉糰',
    minWeightGrams: 0,
    maxWeightGrams: 20000,
    icon: '🥟',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_1.png',
    description: '身形苗條精瘦的小乳豬，剛加入健康生活，散步步數 0~3 萬步！',
    accessory: '小橡實帽 🌰',
  ),
  chubbyPig(
    title: '元氣小福豬',
    minWeightGrams: 20000,
    maxWeightGrams: 40000,
    icon: '🍙',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_2.png',
    description: '臉頰微鼓、步伐輕盈，散步習慣逐漸養成，累計步數達 3~9 萬步！',
    accessory: '活力小草帽 👒',
  ),
  plumpPig(
    title: '白胖肉肉豬',
    minWeightGrams: 40000,
    maxWeightGrams: 60000,
    icon: '🍮',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_3.png',
    description: '肚子圓滾滾、Q彈飽滿！連續規律吃藥且日均步數達標，長輩福氣滿滿！',
    accessory: '吉祥小金鈴 🔔',
  ),
  auspiciousIngot(
    title: '富貴大元寶',
    minWeightGrams: 60000,
    maxWeightGrams: 80000,
    icon: '🏮',
    imageAssetPath: 'assets/images/pet_stages/pig_stage_4.png',
    description: '體態圓潤如金元寶，日均步數破 6,000 步的長者健步達人！',
    accessory: '富貴紅肚兜 🏮',
  ),
  goldenFortunePig(
    title: '招財金光大富豬',
    minWeightGrams: 80000,
    maxWeightGrams: 999999999,
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

  /// 依「目前生效中」的門檻（[PetProgressService.stageBounds]，後端資料
  /// 或離線 fallback）判斷體重對應的成長階段。門檻資料一律是 5 筆、
  /// stage_no 1~5 依序排列（[PetProgressService] 已驗證過形狀），所以
  /// 這裡直接用索引對應 [PetGrowthStage.values]，不必再比對 stageNo。
  static PetGrowthStage fromWeight(int grams) {
    final bounds = PetProgressService.stageBounds;
    int matchedIndex = 0;
    for (int i = 0; i < bounds.length && i < values.length; i++) {
      if (grams >= bounds[i].minWeightGrams) {
        matchedIndex = i;
      }
    }
    return values[matchedIndex];
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

  /// 目前生效中的階段門檻（後端資料或離線 fallback），與 [stage] 用同一
  /// 份 [PetProgressService.stageBounds]，維持前後一致——下面幾個 getter
  /// 一律透過這裡取值，不要退回讀 [PetGrowthStage] 自己的
  /// minWeightGrams/maxWeightGrams（那兩個欄位只是給
  /// [PetProgressService] 快取未命中時的離線 fallback 用，見該檔說明）。
  PetStageBounds get _liveBounds {
    final bounds = PetProgressService.stageBounds;
    final idx = stage.index.clamp(0, bounds.length - 1);
    return bounds[idx];
  }

  /// 格式化體重（純 kg）
  String get weightFormatted {
    final double kg = weightGrams / 1000.0;
    return '${kg.toStringAsFixed(1)} kg';
  }

  /// 距離下一階段還差多少 kg
  String get kgToNextStageFormatted {
    final int? max = _liveBounds.maxWeightGrams;
    if (max == null) return '已達成最高形態'; // null = 無上限 = 已在最高階
    final double diffKg = (max - weightGrams) / 1000.0;
    return '${diffKg.toStringAsFixed(1)} kg';
  }

  double get stageProgress {
    final bounds = _liveBounds;
    final int? max = bounds.maxWeightGrams;
    if (max == null) return 1.0;
    final int currentSpan = weightGrams - bounds.minWeightGrams;
    final int totalSpan = max - bounds.minWeightGrams;
    if (totalSpan <= 0) return 1.0;
    return (currentSpan / totalSpan).clamp(0.0, 1.0);
  }

  int get gramsToNextStage {
    final int? max = _liveBounds.maxWeightGrams;
    if (max == null) return 0;
    return (max - weightGrams).clamp(0, 999999999);
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
