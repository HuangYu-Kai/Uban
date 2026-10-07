import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';
import 'uban_text.dart';

class UbanNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// 掛在該項的 GestureDetector 上（外部教學／spotlight 用的 GlobalKey）。
  final Key? key;

  /// ★ 2026-10-07 每日一問改留聊天：true 時在圖示右上角畫小紅點，
  /// 無障礙標籤改為「$label，$badgeLabel」。
  final bool showBadge;
  final String badgeLabel;

  const UbanNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.key,
    this.showBadge = false,
    this.badgeLabel = '',
  });
}

/// 設計稿懸浮玻璃導覽列（`.navwrap` / `.nav`）。
///
/// 放在 Stack 底部（例如 `Align(alignment: Alignment.bottomCenter)`）。
/// 指示器位置以 SpringSimulation(navSpring) 驅動，移動中依速度拉伸。
class UbanGlassNavBar extends StatefulWidget {
  final List<UbanNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const UbanGlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 80;
  static const double bottomGap = 18;

  /// 導覽列佔用高度（含底部 18，不含系統安全區）；分頁底部留白以此加安全區計算。
  static const double totalHeight = barHeight + bottomGap;

  @override
  State<UbanGlassNavBar> createState() => _UbanGlassNavBarState();
}

class _UbanGlassNavBarState extends State<UbanGlassNavBar>
    with TickerProviderStateMixin {
  static const double _indW = 58;
  static const double _hPad = 6;

  // 以「項目索引」為單位的指示器位置（寬度改變時不用重算動畫）。
  late final AnimationController _pos;
  late final AnimationController _pop;
  int _popIndex = -1;

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(
        vsync: this, value: widget.currentIndex.toDouble());
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
  }

  @override
  void didUpdateWidget(covariant UbanGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _popIndex = widget.currentIndex;
      if (reduceMotion(context)) {
        _pos.value = widget.currentIndex.toDouble();
      } else {
        _pos.animateWith(SpringSimulation(
          UbanMotion.navSpring,
          _pos.value,
          widget.currentIndex.toDouble(),
          _pos.velocity,
        ));
        _pop.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    _pop.dispose();
    super.dispose();
  }

  double _popScale(int i) {
    if (i != _popIndex) return 1;
    final t = _pop.value;
    return t < .4
        ? 1 + .14 * Curves.easeOut.transform(t / .4)
        : 1.14 - .14 * Curves.easeInOut.transform((t - .4) / .6);
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final n = widget.items.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(999);

    // 固定高度的元件：字級放大時限制 label，避免溢位。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            14, 0, 14, UbanGlassNavBar.bottomGap + bottomInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: c.shadows.glass,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: UbanGlassNavBar.barHeight,
                padding: const EdgeInsets.symmetric(horizontal: _hPad),
                decoration: BoxDecoration(
                  color: c.glass,
                  borderRadius: radius,
                  border: Border.all(color: c.glassLine, width: 1),
                ),
                child: LayoutBuilder(builder: (context, box) {
                  final itemW = n == 0 ? 0.0 : box.maxWidth / n;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedBuilder(
                        animation: _pos,
                        builder: (context, _) {
                          final x = _pos.value * itemW + itemW / 2 - _indW / 2;
                          final stretch = (_pos.velocity.abs() * itemW * 0.045)
                              .clamp(0.0, 30.0);
                          return Positioned(
                            left: x - stretch / 2,
                            top: 9,
                            width: _indW + stretch,
                            height: 38,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.brandContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < n; i++)
                            Expanded(child: _buildItem(c, i)),
                        ],
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(UbanColors c, int i) {
    final item = widget.items[i];
    final selected = i == widget.currentIndex;
    final color = selected ? c.brandStrong : c.text2;
    return GestureDetector(
      key: item.key,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap(i);
      },
      child: Semantics(
        button: true,
        selected: selected,
        label: item.showBadge && item.badgeLabel.isNotEmpty
            ? '${item.label}，${item.badgeLabel}'
            : item.label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: AnimatedBuilder(
                        animation: _pop,
                        builder: (context, child) =>
                            Transform.scale(scale: _popScale(i), child: child),
                        child: Icon(selected ? item.selectedIcon : item.icon,
                            size: 27, color: color),
                      ),
                    ),
                    // ★ 2026-10-07 每日一問改留聊天：小紅點（12px，疊在圖示右上，
                    // 不佔版面、不吃點擊，不會造成溢位）。
                    if (item.showBadge)
                      Positioned(
                        top: 3,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('nav_badge_dot'),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              shape: BoxShape.circle,
                              border: Border.all(color: c.glass, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(
                    15,
                    selected ? FontWeight.w900 : FontWeight.w500,
                    color,
                    letterSpacingEm: .04,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
