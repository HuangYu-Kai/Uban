import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/ui/pressable_scale.dart';
import 'fam_ui.dart';

/// 家屬端「戶外 GPS」三個畫面（移動軌跡／常去地點／外出趨勢）共用的純外觀元件
/// （對應 design_prototype/family.css 的 `.datepill`、`.mapwarn`、`.fab`、`.mapstatus`、
/// `.mapempty`、`.ev`、`.place`、`.rule`、`.inl`、`.sumgrid`、`.legend`）。
///
/// 全部不碰資料與 callback 之外的邏輯：文字與 callback 由呼叫端傳入。
/// 原則：少用小圖示、不帶色光暈陰影、暖色只給「待處理」。
/// 所有同列的動態字串都可收縮（CLAUDE.md §3.1 第 14 條）。

// ───────────────────────── 地圖：上方 ─────────────────────────

/// `.datepill`：前一天／日期／後一天。[onPrev]／[onNext] 為 null 時該鈕變淡。
class GpsDatePill extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback onPick;
  final VoidCallback? onNext;

  const GpsDatePill({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onPick,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => Opacity(
          opacity: onTap == null ? .3 : 1,
          child: Tooltip(
            message: tip,
            child: PressableScale(
              enabled: onTap != null,
              onTap: onTap,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: c.text),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: c.shadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, '前一天', onPrev),
          PressableScale(
            onTap: onPick,
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                style: famText(c.text, 14, weight: FontWeight.w600, tabular: true),
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, '後一天', onNext),
        ],
      ),
    );
  }
}

// ───────────────────────── 地圖：疊層 ─────────────────────────

/// `.mapwarn`：長輩手機定位有問題時的警示卡（warm 底，文字為動態字串，可多行）。
class GpsMapWarn extends StatelessWidget {
  final String text;
  const GpsMapWarn({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.warmContainer,
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.shadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.location_off_rounded, size: 22, color: c.warm),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: famText(c.warm, 13.5, weight: FontWeight.w700, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.fab`：48px 玻璃方鈕（圓角 16、霧面、中性陰影）。[active] 用於除錯開關的啟用狀態。
class GpsGlassButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const GpsGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(16);
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: br, boxShadow: c.shadows.glass),
          child: ClipRRect(
            borderRadius: br,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: active ? c.brandContainer : c.glass,
                  borderRadius: br,
                  border: Border.all(color: c.glassLine),
                ),
                child: Icon(icon,
                    size: 22, color: active ? c.brandStrong : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.mapstatus`：地圖底部的玻璃狀態列。
///
/// [title] 是主要一行（最後更新／目前在哪）；[subtitle] 是摘要；[debugLine] 只在除錯疊圖開啟時有值。
/// [stale] 為 true 時左側色塊改灰（資料過舊）。[onTap] 為 null 代表沒有時間軸可開。
class GpsMapStatusBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? debugLine;
  final bool stale;
  final VoidCallback? onTap;

  const GpsMapStatusBar({
    super.key,
    required this.title,
    this.subtitle,
    this.debugLine,
    this.stale = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final br = BorderRadius.circular(24);
    final hasTimeline = onTap != null;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: br, boxShadow: c.shadows.glass),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: c.glass,
            shape: RoundedRectangleBorder(
              borderRadius: br,
              side: BorderSide(color: c.glassLine),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: br,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  children: [
                    // `.ib`：用色點取代小圖示；過舊時整塊轉灰。
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: stale ? c.surface3 : c.brandContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: FamDot(
                          color: stale ? c.text3 : c.brandFill, size: 12),
                    ),
                    const SizedBox(width: 12),
                    // 三行都是動態字串：包 Expanded 才能在窄螢幕／大字級下收縮（第 14 條）。
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text, 15, weight: FontWeight.w900),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: famText(c.text2, 12.5),
                            ),
                          ],
                          if (debugLine != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              debugLine!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: famText(c.warm, 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (hasTimeline) ...[
                      const SizedBox(width: 8),
                      Text('時間軸',
                          maxLines: 1,
                          style: famText(c.brandStrong, 13,
                              weight: FontWeight.w700)),
                      Icon(Icons.expand_less_rounded,
                          size: 20, color: c.brandStrong),
                    ],
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

/// `.mapempty`：整頁置中的狀態畫面（分享關閉／讀取失敗／尚無資料／空清單）。
///
/// 外層是可下拉的捲動容器，讓 `RefreshIndicator` 在這些畫面仍然有效。
class GpsMapEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// 版面頂部留白；地圖頁用大一點，清單內嵌時用小一點。
  final double topPadding;

  const GpsMapEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.topPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, topPadding, 28, 40),
            child: Center(child: GpsEmptyBlock(icon: icon, title: title, message: message)),
          ),
        ),
      ),
    );
  }
}

