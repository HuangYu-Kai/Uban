import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/ui/blob_ripple.dart';
import '../../../widgets/ui/pressable_scale.dart';

/// 家屬端新設計的共用小元件（對應 design_prototype/family.css）。
///
/// 全部以 [UbanColors.of] 取色——掛在 `FamilyTheme` 之下就是海灣藍色票。
/// 原則：少用小圖示、不帶色光暈、暖色只用於「待處理」。

const String _kFont = 'NotoSansTC';

/// 家屬端文字樣式（NotoSansTC 本地字型；[tabular] 讓數字等寬）。
TextStyle famText(
  Color color,
  double size, {
  FontWeight weight = FontWeight.w500,
  double? height,
  double letterSpacing = 0,
  bool tabular = false,
}) =>
    TextStyle(
      fontFamily: _kFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

enum FamTone { neutral, brand, warm, info, danger }

Color famToneFg(UbanColors c, FamTone t) {
  switch (t) {
    case FamTone.brand:
      return c.brandStrong;
    case FamTone.warm:
      return c.warm;
    case FamTone.info:
      return c.info;
    case FamTone.danger:
      return c.danger;
    case FamTone.neutral:
      return c.text2;
  }
}

Color famToneBg(UbanColors c, FamTone t) {
  switch (t) {
    case FamTone.brand:
      return c.brandContainer;
    case FamTone.warm:
      return c.warmContainer;
    case FamTone.info:
      return c.infoContainer;
    case FamTone.danger:
      return c.dangerContainer;
    case FamTone.neutral:
      return c.surface2;
  }
}

/// `.sev`：10px 色點（取代小圖示表達嚴重度／狀態）。
class FamDot extends StatelessWidget {
  final Color color;
  final double size;
  const FamDot({super.key, required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// `.card`：surface 底、圓角 24、padding 16、中性雙層陰影；有 [onTap] 時附按下縮放。
/// [clip] 為 true 時內容以圓角裁切（`.gpscard`）。
class FamCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool clip;
  final Color? color;

  const FamCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.clip = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(24);
    Widget inner = Padding(padding: padding, child: child);
    if (clip) inner = ClipRRect(borderRadius: br, child: inner);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: br,
        boxShadow: c.shadows.card,
      ),
      child: inner,
    );
    if (onTap == null) return card;
    return PressableScale(
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        child: card,
      ),
    );
  }
}

/// `.sec-head`：標題（可收縮）＋右側元件。標題 18px／900。
class FamSecHead extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const FamSecHead({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 標題同列有徽章／按鈕時要可收縮（鐵律 #14）。
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text, 18, weight: FontWeight.w900),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// `.more`：區段右上的文字按鈕。
class FamMore extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const FamMore({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: famText(c.brandStrong, 14, weight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// `.fsec`：區段小標（灰、字距）。
class FamSectionLabel extends StatelessWidget {
  final String text;
  const FamSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Text(
        text,
        style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.3),
      ),
    );
  }
}

/// `.avatar`：以名字首字當頭像（不放照片、不放表情）。
class FamAvatar extends StatelessWidget {
  final String name;
  final double size;
  final FamTone tone;
  const FamAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.tone = FamTone.brand,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: famToneBg(c, tone),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: famText(famToneFg(c, tone), size * .42, weight: FontWeight.w900),
      ),
    );
  }
}

/// `.minichip`：小標籤（可帶前置色點）。
class FamChip extends StatelessWidget {
  final String label;
  final FamTone tone;
  final bool dot;
  const FamChip({super.key, required this.label, this.tone = FamTone.neutral, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final fg = famToneFg(c, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: famToneBg(c, tone),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[FamDot(color: fg, size: 8), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(fg, 12.5, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

enum FamButtonKind { filled, tonal, danger, ghost, outline }

/// `.smallbtn`／`.btn`：膠囊按鈕（高 [height]）。
class FamButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FamButtonKind kind;
  final double height;
  final bool expand;
  final bool loading;

  const FamButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = FamButtonKind.filled,
    this.height = 46,
    this.expand = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg;
    final Color fg;
    switch (kind) {
      case FamButtonKind.filled:
        bg = c.brandFill;
        fg = c.onBrand;
      case FamButtonKind.tonal:
        bg = c.brandContainer;
        fg = c.brandStrong;
      case FamButtonKind.danger:
        bg = c.danger;
        fg = Colors.white;
      case FamButtonKind.ghost:
        bg = Colors.transparent;
        fg = c.brandStrong;
      case FamButtonKind.outline:
        bg = Colors.transparent;
        fg = c.brandStrong;
    }
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(999);
    final blob = (kind == FamButtonKind.filled || kind == FamButtonKind.danger)
        ? Colors.white.withValues(alpha: .28)
        : c.brand.withValues(alpha: .22);

    final text = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: famText(fg, 15.5, weight: FontWeight.w700, letterSpacing: .3),
      ),
    );

    final body = Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: kind == FamButtonKind.outline
            ? Border.all(color: c.line, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
            const SizedBox(width: 8),
          ],
          text,
        ],
      ),
    );

    return Opacity(
      opacity: onPressed == null ? .45 : 1,
      child: PressableScale(
        enabled: enabled,
        onTap: onPressed,
        child: BlobRipple(
          color: blob,
          borderRadius: radius,
          enabled: enabled,
          child: body,
        ),
      ),
    );
  }
}

