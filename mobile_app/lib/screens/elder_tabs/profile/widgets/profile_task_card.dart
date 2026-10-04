import 'package:flutter/material.dart';

import '../../../../utils/reminder_schedule.dart';
import '../../../../widgets/ui/ui.dart';

/// 「我的」分頁的任務卡（設計稿 `.taskcard`）：進度環＋下一件＋打卡鈕，點卡片開抽屜。
///
/// 與首頁任務卡同一個視覺與同一套判斷（[nextDue]／[groupByStatus]），但這個 widget
/// 只負責呈現：資料由呼叫端傳入，打卡一律交給 [onCheckIn]（「我的」分頁傳入既有的
/// `_toggleTaskCompletion`），不碰 SharedPreferences／API。
class ProfileTaskCard extends StatelessWidget {
  final List<Map<String, dynamic>> reminders;
  final Set<int> completedIds;
  final bool isLoading;

  /// 讀取失敗與「真的沒有提醒」是兩種畫面（第四十九輪：避免網路不穩被誤導成
  /// 「今天沒有藥要吃」）。
  final bool hasLoadError;

  /// 按下「打卡」時以該筆提醒呼叫。
  final void Function(Map<String, dynamic> reminder) onCheckIn;

  /// 點卡片本身（開抽屜）。
  final VoidCallback onOpenSheet;

  /// 測試用：固定「現在」。正式呼叫端不傳。
  final DateTime? now;

  const ProfileTaskCard({
    super.key,
    required this.reminders,
    required this.completedIds,
    required this.isLoading,
    required this.hasLoadError,
    required this.onCheckIn,
    required this.onOpenSheet,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);

    if (isLoading) {
      return UbanCard(
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text('提醒讀取中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w700, c.text)),
            ),
          ],
        ),
      );
    }

    final t = now ?? DateTime.now();
    final next = nextDue(reminders, completedIds, t);
    if (next == null && hasLoadError) {
      return UbanCard(
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 28, color: c.text3),
            const SizedBox(width: 14),
            Expanded(
              child: Text('提醒暫時讀不到，請確認網路連線',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w700, c.text)),
            ),
          ],
        ),
      );
    }

    final groups = groupByStatus(reminders, completedIds, t);
    final done = groups.done.length;
    final total = done + groups.dueNow.length + groups.later.length;

    final Widget right;
    if (next == null) {
      right = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 24, color: c.brandStrong),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  total == 0 ? '今天沒有要做的事' : '今天的事都做完了',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(19, FontWeight.w900, c.brandStrong),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            Text('小豬也替您開心', style: ubanText(18, FontWeight.w400, c.text2)),
          ],
        ],
      );
    } else {
      final timeStr = (next['time_str'] ?? '').toString();
      final title = (next['title'] ?? '提醒').toString();
      // ⚠️ 時間＋標題皆為動態長度（後端自訂文字）：時間用 FittedBox、標題限 2 行省略。
      right = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('下一件',
              style:
                  ubanText(18, FontWeight.w700, c.text3, letterSpacingEm: .1)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(timeStr,
                maxLines: 1,
                style: ubanBrandText(24, FontWeight.w600, c.text, height: 1.3)),
          ),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ubanText(19, FontWeight.w700, c.text, height: 1.3)),
        ],
      );
    }

    return UbanCard(
      onTap: total > 0 ? onOpenSheet : null,
      child: Row(
        children: [
          UbanProgressRing(done: done, total: total),
          const SizedBox(width: 16),
          Expanded(child: right),
          if (next != null) ...[
            const SizedBox(width: 12),
            UbanButton(
              label: '打卡',
              expand: false,
              onPressed: () => onCheckIn(next),
            ),
          ],
        ],
      ),
    );
  }
}
