import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/uban_motion.dart';
import 'uban_text.dart';

/// 設計稿 `.segbig`：surface2 膠囊、padding 5、按鈕高 52（small 46）、
/// thumb 以 420ms 彈性曲線滑動。傳入的 [key] 掛在整個元件上。
class UbanSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool small;

  const UbanSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final n = labels.length;
    final dur =
        reduceMotion(context) ? Duration.zero : UbanMotion.segThumbDuration;
    final h = small ? 46.0 : 52.0;
    final fs = small ? 15.0 : 18.0;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final segW = n == 0 ? 0.0 : box.maxWidth / n;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: dur,
              curve: UbanMotion.segThumb,
              left: segW * index,
              top: 0,
              bottom: 0,
              width: segW,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, .08),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: labels[i],
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) onChanged(i);
                        },
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: h),
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: ubanText(fs, FontWeight.w700,
                                    i == index ? c.brandStrong : c.text2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                child: Text(labels[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
