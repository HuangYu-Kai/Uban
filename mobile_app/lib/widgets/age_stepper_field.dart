import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

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
/// [elderMode] 為 true 時套用 [ElderScale]（大字體、大按鈕，`ElderScale.buttonHeight`
/// = 84），符合長輩端 UI 尺規要求；為 false 時走一般家屬端尺寸。
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
    final current = value ?? defaultStartAge;
    final next = (current + delta).clamp(minAge, maxAge);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final displayText = value == null ? '請選擇' : '$value 歲';
    final double buttonSize = elderMode ? ElderScale.buttonHeight : 52;
    final double iconSize = elderMode ? ElderScale.buttonIcon : 24;
    final TextStyle labelStyle = elderMode
        ? ElderScale.body
        : GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    final TextStyle valueStyle = elderMode
        ? ElderScale.sectionTitle
        : GoogleFonts.notoSansTc(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        SizedBox(height: elderMode ? 12 : 8),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              size: buttonSize,
              iconSize: iconSize,
              onTap: value == null || value! <= minAge ? null : () => _step(-1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: buttonSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child: FittedBox(
                  child: Text(displayText, style: valueStyle),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StepButton(
              icon: Icons.add_rounded,
              size: buttonSize,
              iconSize: iconSize,
              onTap: value != null && value! >= maxAge ? null : () => _step(1),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  const _StepButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.primary : AppColors.border,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}
