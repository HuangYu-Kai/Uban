import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui/blob_ripple.dart';
import 'ui/pressable_scale.dart';
import 'ui/uban_text.dart';

/// 長輩端浮層（教學卡、用藥提醒、通話重撥）共用的膠囊按鈕。
///
/// 外觀同設計稿 `.btn`（filled／outline）：最小高 60、按下縮放＋液態暈開。
/// 與 `UbanButton` 的差別只有「左右 padding 10」——浮層裡常有 2:3 的並排按鈕，
/// 360 寬螢幕上 `UbanButton` 的 18 padding 會讓四個字的標籤被迫折成兩行。
/// 標籤可收縮（最多兩行），大字級下不會溢位。
class OverlayButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final double fontSize;
  final double minHeight;
  final bool loading;

  const OverlayButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
    this.fontSize = 19,
    this.minHeight = 60,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg = filled ? c.brandFill : Colors.transparent;
    final Color fg = filled ? c.onBrand : c.text;
    final radius = BorderRadius.circular(999);
    final enabled = onPressed != null && !loading;

    final body = Container(
      constraints: BoxConstraints(minHeight: minHeight < 60 ? 60 : minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: filled ? null : Border.all(color: c.line, width: 2),
      ),
      child: loading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
            )
          : Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ubanText(fontSize, FontWeight.w700, fg,
                  letterSpacingEm: .02),
            ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: (onPressed == null && !loading) ? .5 : 1,
        child: PressableScale(
          enabled: enabled,
          onTap: onPressed,
          child: BlobRipple(
            enabled: enabled,
            color: filled
                ? Colors.white.withValues(alpha: .28)
                : c.brand.withValues(alpha: .22),
            borderRadius: radius,
            child: body,
          ),
        ),
      ),
    );
  }
}
