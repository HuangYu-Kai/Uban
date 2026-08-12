// lib/widgets/call_retry_dialog.dart
import 'package:flutter/material.dart';

/// 使用者在「無人接聽／連線逾時」對話框上的選擇。
enum CallRetryChoice {
  /// 離開通話房間，回到主畫面。
  leave,

  /// 重新撥打（重新送出一次通話封包），留在原畫面繼續等待。
  retry,
}

/// ★ 2026-08-12 第二十三輪（需求 3）：LINE 式「無人接聽／連線逾時」對話框。
///
/// 取代原本 `VideoCallScreen` 內嵌的失敗畫面（紅色 `Icons.wifi_off` ＋「重試連線」按鈕）。
/// 舊介面有兩個問題：
///   1. 它只存在於**家屬端**的 `VideoCallScreen`，長輩端 `ElderScreen` 逾時只把
///      狀態字串改成「對方未接聽」就返回，兩端行為不一致。
///   2. 那顆「重試連線」按鈕呼叫的是 `_initCall()`——會**整個重跑**媒體初始化與
///      Socket 連線流程，而不是「重新撥打」；重複 `openUserMedia` 在真機上常
///      造成鏡頭被佔用而黑畫面。
///
/// 本對話框只負責「問」，實際的離開／重撥動作由呼叫端決定，因此兩端可以
/// 共用同一個 UI 而各自走自己正確的導航與重撥路徑。
///
/// ⚠️ 護欄 G23 仍然適用：**不可改用 `SnackBar`**。呼叫端在使用者選擇「離開」後
/// 幾乎都會接 `pushAndRemoveUntil`，SnackBar 會隨 route 一起被移除而看不到。
///
/// [largeText] 供長輩端使用（字級與按鈕加大）。
Future<CallRetryChoice?> showCallRetryDialog(
  BuildContext context, {
  String title = '對方沒有接聽',
  String message = '要離開通話房間，還是重新撥打一次？',
  bool largeText = false,
}) {
  final double titleSize = largeText ? 26 : 20;
  final double bodySize = largeText ? 22 : 16;
  final double buttonSize = largeText ? 22 : 17;
  final EdgeInsets buttonPadding = largeText
      ? const EdgeInsets.symmetric(vertical: 16)
      : const EdgeInsets.symmetric(vertical: 12);

  return showDialog<CallRetryChoice>(
    context: context,
    // 這是一個必須做出選擇的分岔點：點外框或按返回鍵都不應該讓使用者
    // 卡在一個已經斷線的通話畫面上。
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.phone_missed, color: Colors.redAccent, size: titleSize + 6),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: bodySize, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(CallRetryChoice.leave),
                  icon: Icon(Icons.close, size: buttonSize + 2),
                  label: Text(
                    '離開通話',
                    style: TextStyle(fontSize: buttonSize),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: buttonPadding,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(CallRetryChoice.retry),
                  icon: Icon(Icons.refresh, size: buttonSize + 2),
                  label: Text(
                    '重新撥打',
                    style: TextStyle(fontSize: buttonSize),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: buttonPadding,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
