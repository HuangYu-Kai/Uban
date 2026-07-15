import 'dart:ui';
import 'package:flutter/material.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final radiusObj = BorderRadius.circular(radius);

    Widget glass = ClipRRect(
      borderRadius: radiusObj,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radiusObj,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: (tintOpacity + 0.12).clamp(0.0, 1.0)),
                tint.withValues(alpha: (tintOpacity - 0.08).clamp(0.0, 1.0)),
              ],
            ),
            border: Border.all(
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
        boxShadow: [
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
