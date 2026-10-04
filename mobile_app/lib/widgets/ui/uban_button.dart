import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'blob_ripple.dart';
import 'pressable_scale.dart';
import 'uban_text.dart';

enum UbanButtonVariant { filled, tonal, outline, ghost, danger, line }

enum UbanButtonSize { normal, xl }

/// 設計稿 `.btn`：膠囊、最小高 60（xl 76、ghost 48）、按下縮放＋液態暈開。
///
/// [onPressed] 為 null 或 [loading] 時視為停用。預設撐滿父層寬度
/// （[expand]=true）；放進不限寬的 Row 時請設 `expand: false`。
class UbanButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final UbanButtonVariant variant;
  final UbanButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const UbanButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = UbanButtonVariant.filled,
    this.size = UbanButtonSize.normal,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final v = variant;
    final ghost = v == UbanButtonVariant.ghost;
    final xl = size == UbanButtonSize.xl && !ghost;

    final double minH = ghost ? 48 : (xl ? 76 : 60);
    final double fontSize = ghost ? 16 : (xl ? 22 : 19);

    final Color bg;
    final Color fg;
    switch (v) {
      case UbanButtonVariant.filled:
        bg = c.brandFill;
        fg = c.onBrand;
      case UbanButtonVariant.tonal:
        bg = c.brandContainer;
        fg = c.brandStrong;
      case UbanButtonVariant.outline:
        bg = Colors.transparent;
        fg = c.text;
      case UbanButtonVariant.ghost:
        bg = Colors.transparent;
        fg = c.brandStrong;
      case UbanButtonVariant.danger:
        bg = c.danger;
        fg = Colors.white;
      case UbanButtonVariant.line:
        bg = c.lineGreen;
        fg = Colors.white;
    }
    final blobColor = (v == UbanButtonVariant.filled ||
            v == UbanButtonVariant.danger ||
            v == UbanButtonVariant.line)
        ? Colors.white.withValues(alpha: .28)
        : c.brand.withValues(alpha: .22);

    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(999);

    final Widget content = loading
        ? SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 24, color: fg),
                const SizedBox(width: 10),
              ],
              // 文字可收縮＋省略，避免長標籤或大字級造成 RenderFlex 溢位。
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ubanText(fontSize, FontWeight.w700, fg,
                      letterSpacingEm: .04),
                ),
              ),
            ],
          );

    final body = Container(
      constraints: BoxConstraints(minHeight: minH),
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: v == UbanButtonVariant.outline
            ? Border.all(color: c.line, width: 2)
            : null,
      ),
      child: content,
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
            color: blobColor,
            borderRadius: radius,
            child: body,
          ),
        ),
      ),
    );
  }
}
