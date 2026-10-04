import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';

/// 新聞分類列（設計稿 `.catrow`）：膠囊鈕、高 ≥48，選中者用 text／bg 反白。
class NewsCategorySelector extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  /// 是否在面板（surface 底）中使用；false 時改為疊在綠色漸層上的玻璃膠囊。
  final bool onWhiteBackground;

  const NewsCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.onWhiteBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: categories.map((category) {
            final isSelected = selectedCategory == category;
            final Color bg = onWhiteBackground
                ? (isSelected ? c.text : c.surface2)
                : (isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18));
            final Color fg = onWhiteBackground
                ? (isSelected ? c.bg : c.text2)
                : (isSelected ? const Color(0xFF16201C) : Colors.white);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PressableScale(
                onTap: () => onCategorySelected(category),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    category,
                    style: ubanText(18, FontWeight.w700, fg),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
