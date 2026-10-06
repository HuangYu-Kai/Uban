import 'package:flutter/material.dart';
import 'ui/ui.dart';

/// 年齡輸入元件：用「-／+」加減按鈕取代純數字鍵盤輸入。
///
/// ★ 第五十三輪 onboard53：長輩端／家屬端「年齡與居住地改為必填」共用元件。
///
/// 選擇 Stepper（加減按鈕）而非純文字輸入框，是刻意的設計決定：
/// - 長輩端：打字輸入數字容易誤觸、打錯，加減按鈕點擊區大、操作直覺。
/// - 兩端共用：範圍固定在 1～120（與後端 `services/taiwan_regions.py::is_valid_age`
///   / `taiwan_regions.py` 的合理範圍檢查一致），Stepper 天生就不會產生超出
///   範圍或非數字的髒值，省去前端另外寫數字格式檢查。
///
/// [elderMode] 為 true 時套用長輩尺規（按鈕 72、字級 ≥18）；為 false 時走設計稿
/// `.stepper`（58 圓按鈕＋58 高數值框）。外觀走 [UbanColors]，參數與回傳不變。
class AgeStepperField extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  final bool elderMode;
  final String label;
  static const int minAge = 1;
  static const int maxAge = 120;
  /// 未選擇時，加減按鈕的起始值（點「+」第一下會從這個值開始累加）。
  static const int defaultStartAge = 65;

  const AgeStepperField({
    super.key,
    required this.value,
    required this.onChanged,
    this.elderMode = false,
    this.label = '年齡',
  });

  void _step(int delta) {
    // ★ 2026-10-06：尚未選擇時，第一次點「＋」直接落在起始值（不再 +1 變成 66）。
    if (value == null) {
      onChanged(defaultStartAge);
      return;
    }
    final current = value!;
    final next = (current + delta).clamp(minAge, maxAge);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final displayText = value == null ? '請選擇' : '$value 歲';
    final double buttonSize = elderMode ? 72 : 58;
    final TextStyle labelStyle = ubanText(
        elderMode ? 18 : 15, FontWeight.w700, c.text2);
    final TextStyle valueStyle = ubanText(
        elderMode ? 32 : 26, FontWeight.w600, value == null ? c.text3 : c.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
        const SizedBox(height: 6),
        Row(
          children: [
            _StepButton(
              glyph: '−',
              semantics: '減一歲',
              size: buttonSize,
              onTap: value == null || value! <= minAge ? null : () => _step(-1),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: buttonSize,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.line, width: 1.5),
                ),
                // 數值是展示文字，用 FittedBox 縮放而非省略。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(displayText,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: valueStyle),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StepButton(
              glyph: '+',
              semantics: '加一歲',
              size: buttonSize,
              onTap: value != null && value! >= maxAge ? null : () => _step(1),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final String glyph;
  final String semantics;
  final double size;
  final VoidCallback? onTap;

  const _StepButton({
    required this.glyph,
    required this.semantics,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantics,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : .4,
        child: PressableScale(
          enabled: enabled,
          onTap: onTap,
          child: BlobRipple(
            enabled: enabled,
            color: c.brand.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(size / 2),
            child: Container(
              width: size,
              height: size,
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