/// `.mapempty` 的內容區塊（84px 圖示方塊＋標題＋說明），可嵌在任何捲動容器。
class GpsEmptyBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const GpsEmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 40, color: c.text2),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: famText(c.text, 20, weight: FontWeight.w900, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: famText(c.text2, 14.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 行程時間軸 ─────────────────────────

enum GpsEventKind { depart, move, stay, gap }

Color gpsEventColor(UbanColors c, GpsEventKind k) {
  switch (k) {
    case GpsEventKind.depart:
      return c.brandFill;
    case GpsEventKind.move:
      return c.info;
    case GpsEventKind.stay:
      return c.warm;
    case GpsEventKind.gap:
      return c.text3;
  }
}

/// `.ev`：時間（52～64px）｜軌道＋圓點（22px）｜說明。
///
/// [time] 是 `08:12` 或 `08:12–09:30`；區間會拆成兩行（起／迄）以免大字級擠爆。
/// [isFirst]／[isLast] 決定軌道線的頭尾要不要收掉；斷訊（gap）的軌道為虛線。
class GpsTimelineRow extends StatelessWidget {
  final GpsEventKind kind;
  final String time;
  final String description;
  final bool ongoing;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const GpsTimelineRow({
    super.key,
    required this.kind,
    required this.time,
    required this.description,
    this.ongoing = false,
    this.isFirst = false,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final color = gpsEventColor(c, kind);
    final parts = time.split('–');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parts.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text2, 14,
                            weight: FontWeight.w600, tabular: true)),
                    if (parts.length > 1)
                      Text('–${parts.last}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: famText(c.text3, 12.5,
                              weight: FontWeight.w600, tabular: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 22,
              child: CustomPaint(
                painter: _RailPainter(
                  color: color,
                  line: c.line,
                  dashed: kind == GpsEventKind.gap,
                  dashColor: c.text3,
                  surface: c.surface,
                  isFirst: isFirst,
                  isLast: isLast,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                child: Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: famText(
                    c.text,
                    15,
                    weight: ongoing ? FontWeight.w900 : FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  final Color color, line, dashColor, surface;
  final bool dashed, isFirst, isLast;

  _RailPainter({
    required this.color,
    required this.line,
    required this.dashColor,
    required this.surface,
    required this.dashed,
    required this.isFirst,
    required this.isLast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final top = isFirst ? 18.0 : 0.0;
    final bottom = isLast ? 18.0 : size.height;
    if (bottom > top) {
      if (dashed) {
        final p = Paint()
          ..color = dashColor
          ..strokeWidth = 2;
        for (var y = top; y < bottom; y += 8) {
          canvas.drawLine(Offset(x, y), Offset(x, (y + 4).clamp(top, bottom)), p);
        }
      } else {
        canvas.drawLine(
          Offset(x, top),
          Offset(x, bottom),
          Paint()
            ..color = line
            ..strokeWidth = 2,
        );
      }
    }
    // 圓點：外環 1.5（currentColor）＋ 3px surface 描邊 ＋ 實心。
    const cy = 20.0;
    canvas.drawCircle(Offset(x, cy), 8.5, Paint()..color = color);
    canvas.drawCircle(Offset(x, cy), 7, Paint()..color = surface);
    canvas.drawCircle(Offset(x, cy), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RailPainter o) =>
      o.color != color ||
      o.line != line ||
      o.dashed != dashed ||
      o.isFirst != isFirst ||
      o.isLast != isLast ||
      o.surface != surface;
}

// ───────────────────────── 常去地點 ─────────────────────────

/// `.place`：左側 10px 色點（家＝brandFill、其他＝info）＋名稱／副標＋右側元件。
class GpsPlaceRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isHome;
  final bool first;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GpsPlaceRow({
    super.key,
    required this.name,
    required this.subtitle,
    required this.isHome,
    this.first = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              FamDot(color: isHome ? c.brandFill : c.info),
              const SizedBox(width: 12),
              // 地點名稱是使用者自訂字串：可收縮（第 14 條）。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text, 15.5, weight: FontWeight.w700),
                          ),
                        ),
                        if (isHome) ...[
                          const SizedBox(width: 6),
                          const FamChip(label: '家', tone: FamTone.brand),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text2, 12.5),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// `.rule`：標題＋說明（可含 [gpsInline] 內嵌值）＋右側開關。[disabled] 時文字變 text3。
class GpsRuleRow extends StatelessWidget {
  final String title;

  /// 說明文字，用 [gpsPlain]／[gpsInline] 組成。
  final List<InlineSpan> body;
  final bool disabled;
  final bool first;
  final Widget trailing;

  const GpsRuleRow({
    super.key,
    required this.title,
    required this.body,
    required this.trailing,
    this.disabled = false,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: famText(disabled ? c.text3 : c.text, 15.5,
                        weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: body),
                    style: famText(disabled ? c.text3 : c.text2, 13.5, height: 1.9),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// 說明文字中的一般片段。
InlineSpan gpsPlain(String text) => TextSpan(text: text);

/// 說明文字中的 `.inl` 內嵌可點值；[onTap] 為 null 時只顯示不可點。
/// 要彈出選單時把 [wrap] 傳進來，用 [PopupMenuButton] 包住外觀。
InlineSpan gpsInline(
  String label, {
  VoidCallback? onTap,
  Widget Function(Widget chip)? wrap,
}) =>
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GpsInlineValue(label: label, onTap: onTap, wrap: wrap),
    );

/// `.inl`：brandSoft 底、圓角 8、粗體 brandStrong、右側小三角。
class GpsInlineValue extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget Function(Widget chip)? wrap;

  const GpsInlineValue({super.key, required this.label, this.onTap, this.wrap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final chip = Container(
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: famText(c.brandStrong, 14,
                  weight: FontWeight.w700, tabular: true)),
          Icon(Icons.arrow_drop_down_rounded, size: 18, color: c.brandStrong),
        ],
      ),
    );
    if (wrap != null) return wrap!(chip);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}

// ───────────────────────── 外出趨勢 ─────────────────────────

/// `.sumgrid .stat`：小標＋大數字＋單位（surface2 底、圓角 16）。
class GpsSumCell extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const GpsSumCell({super.key, required this.label, required this.value, this.unit});

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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text2, 12)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: value,
                  style: famText(c.text, 22,
                      weight: FontWeight.w700, tabular: true)),
              if (unit != null)
                TextSpan(
                    text: ' $unit',
                    style: famText(c.text2, 12, weight: FontWeight.w700)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// `.chart-h`：色塊＋標題（可收縮）＋右側單位。
class GpsChartHead extends StatelessWidget {
  final String title;
  final String? unit;
  final Color swatch;

  const GpsChartHead({super.key, required this.title, required this.swatch, this.unit});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: swatch, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text, 16, weight: FontWeight.w900),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 8),
          Text('（$unit）', maxLines: 1, style: famText(c.text2, 12.5)),
        ],
      ],
    );
  }
}

/// `.legend`：「今天（統計中）」淡色塊說明＋點長條提示。
class GpsLegend extends StatelessWidget {
  final Color color;
  const GpsLegend({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Text('今天（統計中）', style: famText(c.text2, 12.5)),
          ],
        ),
        Text('點長條看當天軌跡', style: famText(c.text3, 12.5)),
      ],
    );
  }
}
