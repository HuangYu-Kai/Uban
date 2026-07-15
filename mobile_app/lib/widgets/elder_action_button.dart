import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 適老化「大按鈕」—— 全寬、超大點擊區、圖示 + 大字，長輩一看就懂。
///
/// 用於長輩端主要動作（打電話給家人、和小雲聊天、唸給我聽…）。
/// 主色底白字（primary），或淡底彩字（filled=false）兩種樣式。
class ElderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 主色（預設品牌 teal）。
  final Color color;

  /// true = 實心（彩底白字，主要動作）；false = 淡底彩字（次要動作）。
  final bool filled;

  const ElderActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = filled ? Colors.white : color;
    final Color bg = filled ? color : color.withValues(alpha: 0.12);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(ElderScale.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ElderScale.cardRadius),
        child: Container(
          height: ElderScale.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ElderScale.cardRadius),
            border: filled
                ? null
                : Border.all(color: color.withValues(alpha: 0.35), width: 2),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: ElderScale.buttonIcon, color: fg),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElderScale.button.copyWith(color: fg),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 34, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
