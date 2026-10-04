import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 蘋果風「毛玻璃」容器（frosted / liquid glass）。
///
/// 半透明底 + 背景模糊 + 細白邊 + 柔和高光與陰影。
/// 需要放在有色彩/層次的背景之上（漸層、光暈）才透得出玻璃感。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  /// 玻璃底色（預設白玻璃）。
  final Color tint;
  final double tintOpacity;
  final double borderOpacity;
  final VoidCallback? onTap;

  /// true 時改用新設計系統（UbanColors）的玻璃底、細邊與中性陰影；
  /// 預設 false，外觀與舊版完全相同。
  final bool useUbanColors;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.blur = 18,
    this.tint = Colors.white,
    this.tintOpacity = 0.5,
    this.borderOpacity = 0.55,
    this.onTap,
    this.useUbanColors = false,
  });

  @override
  Widget build(BuildContext context) {
    final radiusObj = BorderRadius.circular(radius);
    final uc = useUbanColors ? UbanColors.of(context) : null;

    Widget glass = ClipRRect(
      borderRadius: radiusObj,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radiusObj,
            color: uc?.glass,
            gradient: uc != null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(
                          alpha: (tintOpacity + 0.12).clamp(0.0, 1.0)),
                      tint.withValues(
                          alpha: (tintOpacity - 0.08).clamp(0.0, 1.0)),
                    ],
                  ),
            border: uc != null
                ? Border.all(color: uc.glassLine, width: 1)
                : Border.all(
                    color: Colors.white.withValues(alpha: borderOpacity),
                    width: 1.5,
                  ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    Widget shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radiusObj,
        boxShadow: uc?.shadows.glass ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
      ),
      child: glass,
    );

    if (onTap == null) return shadowed;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radiusObj,
        child: shadowed,
      ),
    );
  }
}
