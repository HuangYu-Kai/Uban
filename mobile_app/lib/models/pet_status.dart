/// 寵物狀態模型
/// 封裝寵物的基本數值，用於資料管理與序列化
class PetStatus {
  /// 飽食度 (0-100)
  int hunger;
  
  /// 活力 (0-100)
  int energy;
  
  /// 心情/幸福度 (0-100)
  int happiness;

  PetStatus({
    this.hunger = 50,
    this.energy = 50,
    this.happiness = 50,
  });

  /// 數值更新輔助方法，確保數值在 0-100 之間
  void update({int? hungerDelta, int? energyDelta, int? happinessDelta}) {
    if (hungerDelta != null) {
      hunger = (hunger + hungerDelta).clamp(0, 100);
    }
    if (energyDelta != null) {
      energy = (energy + energyDelta).clamp(0, 100);
    }
    if (happinessDelta != null) {
      happiness = (happiness + happinessDelta).clamp(0, 100);
    }
  }
}
