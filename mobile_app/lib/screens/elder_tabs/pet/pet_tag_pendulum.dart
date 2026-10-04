import 'dart:math' as math;

/// 耳標鐘擺：阻尼彈簧 K=49、ζ=0.12（週期約 0.9 秒），對應 ui.js 的
/// `TAG_K`／`TAG_C`。角度單位為度。走路每步、跳、咀嚼各給一次衝量（[kick]）。
class PetTagPendulum {
  static const double k = 49;
  static const double zeta = 0.12;
  static final double c = 2 * zeta * math.sqrt(k);

  /// 目前角度（度）。
  double angle = 0;

  /// 角速度（度／秒）。
  double velocity = 0;

  /// 平衡位置（走路時往後甩）。
  double lean = 0;

  void kick(double v) => velocity += v;

  /// 前進 [dt] 秒（內部再切 4 個子步，與設計稿一致）。
  void step(double dt) {
    final d = dt.clamp(0.0, 0.032);
    for (var i = 0; i < 4; i++) {
      final acc = -k * (angle - lean) - c * velocity;
      velocity += acc * d / 4;
      angle += velocity * d / 4;
    }
  }

  bool get settled => velocity.abs() < 0.05 && (angle - lean).abs() < 0.05;
}
