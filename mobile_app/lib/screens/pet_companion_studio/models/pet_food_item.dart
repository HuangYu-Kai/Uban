import 'package:flutter/material.dart';

class PetFoodItem {
  final int stepMilestone;

  /// 今日「服藥打卡」次數門檻——與 [stepMilestone] 是 OR 關係，兩者達成
  /// 其一即可解鎖（見 [isUnlockedFor]），對應文案「散步達 N 步或服藥打卡
  /// M 次」。0 代表不設防（例如 [PetFoodItem.milestoneMenu] 的常駐基礎
  /// 食物 carrot，本來就靠 [stepMilestone]=0 恆解鎖）。
  final int medicationCheckinMilestone;
  final String id;
  final String name;
  final String emoji;
  final String imageAsset;
  final String subtitle;
  final String unlockCondition;
  final String reactionQuote;
  final Color themeColor;
  final int vitalityGain;
  final int weightGainGrams;
  final int intimacyGain;
  final String soundType; // crunch, sweet, chew, feast
  final int initialCount; // -1 for unlimited

  /// 「賺取制」食物專用參數——目前只有 carrot 使用，其餘食物一律是 null。
  /// null 代表沿用舊制「解鎖後給固定份數」的模型（[initialCount] 直接就是
  /// 當天可餵份數，庫存打完就沒了，不再補）。
  ///
  /// ⚠️ 第五十一輪修復：carrot 原本 [stepMilestone]=0 且 [initialCount]=-1，
  /// 等於「恆解鎖＋無限量」——使用者實機發現可以無限次投餵同一顆
  /// 胡蘿蔔。改為「賺取制」：每走 [earnStepsPerUnit] 步、或每完成
  /// [earnCheckinsPerUnit] 次生活排程打卡各兌換 1 份，兩者相加後再夾在
  /// [earnDailyCap] 這個每日上限內；已賺得的份數扣掉今天已經吃掉的份數
  /// （由後端食物帳本 `GET/POST /api/pet/food-ledger` 持久化，見
  /// `PetProgressService.loadFoodLedger`／`recordFoodConsumption`），
  /// 才是目前真正可餵的份數。實際的「已賺得－已消耗」換算邏輯在呼叫端
  /// （`ElderProfileTab`／`PetStudioScreen`），本類別只保存規則參數與
  /// [earnedCountFor] 這個純函式換算。
  final int? earnStepsPerUnit;
  final int? earnCheckinsPerUnit;
  final int? earnDailyCap;

  const PetFoodItem({
    required this.stepMilestone,
    this.medicationCheckinMilestone = 0,
    required this.id,
    required this.name,
    required this.emoji,
    required this.imageAsset,
    required this.subtitle,
    required this.unlockCondition,
    required this.reactionQuote,
    required this.themeColor,
    this.vitalityGain = 12,
    this.weightGainGrams = 50,
    this.intimacyGain = 6,
    this.soundType = 'crunch',
    this.initialCount = 1,
    this.earnStepsPerUnit,
    this.earnCheckinsPerUnit,
    this.earnDailyCap,
  });

  bool get isUnlimited => initialCount == -1;

  /// 是否為「賺取制」食物（見 [earnStepsPerUnit] 等欄位說明）。
  bool get isEarnedQuantity => earnDailyCap != null;

  /// 依賺取規則換算「今天已賺得」的份數（尚未扣掉今天已消耗的部分——扣除
  /// 邏輯在呼叫端合併食物帳本後處理）。非賺取制食物（[isEarnedQuantity]
  /// 為 false）一律回傳 0，呼叫端不應該對這類食物呼叫本方法。
  int earnedCountFor({required int steps, required int checkins}) {
    final cap = earnDailyCap;
    final stepsPerUnit = earnStepsPerUnit;
    final checkinsPerUnit = earnCheckinsPerUnit;
    if (cap == null ||
        stepsPerUnit == null ||
        stepsPerUnit <= 0 ||
        checkinsPerUnit == null ||
        checkinsPerUnit <= 0) {
      return 0;
    }
    final int fromSteps = steps ~/ stepsPerUnit;
    final int fromCheckins = checkins ~/ checkinsPerUnit;
    return (fromSteps + fromCheckins).clamp(0, cap);
  }

  /// 判斷這項食物「今天」是否已解鎖：散步步數達標「或」服藥打卡次數達
  /// 標，兩者擇一即可（對應 [unlockCondition] 的文案）。
  ///
  /// ⚠️ 故意不比照再加一個「運動事件數」一起做 OR——後端
  /// `GET /api/pet/food-unlocks/{elder_id}` 的 `exercise_events_today`
  /// 目前恆為 0（activity_log 的 exercise 事件全專案只有讀取端、沒有任何
  /// 寫入路徑，見 uban-api/routers/pet.py 該端點的說明），現在納入只會
  /// 產生一個永遠不成立的死條件。等後端補上寫入路徑後，可以在這裡新增
  /// exerciseMilestone 欄位，比照 currentSteps／medicationCheckinsToday
  /// 的模式一起做 OR。
  bool isUnlockedFor({
    required int currentSteps,
    required int medicationCheckinsToday,
  }) {
    return currentSteps >= stepMilestone ||
        medicationCheckinsToday >= medicationCheckinMilestone;
  }