/// `.stat`：小標＋數值（surface2 底、圓角 16）。
class FamStat extends StatelessWidget {
  final String label;
  final String value;
  const FamStat({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text2, 12)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text, 16, weight: FontWeight.w900, tabular: true)),
        ],
      ),
    );
  }
}

/// `.kv3` 的單格：小標＋大數字＋單位。
class FamKv extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const FamKv({super.key, required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text2, 12)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: value,
                style: famText(c.text, 20, weight: FontWeight.w700, tabular: true)),
            if (unit != null)
              TextSpan(
                  text: ' $unit',
                  style: famText(c.text2, 12, weight: FontWeight.w700)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// `.alarm` 的一顆按鈕。
class FamAlarmAction {
  final String label;
  final VoidCallback onPressed;
  const FamAlarmAction(this.label, this.onPressed);
}

/// `.alarm`：從底部升起的警報面板（danger 警示塊、資訊列、按鈕直排）。
///
/// 純外觀：按鈕集合與 callback 由呼叫端決定。[primary] 依序排在上面
/// （第一顆 danger、其餘 tonal），[dismiss] 固定排最後（ghost）。
class FamAlarmSheet extends StatelessWidget {
  final String title;
  final String? whenText;
  final String description;
  final List<String> detailLines;
  final List<FamAlarmAction> primary;
  final FamAlarmAction dismiss;

  const FamAlarmSheet({
    super.key,
    required this.title,
    this.whenText,
    required this.description,
    this.detailLines = const [],
    this.primary = const [],
    required this.dismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final mq = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 30 * (1 - t)), child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mq.size.height * .9),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(32),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: c.danger,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: famText(c.danger, 22, weight: FontWeight.w900),
                              ),
                              if (whenText != null)
                                Text(whenText!,
                                    style: famText(c.text2, 13,
                                        weight: FontWeight.w600, tabular: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(description,
                        style: famText(c.text, 15.5, height: 1.6)),
                    if (detailLines.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < detailLines.length; i++) ...[
                              if (i > 0) const SizedBox(height: 4),
                              Text(detailLines[i],
                                  style: famText(c.text, 14,
                                      weight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    for (var i = 0; i < primary.length; i++) ...[
                      FamButton(
                        label: primary[i].label,
                        onPressed: primary[i].onPressed,
                        kind: i == 0 ? FamButtonKind.danger : FamButtonKind.tonal,
                        height: 52,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FamButton(
                      label: dismiss.label,
                      onPressed: dismiss.onPressed,
                      kind: FamButtonKind.ghost,
                      height: 44,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.subbar .iconbtn`：42px 圓形 surface2 底的圖示鈕；[onTap] 為 null 時變淡（disabled）。
class FamIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const FamIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Opacity(
      opacity: onTap == null ? .35 : 1,
      child: Tooltip(
        message: tooltip,
        child: PressableScale(
          enabled: onTap != null,
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// `.subbar`：返回鈕＋標題（可收縮）＋右側元件。回傳 [AppBar] 以沿用狀態列安全區。
///
/// 標題字級固定 19／900；整條的文字縮放上限壓在 1.2，避免 360dp 寬時把標題擠沒。
PreferredSizeWidget famSubBar(
  BuildContext context, {
  required String title,
  VoidCallback? onBack,
  List<Widget> trailing = const [],
}) {
  final c = UbanColors.of(context);
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: c.bg,
    toolbarHeight: 64,
    titleSpacing: 12,
    title: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 1, maxScaleFactor: 1.2),
      ),
      child: Row(
        children: [
          FamIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '返回',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          // 標題同列有多個按鈕：必須可收縮（鐵律 #14）。
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text, 19, weight: FontWeight.w900),
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: 8), w],
        ],
      ),
    ),
  );
}

// ───────────────────────── 警示中心／清單共用（第 3 批新增） ─────────────────────────

/// `.filters`：橫向捲動的篩選膠囊列。不裁切（Clip.none），讓捲動中的膠囊能滑出
/// 外層 16px 內距直達螢幕邊緣（對應 `.filters{margin:0 -14px}`）。
class FamFilterRow extends StatelessWidget {
  final List<Widget> children;
  const FamFilterRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.fchip`：篩選膠囊（高 36、選取時 brandContainer＋brandStrong）。
/// [onTap] 為 null 時視為停用（變淡、不可點）。
class FamFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const FamFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Opacity(
      opacity: onTap == null ? .55 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.brandContainer : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? Colors.transparent : c.line,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: famText(
                selected ? c.brandStrong : c.text2,
                14,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.st`／`.st.ok`：清單列右側的狀態膠囊。[tone] 為 neutral（預設）或 brand（已處理）；
/// 傳 warm 則為「待處理」。文字最多三行、超出省略（鐵律 #14）。
class FamStatusPill extends StatelessWidget {
  final String label;
  final FamTone tone;
  final Widget? trailing;
  const FamStatusPill({
    super.key,
    required this.label,
    this.tone = FamTone.neutral,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final fg = famToneFg(c, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: famToneBg(c, tone),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: famText(fg, 12, weight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// `.daysep`：清單內的日期分隔小標。
class FamDaySep extends StatelessWidget {
  final String text;
  const FamDaySep(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: famText(c.text3, 12, weight: FontWeight.w700, letterSpacing: 1),
      ),
    );
  }
}

/// `.locbtn`：警示卡內的「查看位置」膠囊（surface 底、brandStrong 字）。
class FamLocButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? background;
  const FamLocButton({
    super.key,
    required this.label,
    required this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background ?? c.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_outlined, size: 16, color: c.brandStrong),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: famText(c.brandStrong, 13.5, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
