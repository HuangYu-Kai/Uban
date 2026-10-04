import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/family_theme.dart';
import '../../../theme/uban_motion.dart';
import '../../../widgets/ui/blob_ripple.dart';
import '../../../widgets/ui/pressable_scale.dart';
import '../../../widgets/ui/uban_dialog.dart';
import 'fam_ui.dart';

/// 家屬端第 4 批（資料分頁與其子頁）新增的共用小元件（對應 design_prototype/family.css）。
///
/// 全部以 [UbanColors.of] 取色；原則同 `fam_ui.dart`：少用小圖示、暖色只給待處理、
/// 不用漸層與色光暈。**純外觀元件**——不碰任何 callback 的語意，只負責排版。

/// `.group2`：圓角 22、surface 底、卡片陰影；有 [title] 時顯示 `.gh` 小標。
/// 列與列之間以 1px `line` 分隔（`.setrow+.setrow{border-top}`）。
class FamGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const FamGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: c.shadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: famText(c.text3, 12,
                    weight: FontWeight.w700, letterSpacing: 1.2),
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, color: c.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.setrow`：標題＋說明在左（不放圖示方塊），右側放開關／箭頭／徽章。
/// 有 [onTap] 時整列可點（液態暈開）；[chevron] 為 true 時右側補一個 chevron。
class FamSetRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? titleColor;
  final int subtitleMaxLines;

  const FamSetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.titleColor,
    this.subtitleMaxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 標題與說明都是動態或長字串，必須可收縮（鐵律 #14）。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(titleColor ?? c.text, 15.5,
                      weight: FontWeight.w700, height: 1.3),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.text2, 12.5, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (chevron) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 22, color: c.text3),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .18),
        child: row,
      ),
    );
  }
}

/// `.entry`：入口小卡（圓角 20、標題 15.5/900、說明 12.5）。可放一個 [extra]（例如迷你走勢）。
class FamEntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? extra;
  final VoidCallback? onTap;
  const FamEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.extra,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(20);
    return PressableScale(
      enabled: onTap != null,
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        enabled: onTap != null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: br,
            boxShadow: c.shadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: famText(c.text, 15.5, weight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: famText(c.text2, 12.5, height: 1.45),
              ),
              if (extra != null) ...[const SizedBox(height: 8), extra!],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.story`：卡片內的一則故事列（標題＋一行說明，不放封面圖示）。
/// [first] 為 true 時不畫上分隔線。[trailing] 通常放一個 [FamChip]。
class FamStoryRow extends StatelessWidget {
  final String title;
  final String meta;
  final Widget? trailing;
  final bool first;
  final VoidCallback? onTap;
  const FamStoryRow({
    super.key,
    required this.title,
    required this.meta,
    this.trailing,
    this.first = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text, 15, weight: FontWeight.w700, height: 1.35),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.text2, 12.5),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

/// `.mem`：回憶錄方塊（上方 4:3 色塊＋下方標題／說明）。色塊用單色（不用漸層），
/// 中央放標題首字；[onFavorite] 有值時右上角出現珍藏愛心鈕。
class FamMemCard extends StatelessWidget {
  final String title;
  final String meta;
  final FamTone tone;
  final bool favorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  const FamMemCard({
    super.key,
    required this.title,
    required this.meta,
    this.tone = FamTone.brand,
    this.favorite = false,
    this.onTap,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(20);
    final trimmed = title.trim();
    final initial =
        trimmed.isEmpty ? '·' : String.fromCharCode(trimmed.runes.first);
    return PressableScale(
      enabled: onTap != null,
      onTap: onTap,
      child: BlobRipple(
        color: c.brand.withValues(alpha: .22),
        borderRadius: br,
        enabled: onTap != null,
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: br,
            boxShadow: c.shadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: famToneBg(c, tone),
                        child: Center(
                          child: Text(
                            initial,
                            style: famText(famToneFg(c, tone), 34,
                                weight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                    if (onFavorite != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onFavorite,
                          child: Semantics(
                            button: true,
                            label: favorite ? '取消珍藏' : '加入珍藏',
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                favorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 20,
                                color: favorite ? c.danger : c.text2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 標題固定保留兩行高度，讓同一排兩張卡片等高（放大字級也一樣）。
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.textScalerOf(context)
                                .scale(14.5) *
                            1.4 *
                            2,
                      ),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text, 14.5,
                            weight: FontWeight.w700, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text2, 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.plan`：方案卡（圓角 24、2px 邊；[selected] 時邊色為 brand）。
class FamPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String subtitle;
  final List<String> features;
  final String? badge;
  final FamTone badgeTone;
  final bool selected;
  final Widget? action;
  const FamPlanCard({
    super.key,
    required this.title,
    required this.price,
    this.period = '',
    this.subtitle = '',
    required this.features,
    this.badge,
    this.badgeTone = FamTone.brand,
    this.selected = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.shadows.card,
        border: Border.all(
          color: selected ? c.brand : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text, 18, weight: FontWeight.w900),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Flexible(child: FamChip(label: badge!, tone: badgeTone)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: price,
                style: famText(c.text, 24, weight: FontWeight.w700, tabular: true),
              ),
              if (period.isNotEmpty)
                TextSpan(
                  text: ' $period',
                  style: famText(c.text2, 13),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: famText(c.text2, 13, height: 1.45)),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.check_rounded, size: 18, color: c.brandStrong),
                ),
                const SizedBox(width: 8),
                // 方案特色文案長度不一，必須可收縮（鐵律 #14）。
                Expanded(
                  child: Text(features[i],
                      style: famText(c.text2, 14, height: 1.4)),
                ),
              ],
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// 說明／錯誤小橫幅：圓角 14、依 [tone] 上底色（neutral＝surface2、danger＝dangerContainer…）。
/// 不放圖示，文字自動換行。
class FamNote extends StatelessWidget {
  final String text;
  final FamTone tone;
  final int? maxLines;
  const FamNote({
    super.key,
    required this.text,
    this.tone = FamTone.neutral,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: famToneBg(c, tone),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: famText(famToneFg(c, tone), 13, height: 1.5),
      ),
    );
  }
}

/// 載入中／空狀態共用的置中區塊（撐滿寬度，內容相對卡片置中）。
class FamStateBlock extends StatelessWidget {
  final Widget child;
  final double height;
  const FamStateBlock({super.key, required this.child, this.height = 140});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Center(child: child),
        ),
      );
}

/// 家屬主題下的 [UbanDialog]（400ms 彈性縮放，外觀與 `showUbanDialog` 相同）。
///
/// `showUbanDialog` 走 `showGeneralDialog`，路由不會沿用呼叫端的 Theme，深色模式下
/// 對話框會落回 App 預設色票；這裡在路由內自己掛 [FamilyThemeScope]，[builder] 拿到的
/// context 與 [UbanDialog] 本身都吃得到家屬色票。[context] 只用來取遮罩色與 Navigator。
Future<T?> showFamDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) {
  final c = UbanColors.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '關閉',
    barrierColor: c.scrim,
    transitionDuration: UbanMotion.dialogDuration,
    pageBuilder: (ctx, _, __) => FamilyThemeScope(
      child: Builder(
        builder: (themed) =>
            Center(child: UbanDialog(child: builder(themed))),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
          parent: anim, curve: UbanMotion.dialog, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: const Interval(0, .5)),
        child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
