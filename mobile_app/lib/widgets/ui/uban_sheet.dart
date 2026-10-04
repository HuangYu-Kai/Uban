import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';

/// 設計稿 `.sheet`：左右下 inset 8、圓角 32、grab 44×5、最高 86%、450ms 彈性升起。
Future<T?> showUbanSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool isDismissible = true,
  bool useRootNavigator = true,
}) {
  final c = UbanColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: c.scrim,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    sheetAnimationStyle: AnimationStyle(
      curve: UbanMotion.sheet,
      duration: UbanMotion.sheetDuration,
      reverseCurve: Curves.easeInCubic,
      reverseDuration: const Duration(milliseconds: 250),
    ),
    builder: (ctx) => UbanSheet(child: builder(ctx)),
  );
}

/// [showUbanSheet] 使用的面板外觀（也可單獨使用）。
class UbanSheet extends StatelessWidget {
  final Widget child;

  const UbanSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final mq = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * .86),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.surface3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // 內容過長時在面板內捲動（最高 86%）。
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
