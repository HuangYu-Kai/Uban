import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/ui/blob_ripple.dart';
import '../../../widgets/ui/pressable_scale.dart';
import '../../widgets/friend_avatar.dart';
import 'fam_ui.dart';

/// 家屬端「互動」分頁、AI 照護秘書、好友頁共用的新設計元件
/// （對應 design_prototype/family.css 的 `.callbig`／`.action`／`.devrow`／
/// `.quota`／`.tier`／`.cbub`／`.sched`／`.input`／`.roundbtn`）。
///
/// 與 [fam_ui.dart] 一樣全部以 [UbanColors.of] 取色；原則：少用小圖示、
/// 暖色只用於「待處理」、不帶色光暈與漸層。

/// `.callbig`：通話大卡。[filled] 為 brandFill（視訊），否則 brandContainer（語音）。
/// 高度由內容決定、至少 96；放在 [IntrinsicHeight] 內的 Row 可兩張等高。
class FamCallBig extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const FamCallBig({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final bg = filled ? c.brandFill : c.brandContainer;
    final fg = filled ? c.onBrand : c.brandStrong;
    final br = BorderRadius.circular(22);
    return PressableScale(
      onTap: onTap,
      child: BlobRipple(
        color: (filled ? Colors.white : c.brand).withValues(alpha: .26),
        borderRadius: br,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bg, borderRadius: br),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 28, color: fg),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: famText(fg, 17, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: famText(fg.withValues(alpha: .85), 12.5, height: 1.35),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.action`：整列可點的入口列（無前置圖示）。標題 16.5／700、副標 13.5。
///
/// [flat] 為 true 時用 surface2 底、無陰影（放在 sheet 內）；否則 surface 底＋卡片陰影。
class FamAction extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool flat;

  const FamAction({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.flat = false,
  });

  /// 尾端的導覽箭頭（text3）。
  static Widget chevron(BuildContext context) => Icon(
        Icons.chevron_right_rounded,
        size: 24,
        color: UbanColors.of(context).text3,
      );

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(20);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: flat ? c.surface2 : c.surface,
        borderRadius: br,
        boxShadow: flat ? null : c.shadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: famText(titleColor ?? c.text, 16.5,
                        weight: FontWeight.w700),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: famText(c.text2, 13.5, height: 1.45),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return body;
    return PressableScale(
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        child: body,
      ),
    );
  }
}

/// `.devrow`：色點｜標題＋副標｜右側元件。[first] 為 true 時不畫上分隔線。
/// [highlight] 有值時整列以該色為底（警報／長輩在此）。
class FamDevRow extends StatelessWidget {
  final Color dot;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool first;
  final Color? highlight;
  final Color? titleColor;
  final Color? subtitleColor;
  final FontWeight subtitleWeight;
  final int subtitleMaxLines;

  const FamDevRow({
    super.key,
    required this.dot,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.first = false,
    this.highlight,
    this.titleColor,
    this.subtitleColor,
    this.subtitleWeight = FontWeight.w500,
    this.subtitleMaxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final row = Row(
      children: [
        FamDot(color: dot),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: famText(titleColor ?? c.text, 15.5,
                    weight: FontWeight.w700),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: famText(subtitleColor ?? c.text2, 12.5,
                      weight: subtitleWeight, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
    if (highlight != null) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: row,
    );
  }
}

/// `.smallbtn`：38 高的膠囊小按鈕（可收縮）。[filled] 為 brandFill，否則 brandContainer。
/// [onTap] 為 null 時變淡。
class FamSmallBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool danger;

  const FamSmallBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg;
    final Color fg;
    if (danger) {
      bg = c.dangerContainer;
      fg = c.danger;
    } else if (filled) {
      bg = c.brandFill;
      fg = c.onBrand;
    } else {
      bg = c.brandContainer;
      fg = c.brandStrong;
    }
    final enabled = onTap != null;
    final br = BorderRadius.circular(999);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: PressableScale(
        enabled: enabled,
        onTap: onTap,
        child: BlobRipple(
          color: (filled && !danger ? Colors.white : fg).withValues(alpha: .24),
          borderRadius: br,
          enabled: enabled,
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: br),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(fg, 14, weight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.meter`：8 高的進度條（surface3 軌、[color] 填色）。[value] 為 0～1。
class FamMeter extends StatelessWidget {
  final double value;
  final Color? color;
  const FamMeter({super.key, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.surface3)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: ColoredBox(color: color ?? c.brand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.quota`：標籤｜進度條｜右側按鈕。
class FamQuota extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final Widget? trailing;
  const FamQuota({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Row(
      children: [
        Text(label, style: famText(c.text2, 13, tabular: true)),
        const SizedBox(width: 10),
        Expanded(child: FamMeter(value: value, color: color)),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}

/// `.fam .tier`：中性（surface2 底、text2 字）的層級徽章；[onTap] 有值時可點。
class FamTier extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const FamTier({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: famText(c.text2, 12, weight: FontWeight.w700),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}

/// `.cbub`：對話泡泡。[mine] 為 true 靠右、brandContainer；否則靠左、surface＋卡片陰影。
/// 最寬 88%（[maxWidthFactor]）。
class FamChatBubble extends StatelessWidget {
  final bool mine;
  final Widget child;
  final double maxWidthFactor;
  const FamChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.maxWidthFactor = .88,
  });

  /// 泡泡內文樣式。
  static TextStyle textStyle(BuildContext context, {required bool mine}) {
    final c = UbanColors.of(context);
    return famText(mine ? c.brandStrong : c.text, 15, height: 1.6);
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * maxWidthFactor),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: mine ? c.brandContainer : c.surface,
              boxShadow: mine ? null : c.shadows.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 6),
                bottomRight: Radius.circular(mine ? 6 : 20),
              ),
            ),
            child: child,
          ),
        ),
      );
    });
  }
}

/// `.sched`：泡泡內的排程確認列（surface2 底、圓角 14）。
class FamSched extends StatelessWidget {
  final String time;
  final String title;
  final String? meta;
  final bool first;
  const FamSched({
    super.key,
    required this.time,
    required this.title,
    this.meta,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: first ? 10 : 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: time,
                style: famText(c.text, 15, weight: FontWeight.w700, tabular: true),
              ),
              if (meta != null)
                TextSpan(
                  text: '  $meta',
                  style: famText(c.text2, 13.5),
                ),
            ]),
          ),
          const SizedBox(height: 2),
          Text(title, style: famText(c.text2, 13.5, height: 1.4)),
        ],
      ),
    );
  }
}

/// `.input`：單行／多行輸入框（surface 底、1.5px line 邊框、focus 時 brand 邊框）。
/// [height] 是最小高度（`.msgbox` 48、`.cbar` 50）；[radius] 預設 16（`.cbar` 傳 999）。
class FamInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final double height;
  final double radius;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final Color? fillColor;

  const FamInput({
    super.key,
    this.controller,
    this.hintText,
    this.height = 48,
    this.radius = 16,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.style,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textAlign: textAlign,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: c.brand,
      style: style ?? famText(c.text, 15, height: 1.4),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: famText(c.text3, 15, height: 1.4),
        counterText: '',
        filled: true,
        fillColor: fillColor ?? c.surface,
        constraints: BoxConstraints(minHeight: height),
        contentPadding: EdgeInsets.symmetric(
          horizontal: radius >= 40 ? 20 : 16,
          vertical: 12,
        ),
        border: border(c.line),
        enabledBorder: border(c.line),
        focusedBorder: border(c.brand),
        disabledBorder: border(c.line),
      ),
    );
  }
}

/// `.roundbtn`：圓形圖示鈕（預設 brandFill 底）。[onTap] 為 null 時變淡。
class FamRoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final Color? background;
  final Color? foreground;
  const FamRoundBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final fg = foreground ?? c.onBrand;
    return Opacity(
      opacity: onTap == null ? .45 : 1,
      child: Tooltip(
        message: tooltip,
        child: PressableScale(
          enabled: onTap != null,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background ?? c.brandFill,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 家屬端統一的 SnackBar：浮動、圓角 14；[error] 用 danger 底、[success] 用 brandFill 底，
/// 兩者皆無則用中性深色底。
SnackBar famSnackBar(
  BuildContext context,
  String message, {
  bool error = false,
  bool success = false,
}) {
  final c = UbanColors.of(context);
  final Color bg;
  final Color fg;
  if (error) {
    bg = c.danger;
    fg = Colors.white;
  } else if (success) {
    bg = c.brandFill;
    fg = c.onBrand;
  } else {
    bg = c.text;
    fg = c.bg;
  }
  return SnackBar(
    content: Text(message, style: famText(fg, 14.5, weight: FontWeight.w600)),
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

/// 對話框／面板標題（19／900）。
Text famDialogTitle(UbanColors c, String text) =>
    Text(text, style: famText(c.text, 19, weight: FontWeight.w900, height: 1.3));

/// 好友頭像：有網址就顯示圖片，沒有網址或載入失敗退回姓名首字（[FamAvatar]）。
/// 網址解析沿用 [FriendAvatar.resolveUrl]（相對路徑補 serverRootUrl）。
class FamFriendAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  const FamFriendAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final fallback = FamAvatar(name: name.isEmpty ? '友' : name, size: size);
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          FriendAvatar.resolveUrl(url),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
