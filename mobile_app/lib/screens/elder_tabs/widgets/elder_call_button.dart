import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';

/// [ElderCallButton] 的配色：對應設計稿 `.callbtn.voice`／`.video`／灰底次要鈕。
enum ElderCallButtonTone { filled, tonal, neutral }

/// 設計稿 `.callbtn`：高 64、圓角 20、圖示 26＋標籤 20/700，按下縮放＋液態暈開。
///
/// 純展示：點擊行為由呼叫端傳入（電話頁的撥打鍵仍呼叫既有 `_startCall`／`_startFriendCall`）。
/// 傳入的 [key]（新手指引的 GlobalKey）掛在整顆按鈕上。
class ElderCallButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final ElderCallButtonTone tone;

  const ElderCallButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = ElderCallButtonTone.tonal,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg, fg;
    switch (tone) {
      case ElderCallButtonTone.filled:
        bg = c.brandFill;
        fg = c.onBrand;
      case ElderCallButtonTone.tonal:
        bg = c.brandContainer;
        fg = c.brandStrong;
      case ElderCallButtonTone.neutral:
        bg = c.surface2;
        fg = c.text2;
    }
    final radius = BorderRadius.circular(20);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        enabled: enabled,
        onTap: onTap,
        child: BlobRipple(
          enabled: enabled,
          color: tone == ElderCallButtonTone.filled
              ? Colors.white.withValues(alpha: .28)
              : c.brand.withValues(alpha: .22),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: radius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 26, color: fg),
                  const SizedBox(width: 8),
                ],
                // 標籤可收縮，大字級／窄螢幕不溢位。
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: ubanText(20, FontWeight.w700, fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
