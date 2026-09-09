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
  });

  bool get isUnlimited => initialCount == -1;

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
      unlockCondition: '田園常駐基礎鮮食',
      reactionQuote: '咔滋咔滋！晨採胡蘿蔔最清甜，小豬耳朵高興抖動～🥕✨',
      themeColor: Color(0xFFF97316),
      vitalityGain: 10,
      weightGainGrams: 40,
      intimacyGain: 5,
      soundType: 'crunch',
      initialCount: -1, // 無限量
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
