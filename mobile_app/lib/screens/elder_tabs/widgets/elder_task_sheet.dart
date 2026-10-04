import 'package:flutter/material.dart';

import '../../../utils/reminder_schedule.dart';
import '../../../widgets/ui/ui.dart';

/// 提醒分類 → 圖示與色調（對應設計稿 `catStyle`）。
({IconData icon, Color bg, Color fg}) reminderCategoryStyle(
    UbanColors c, String category) {
  switch (category) {
    case 'medication':
      return (icon: Icons.medication_rounded, bg: c.warmContainer, fg: c.warm);
    case 'water':
      return (icon: Icons.water_drop_rounded, bg: c.infoContainer, fg: c.info);
    case 'exercise':
      return (
        icon: Icons.directions_walk_rounded,
        bg: c.brandSoft,
        fg: c.brandStrong
      );
    default:
      return (icon: Icons.schedule_rounded, bg: c.brandSoft, fg: c.brandStrong);
  }
}

/// 設計稿 `#sh-tasks`「今天要做的事」抽屜內容：三組（現在要做 展開／稍後 收合／已完成 收合）。
///
/// 純展示：資料由 [readGroups] 即時取得，打卡一律交給 [onCheckIn]（首頁傳入既有的
/// `_completeNextDose`，這裡不碰 SharedPreferences／API）。打卡前後各重建一次，
/// 讓樂觀更新與失敗回退都能反映在抽屜裡。
class ElderTaskSheetBody extends StatefulWidget {
  final ReminderGroups Function() readGroups;
  final Future<void> Function(Map<String, dynamic> reminder) onCheckIn;

  const ElderTaskSheetBody({
    super.key,
    required this.readGroups,
    required this.onCheckIn,
  });

  @override
  State<ElderTaskSheetBody> createState() => _ElderTaskSheetBodyState();
}

class _ElderTaskSheetBodyState extends State<ElderTaskSheetBody> {
  final Map<String, bool> _open = {'now': true, 'later': false, 'done': false};

  Future<void> _check(Map<String, dynamic> r) async {
    final f = widget.onCheckIn(r);
    if (mounted) setState(() {});
    await f;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final g = widget.readGroups();
    final total = g.dueNow.length + g.later.length + g.done.length;
    final sections =
        <({String key, String name, List<Map<String, dynamic>> items})>[
      (key: 'now', name: '現在要做', items: g.dueNow),
      (key: 'later', name: '稍後', items: g.later),
      (key: 'done', name: '已完成', items: g.done),
    ].where((s) => s.items.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('今天要做的事',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(22, FontWeight.w900, c.text)),
            ),
            const SizedBox(width: 8),
            _Tag('${g.done.length}／$total'),
          ],
        ),
        const SizedBox(height: 6),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('今天沒有要做的事',
                textAlign: TextAlign.center,
                style: ubanText(19, FontWeight.w700, c.text2)),
          ),
        for (final s in sections) ...[
          _GroupHeader(
            title: '${s.name}（${s.items.length}）',
            open: _open[s.key]!,
            onTap: () => setState(() => _open[s.key] = !_open[s.key]!),
          ),
          AnimatedSize(
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: UbanMotion.enter,
            alignment: Alignment.topCenter,
            child: _open[s.key]!
                ? Column(
                    children: [
                      for (final r in s.items)
                        _TaskRow(
                          reminder: r,
                          done: s.key == 'done',
                          onCheck: () => _check(r),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: ubanBrandText(17, FontWeight.w600, c.text2, height: 1.3)),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final bool open;
  final VoidCallback onTap;

  const _GroupHeader(
      {required this.title, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(18, FontWeight.w900, c.text)),
              ),
              AnimatedRotation(
                turns: open ? .25 : 0,
                duration: reduceMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                child:
                    Icon(Icons.chevron_right_rounded, size: 28, color: c.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final bool done;
  final VoidCallback onCheck;

  const _TaskRow(
      {required this.reminder, required this.done, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final st =
        reminderCategoryStyle(c, (reminder['category'] ?? '').toString());
    final time = (reminder['time_str'] ?? '').toString();
    final title = (reminder['title'] ?? '提醒').toString();
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: st.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(st.icon, size: 24, color: st.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (time.isNotEmpty)
                  Text(time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanBrandText(18, FontWeight.w600, c.text2)),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(
                    19,
                    FontWeight.w700,
                    done ? c.text3 : c.text,
                  ).copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Tick(done: done, label: title, onTap: done ? null : onCheck),
        ],
      ),
    );
  }
}

/// 設計稿 `.tick`：52 圓、2.5 框；完成時填 brandFill 並顯示勾。點擊範圍放大到 60。
class _Tick extends StatelessWidget {
  final bool done;
  final String label;
  final VoidCallback? onTap;

  const _Tick({required this.done, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final dur = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    return Semantics(
      button: onTap != null,
      label: done ? '已完成 $label' : '打卡 $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Center(
            child: AnimatedContainer(
              duration: dur,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.brandFill : Colors.transparent,
                border: Border.all(
                    color: done ? c.brandFill : c.surface3, width: 2.5),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: 28, color: c.onBrand)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
