import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';

/// 設計稿 `.switch`：60×36、圓點 28、選中 brandFill、圓點 380ms springBack。
class UbanSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const UbanSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final dur =
        reduceMotion(context) ? Duration.zero : UbanMotion.switchDuration;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Opacity(
          opacity: onChanged == null ? .5 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 60,
            height: 36,
            decoration: BoxDecoration(
              color: value ? c.brandFill : c.surface3,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: dur,
                  curve: UbanMotion.springBack,
                  top: 4,
                  left: value ? 28 : 4,
                  width: 28,
                  height: 28,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, .2),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
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
