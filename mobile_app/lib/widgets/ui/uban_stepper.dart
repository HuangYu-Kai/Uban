import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'blob_ripple.dart';
import 'pressable_scale.dart';
import 'uban_text.dart';

/// 設計稿 `.stepper`：中間數值框（高 58、圓角 18、Poppins 26）＋左右 58 圓形 tonal 加減鈕。
class UbanStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  const UbanStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final canDec = value - step >= min;
    final canInc = value + step <= max;
    return Row(
      children: [
        _RoundBtn(
          glyph: '−',
          semantics: '減少',
          onTap: canDec ? () => onChanged(value - step) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 58,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$value',
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: ubanBrandText(26, FontWeight.w600, c.text)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _RoundBtn(
          glyph: '+',
          semantics: '增加',
          onTap: canInc ? () => onChanged(value + step) : null,
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final String glyph;
  final String semantics;
  final VoidCallback? onTap;

  const _RoundBtn(
      {required this.glyph, required this.semantics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .4 : 1,
        child: PressableScale(
          enabled: onTap != null,
          onTap: onTap,
          child: BlobRipple(
            enabled: onTap != null,
            color: c.brand.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(29),
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: c.brandContainer, shape: BoxShape.circle),
              child: Text(glyph,
                  textScaler: TextScaler.noScaling,
                  style: ubanText(28, FontWeight.w700, c.brandStrong,
                      height: 1.1)),
            ),
          ),
        ),
      ),
    );
  }
}
