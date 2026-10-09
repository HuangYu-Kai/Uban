import '../../pet_companion_studio/models/pet_food_item.dart';

/// 胡蘿蔔「賺取進度」純函式（無 Flutter 依賴，可單元測試）。
///
/// 規則參數一律取自 carrot 的 [PetFoodItem]（earnStepsPerUnit／
/// earnCheckinsPerUnit／earnDailyCap），UI 文案由這裡組出，畫面不要再寫死
/// 500 或 5。
///
/// - [steps]：今日後端步數；null＝後端答不出來，提示退回通用文案。
/// - [checkins]：今日提醒打卡次數（任何提醒打卡都算，不只服藥）。
class CarrotProgress {
  final PetFoodItem food;
  final int? steps;
  final int checkins;

  CarrotProgress({
    required this.steps,
    this.checkins = 0,
    PetFoodItem? food,
  }) : food = food ?? carrotFood;

  /// 菜單中的 carrot 定義（賺取規則的唯一來源）。
  static PetFoodItem get carrotFood =>
      PetFoodItem.milestoneMenu.firstWhere((f) => f.id == 'carrot');

  /// 只需要規則文案（不需要進度）時使用，例如新手導覽。
  static CarrotProgress get rules => CarrotProgress(steps: null);

  int get stepsPerCarrot => food.earnStepsPerUnit ?? 0;
  int get checkinsPerCarrot => food.earnCheckinsPerUnit ?? 1;
  int get dailyCap => food.earnDailyCap ?? 0;

  /// 今天已賺得（尚未扣掉已吃掉的）。步數未知時只算打卡。
  int get earnedToday =>
      food.earnedCountFor(steps: steps ?? 0, checkins: checkins);

  bool get isCapped => dailyCap > 0 && earnedToday >= dailyCap;

  /// 距離下一根還差幾步：500 − steps % 500（步數未知視為 0 步）。
  int get stepsToNext {
    final per = stepsPerCarrot;
    if (per <= 0) return 0;
    return per - ((steps ?? 0) % per);
  }

  String get _checkinPhrase =>
      checkinsPerCarrot <= 1 ? '打一次卡' : '打 $checkinsPerCarrot 次卡';

  /// 舞台下方常駐提示（A）。
  String get hintText {
    if (steps == null || stepsPerCarrot <= 0) return '走路或打卡就能拿到胡蘿蔔';
    if (isCapped) return '今天的胡蘿蔔都拿到了，明天再來 🌙';
    return '再走 $stepsToNext 步，或$_checkinPhrase，就多 1 根';
  }

  /// 規則說明（沒胡蘿蔔時的提示、新手導覽共用的數字來源）。
  String get rulesText =>
      '走路每 $stepsPerCarrot 步，或打卡${checkinsPerCarrot <= 1 ? '一次' : ' $checkinsPerCarrot 次'}，'
      '就能拿到 1 根胡蘿蔔（每天最多 $dailyCap 根）';

  /// 新手導覽第 3 步內文。
  String get tutorialRulesText => '走路、打卡都能拿到胡蘿蔔，每天最多 $dailyCap 根';

  /// 點了 0 根的胡蘿蔔鈕時的提示（C）。
  String get emptyToast =>
      isCapped ? '今天的 $dailyCap 根胡蘿蔔都吃完了，明天再來 🌙' : rulesText;

  /// 剛完成一次打卡（[checkins] 為「打卡後」的次數）：這次打卡是否真的讓
  /// 胡蘿蔔 +1（已達每日上限就不會）。
  bool get lastCheckinGainedCarrot {
    if (checkins <= 0) return false;
    final before = food.earnedCountFor(
        steps: steps ?? 0, checkins: checkins - checkinsPerCarrot);
    return earnedToday > before;
  }

  static const String checkinRewardMessage = '打卡完成！小豬多了 1 根胡蘿蔔 🥕';

  /// 步數從 [prevSteps] 走到 [steps]，若跨過 [stepsPerCarrot] 的倍數而且
  /// 胡蘿蔔真的增加（未達上限）就回傳慶祝文案，否則 null（E：每個門檻只會
  /// 在「跨過」的那一次回傳一次，因為下一次比較的基準已前進）。
  String? stepMilestoneMessage(int prevSteps) {
    final now = steps;
    final per = stepsPerCarrot;
    if (now == null || per <= 0 || now <= prevSteps) return null;
    if (now ~/ per <= prevSteps ~/ per) return null;
    final before = food.earnedCountFor(steps: prevSteps, checkins: checkins);
    final gained = earnedToday - before;
    if (gained <= 0) return null;
    final mark = (now ~/ per) * per;
    return '走到 $mark 步了！小豬多了 $gained 根胡蘿蔔 🥕';
  }
}
