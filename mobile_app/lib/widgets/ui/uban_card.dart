import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'blob_ripple.dart';
import 'pressable_scale.dart';

/// 設計稿 `.card`：surface 底、圓角 24、padding 18、中性雙層陰影。
/// 有 [onTap] 時附按下縮放與液態暈開。
class UbanCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  const UbanCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(radius);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: br,
        boxShadow: c.shadows.card,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return PressableScale(
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        child: card,
      ),
    );
  }
}