  static const List<PetFoodItem> milestoneMenu = [
    PetFoodItem(
      stepMilestone: 0,
      id: 'carrot',
      name: '陽光脆胡蘿蔔',
      emoji: '🥕',
      imageAsset: 'assets/images/pet_foods/food_carrot.png',
      subtitle: '爽脆多汁，保護好眼力',
      // ⚠️ 第五十一輪修復：文案從「田園常駐基礎鮮食」改成寫實描述賺取
      // 規則——舊文案配合 initialCount:-1 給人「隨便吃」的印象，這正是
      // 使用者實機發現可以無限次投餵同一顆胡蘿蔔的根因之一。
      unlockCondition: '每走 500 步或完成 1 次生活排程打卡兌換 1 份，每日最多 5 份',
      reactionQuote: '咔滋咔滋！晨採胡蘿蔔最清甜，小豬耳朵高興抖動～🥕✨',
      themeColor: Color(0xFFF97316),
      vitalityGain: 10,
      weightGainGrams: 40,
      intimacyGain: 5,
      soundType: 'crunch',
      // 不再是 -1（無限量）。賺取制食物的實際可餵份數由呼叫端用
      // earnedCountFor() 換算「今天已賺得」再扣掉食物帳本的「今天已消耗」
      // 算出，這裡的 initialCount 只是資料形狀需要的預設值，不會被讀取
      // （見 ElderProfileTab/_PetStudioScreenState 的庫存計算邏輯）。
      initialCount: 0,
      earnStepsPerUnit: 500,
      earnCheckinsPerUnit: 1,
      earnDailyCap: 5,
    ),
    PetFoodItem(
      stepMilestone: 1000,
      medicationCheckinMilestone: 1,
      id: 'apple',
      name: '蜜糖紅蘋果',
      emoji: '🍎',
      imageAsset: 'assets/images/pet_foods/food_apple.png',
      subtitle: '清甜爽口，平平安安',
      unlockCondition: '散步達 1,000 步或服藥打卡 1 次',
      reactionQuote: '好甜好脆的紅蘋果！小豬笑得眼睛瞇成彎月～🍎❤️',
      themeColor: Color(0xFFEF4444),
      vitalityGain: 15,
      weightGainGrams: 70,
      intimacyGain: 8,
      soundType: 'crunch',
      initialCount: 3,
    ),
    PetFoodItem(
      stepMilestone: 2000,
      medicationCheckinMilestone: 2,
      id: 'cabbage',
      name: '鮮嫩高麗菜葉',
      emoji: '🥬',
      imageAsset: 'assets/images/pet_foods/food_cabbage.png',
      subtitle: '晨採多汁，幫助好消化',
      unlockCondition: '散步達 2,000 步或服藥打卡 2 次',
      reactionQuote: '喀嚓喀嚓！像吃洋芋片一樣清脆，整隻小豬精神飽滿～🥬🌱',
      themeColor: Color(0xFF10B981),
      vitalityGain: 16,
      weightGainGrams: 50,
      intimacyGain: 8,
      soundType: 'crunch',
      initialCount: 2,
    ),
    PetFoodItem(
      stepMilestone: 3000,
      medicationCheckinMilestone: 2,
      id: 'sweet_potato',
      name: '炭烤金黃番薯',
      emoji: '🍠',
      imageAsset: 'assets/images/pet_foods/food_sweet_potato.png',
      subtitle: '台灣古早味，暖胃好香甜',
      unlockCondition: '散步達 3,000 步或服藥打卡 2 次',
      reactionQuote: '呼呼～熱騰騰的炭烤番薯！小豬捧著小口慢慢咬，好幸福～🍠💛',
      themeColor: Color(0xFFD97706),
      vitalityGain: 20,
      weightGainGrams: 120,
      intimacyGain: 10,
      soundType: 'chew',
      initialCount: 2,
    ),
    PetFoodItem(
      stepMilestone: 5000,
      medicationCheckinMilestone: 3,
      id: 'corn',
      name: '甜糯珍珠玉米',
      emoji: '🌽',
      imageAsset: 'assets/images/pet_foods/food_corn.png',
      subtitle: '粒粒金黃，金玉滿堂',
      unlockCondition: '散步達 5,000 步或服藥打卡 3 次',
      reactionQuote: '小嘴像打字機一樣嗒嗒嗒把玉米粒啃光光，真香～🌽😋',
      themeColor: Color(0xFFEAB308),
      vitalityGain: 25,
      weightGainGrams: 150,
      intimacyGain: 12,
      soundType: 'chew',
      initialCount: 1,
    ),
    PetFoodItem(
      stepMilestone: 6000,
      medicationCheckinMilestone: 3,
      id: 'watermelon',
      name: '沁涼大西瓜',
      emoji: '🍉',
      imageAsset: 'assets/images/pet_foods/food_watermelon.png',
      subtitle: '消暑解渴，多汁甘甜',
      unlockCondition: '散步達 6,000 步或服藥打卡 3 次',
      reactionQuote: '大口埋進甜西瓜裡！滿臉果汁開懷大笑，太涼爽啦～🍉💦',
      themeColor: Color(0xFFEC4899),
      vitalityGain: 28,
      weightGainGrams: 200,
      intimacyGain: 15,
      soundType: 'sweet',
      initialCount: 1,
    ),
    PetFoodItem(
      stepMilestone: 8000,
      medicationCheckinMilestone: 4,
      id: 'peach_cake',
      name: '壽桃五穀福糕',
      emoji: '🎂',
      imageAsset: 'assets/images/pet_foods/food_peach_cake.png',
      subtitle: '萬步達標，福壽雙全特餐',
      unlockCondition: '散步達 8,000 步或服藥打卡 4 次（終極達標）',
      reactionQuote: '哇！熱騰騰的壽桃福糕！今天步數圓滿達成，宇璿是超級健康之星 👑🎂🌟！',
      themeColor: Color(0xFF8B5CF6),
      vitalityGain: 40,
      weightGainGrams: 350,
      intimacyGain: 30,
      soundType: 'feast',
      initialCount: 1,
    ),
  ];
}
