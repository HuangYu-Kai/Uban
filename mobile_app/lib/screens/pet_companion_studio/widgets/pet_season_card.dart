import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/pet_progress_service.dart';

/// 🗓️ 賽季資訊卡——取代原本兩份幾乎相同的 `_buildSeasonBadge()`
/// （`pet_studio_screen.dart` 與 `pet_corner_actions.dart` 各自複製一份 14pt
/// 小膠囊：「第 N 季 · 還剩 N 天」一行字，長輩讀不出來，資訊也幾乎等於零）。
///
/// 抽成單一共用元件，避免將來又長出第三份複製；同時把賽季起訖日換算成
/// 進度條、加一行白話說明，並改用 [ElderScale] 的既有文字尺度而非各自寫死
/// fontSize——這是本次改版真正的重點，不是換個外觀而已。
///
/// 呼叫端沿用既有慣例：[PetSeasonInfo] 取不到時（[PetProgressService.loadSeason]
/// 失敗）呼叫端本來就不會掛載本元件（`_season` 維持 null），本元件不需要
/// 自己再處理「沒有資料」的狀態，不顯示編造的賽季數字。
class PetSeasonCard extends StatelessWidget {
  final PetSeasonInfo season;

  /// 卡片最大寬度——固定寬度而非撐滿容器。兩個呼叫端都把本卡片放在懸浮於
  /// 畫面角落的窄欄位（見 `pet_studio_screen.dart` 右上角懸浮膠囊群、
  /// `pet_corner_actions.dart` 的同一群組），撐滿容器反而會把旁邊的問候語
  /// 或小豬的對話氣泡擠壓變形，因此維持「卡片本身有自己的寬度上限」。
  final double maxWidth;

  const PetSeasonCard({
    super.key,
    required this.season,
    this.maxWidth = 220,
  });

  @override
  Widget build(BuildContext context) {
    final int totalDays = season.endDate.difference(season.startDate).inDays;
    // 起訖日異常（例如相同一天、或後端資料錯置成負值）時進度條就顯示滿格，
    // 不要讓 0 或負的分母算出 NaN／Infinity 讓 LinearProgressIndicator 炸掉。
    final double progress = totalDays <= 0
        ? 1.0
        : (1 - (season.daysRemaining / totalDays)).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF059669).withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列：季數與剩餘天數都是短數字，但仍包 Flexible + ellipsis
            // ——同列已有圖示，符合鐵律 #14／護欄 G159「同列多元素時標題
            // 需可收縮」的判準，避免極端狀況（例如季數變成三位數）溢位。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🗓️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '第 ${season.seasonNo} 季',
                    style: ElderScale.seasonTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '還有 ${season.daysRemaining} 天結束',
              style: ElderScale.seasonSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE5F5EC),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
              ),
            ),
            const SizedBox(height: 8),
            // 白話一句：長輩不需要自己去理解「賽季」的遊戲機制，直接告訴
            // 結果會發生什麼事。maxLines 2 是留給極窄卡片（例如系統字級放
            // 大時）的保險，不是預期的正常排版。
            Text(
              '時間到會結算排名，小豬會從頭養起',
              style: ElderScale.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
