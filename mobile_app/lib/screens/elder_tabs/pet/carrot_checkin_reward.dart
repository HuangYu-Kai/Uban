import 'package:flutter/material.dart';

import '../../../services/friend_service.dart';
import '../../../utils/error_handler.dart';
import '../../pet_companion_studio/services/pet_progress_service.dart';
import 'carrot_progress.dart';

/// 打卡成功後的「小豬多了 1 根胡蘿蔔」提示。
///
/// 呼叫端只知道打卡成功，不知道今天賺了幾根，所以成功後讀一次
/// `GET /api/pet/food-unlocks/{elder_id}`，只有「這次打卡真的讓胡蘿蔔 +1」
/// （原本沒達每日上限）才提示。任何失敗一律靜默。
class CarrotCheckinReward {
  CarrotCheckinReward._();

  /// [messenger] 請在彈窗關閉／await 之前先取得。[elderId] 不明時用 [userId]
  /// 解析。[replaceCurrent] 為 true 時先收掉目前的 SnackBar（例如「已完成打卡」）。
  static Future<void> announce(
    ScaffoldMessengerState messenger, {
    String? elderId,
    int? userId,
    bool replaceCurrent = false,
  }) async {
    try {
      var eid = elderId;
      if ((eid == null || eid.isEmpty) && userId != null && userId > 0) {
        eid = await FriendService.resolveMyElderId(userId);
      }
      if (eid == null || eid.isEmpty) return;
      final src = await PetProgressService.loadFoodUnlocks(eid);
      if (src == null || !messenger.mounted) return;
      final progress = CarrotProgress(
        steps: src.todaySteps,
        checkins: src.medicationCheckinsToday,
      );
      if (!progress.lastCheckinGainedCarrot) return;
      if (replaceCurrent) messenger.hideCurrentSnackBar();
      ErrorHandler.showSuccessOn(messenger, CarrotProgress.checkinRewardMessage);
    } catch (_) {
      // 提示失敗不影響打卡。
    }
  }
}
