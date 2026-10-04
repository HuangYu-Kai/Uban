import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/uban_motion.dart';
import 'elder_overlay_button.dart';
import 'ui/uban_dialog.dart';
import 'ui/uban_text.dart';

/// 主動關懷對話框（設計稿 `#dl-heartbeat`）：徽章＋大字訊息＋「好喔，我知道了」。
///
/// 由呼叫端以 `showDialog` 顯示；[onDismiss] 的行為（關閉自己）由呼叫端決定。
class HeartbeatOverlay extends StatelessWidget {
  final String message;
  final String type; // greeting, medication, family, weather, chat
  final String emotion; // happy, caring, neutral
  final VoidCallback onDismiss;

  const HeartbeatOverlay({
    super.key,
    required this.message,
    required this.type,
    required this.emotion,
    required this.onDismiss,
  });

  /// 徽章底色／字色：依類型取設計系統色票（不再用高飽和的 accent 色）。
  (Color bg, Color fg) _badgeColors(UbanColors c) {
    switch (type) {
      case 'medication':
      case 'weather':
        return (c.warmContainer, c.warm);
      case 'family':
        return (c.infoContainer, c.info);
      default:
        return (c.brandContainer, c.brandStrong);
    }
  }

  IconData _getIcon() {
    switch (type) {
      case 'medication':
        return Icons.medication_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'weather':
        return Icons.wb_sunny_rounded;
      case 'greeting':
        return Icons.wb_twilight_rounded;
      default:
        return Icons.favorite_rounded;
    }
  }

  String _getTypeLabel() {
    switch (type) {
      case 'medication':
        return '用藥提醒';
      case 'family':
        return '家人留言';
      case 'weather':
        return '天氣注意';
      case 'greeting':
        return '溫馨問候';
      default:
        return 'AI 關懷';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final (badgeBg, badgeFg) = _badgeColors(c);

    final dialog = UbanDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getIcon(), size: 18, color: badgeFg),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _getTypeLabel(),
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(16, FontWeight.w700, badgeFg),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: ubanText(26, FontWeight.w700, c.text, height: 1.5),
          ),
          const SizedBox(height: 20),
          OverlayButton(
            label: '好喔，我知道了',
            fontSize: 22,
            minHeight: 76,
            onPressed: onDismiss,
          ),
        ],
      ),
    );

    // 設計稿 .dialog：400ms 彈性縮放 .92→1（系統「移除動畫」時不縮放）。
    if (reduceMotion(context)) return dialog;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .92, end: 1),
      duration: UbanMotion.dialogDuration,
      curve: UbanMotion.dialog,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: dialog,
    );
  }
}
