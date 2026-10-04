import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';

/// 設計稿 `.dialog`：圓角 32、左右 16、padding 22、surface 底。
class UbanDialog extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const UbanDialog({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: SingleChildScrollView(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// 以設計稿 400ms 彈性縮放（.92→1）顯示 [UbanDialog]。
Future<T?> showUbanDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) {
  final c = UbanColors.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '關閉',
    barrierColor: c.scrim,
    transitionDuration: UbanMotion.dialogDuration,
    pageBuilder: (ctx, _, __) => Center(child: UbanDialog(child: builder(ctx))),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
          parent: anim, curve: UbanMotion.dialog, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: const Interval(0, .5)),
        child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
