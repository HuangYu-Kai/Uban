import 'package:flutter/material.dart';

class NewsCategorySelector extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  /// 是否在白色面板中使用（深色文字模式）
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: categories.map((category) {
            final isSelected = selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onCategorySelected(category),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: onWhiteBackground
                        ? (isSelected
                            ? const Color(0xFF1E293B)
                            : Colors.white)
                        : (isSelected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: onWhiteBackground
                          ? (isSelected
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE5E7EB))
                          : (isSelected
                              ? const Color(0xFFFFD700)
                              : Colors.white.withValues(alpha: 0.2)),
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: onWhiteBackground
                                  ? const Color(0xFF1E293B)
                                      .withValues(alpha: 0.15)
                                  : const Color(0xFFFFD700)
                                      .withValues(alpha: 0.25),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: onWhiteBackground
                          ? (isSelected
                              ? Colors.white
                              : const Color(0xFF6B7280))
                          : (isSelected
                              ? const Color(0xFF1E293B)
                              : Colors.white.withValues(alpha: 0.9)),
                      fontSize: 17,
                      fontWeight:
                          isSelected ? FontWeight.w900 : FontWeight.w500,
                    ),
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
