import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'blob_ripple.dart';
import 'pressable_scale.dart';
import 'uban_text.dart';

/// 設計稿 `.iconbtn`：52 圓、surface 底＋卡片陰影（flat：surface2、無陰影）。
class UbanIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool flat;

  const UbanIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressableScale(
        enabled: onTap != null,
        onTap: onTap,
        child: BlobRipple(
          enabled: onTap != null,
          color: c.brand.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(26),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: flat ? c.surface2 : c.surface,
              shape: BoxShape.circle,
              boxShadow: flat ? null : c.shadows.card,
            ),
            child: Icon(icon, size: 24, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// 設計稿 `.topbar`：返回鈕 + 標題 26/900 + trailing。
class UbanTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final bool showBack;
  final Widget? trailing;

  const UbanTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.showBack = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Row(
      children: [
        if (showBack) ...[
          UbanIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: '返回',
            onTap: onBack ?? () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 10),
        ],
        // 標題可收縮，避免長標題把 trailing 擠出畫面。
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ubanText(26, FontWeight.w900, c.text, height: 1.25),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}
