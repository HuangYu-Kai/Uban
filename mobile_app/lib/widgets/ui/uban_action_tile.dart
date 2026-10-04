import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'blob_ripple.dart';
import 'pressable_scale.dart';
import 'uban_text.dart';

enum UbanTone { brand, warm, info, danger }

/// 設計稿 `.action`：padding 16、圓角 22、左 52×52 圓角 16 圖示底，標題 20/900、副標 15。
class UbanActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final UbanTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  const UbanActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = UbanTone.brand,
    this.trailing,
    this.onTap,
  });

  /// 常用的尾端箭頭。
  static Widget chevron(BuildContext context) => Icon(
        Icons.chevron_right_rounded,
        size: 28,
        color: UbanColors.of(context).text3,
      );

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg, fg;
    switch (tone) {
      case UbanTone.brand:
        bg = c.brandSoft;
        fg = c.brandStrong;
      case UbanTone.warm:
        bg = c.warmContainer;
        fg = c.warm;
      case UbanTone.info:
        bg = c.infoContainer;
        fg = c.info;
      case UbanTone.danger:
        bg = c.dangerContainer;
        fg = c.danger;
    }
    final br = BorderRadius.circular(22);
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: br,
        boxShadow: c.shadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: fg),
            ),
            const SizedBox(width: 14),
            // 標題／副標可收縮，避免長輩姓名或動態文字造成溢位。
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(20, FontWeight.w900, c.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ubanText(15, FontWeight.w400, c.text2)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return tile;
    return PressableScale(
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        child: tile,
      ),
    );
  }
}
