import 'package:flutter/material.dart';

import '../../../utils/reminder_schedule.dart';
import '../../../utils/display_text.dart';
import '../../../widgets/ui/ui.dart';
import 'elder_goal_form.dart';

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

  /// 「＋ 新增我的目標」；為 null 且沒有長輩自建項目時，維持原本的三組呈現。
  final Future<void> Function()? onAddGoal;

  /// 長輩自建目標的修改／刪除（只對 `created_by_role=='elder'` 的列出現）。
  final Future<void> Function(Map<String, dynamic> goal)? onEditGoal;
  final Future<void> Function(Map<String, dynamic> goal)? onDeleteGoal;

  const ElderTaskSheetBody({
    super.key,
    required this.readGroups,
    required this.onCheckIn,
    this.onAddGoal,
    this.onEditGoal,
    this.onDeleteGoal,
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

  Future<void> _run(Future<void> Function() f) async {
    await f();
    if (mounted) setState(() {});
  }

  /// 兩區（家人提醒／我的目標）：各區未完成在前（依時間）、已完成在後。
  List<Widget> _splitSections(UbanColors c, ReminderGroups g) {
    final pending = [...g.dueNow, ...g.later]..sort((a, b) =>
        (a['time_str'] ?? '')
            .toString()
            .compareTo((b['time_str'] ?? '').toString()));
    final all = [
      for (final r in pending) (r: r, done: false),
      for (final r in g.done) (r: r, done: true),
    ];
    Widget section(String name, bool mine) {
      final rows = all.where((e) => isElderGoal(e.r) == mine).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(name, style: ubanText(16, FontWeight.w700, c.text2)),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(mine ? '還沒有自己的目標' : '家人還沒有設定提醒',
                  style: ubanText(17, FontWeight.w600, c.text3)),
            ),
          for (final e in rows)
            ElderTaskRow(
              reminder: e.r,
              done: e.done,
              onCheck: () => _check(e.r),
              onEdit: mine && widget.onEditGoal != null
                  ? () => _run(() => widget.onEditGoal!(e.r))
                  : null,
              onDelete: mine && widget.onDeleteGoal != null
                  ? () => _run(() => widget.onDeleteGoal!(e.r))
                  : null,
            ),
        ],
      );
    }

    return [
      section('家人提醒', false),
      const SizedBox(height: 8),
      Divider(height: 1, thickness: 1, color: c.line),
      section('我的目標', true),
      const SizedBox(height: 12),
      if (widget.onAddGoal != null)
        UbanButton(
          label: '新增我的目標',
          icon: Icons.add_rounded,
          onPressed: () => _run(widget.onAddGoal!),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final g = widget.readGroups();
    final total = g.dueNow.length + g.later.length + g.done.length;
    final hasMine = [...g.dueNow, ...g.later, ...g.done].any(isElderGoal);
    final split = widget.onAddGoal != null || hasMine;
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
            ElderTaskTag('${g.done.length}／$total'),
          ],
        ),
        const SizedBox(height: 6),
        if (split) ..._splitSections(c, g),
        if (!split && sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('今天沒有要做的事',
                textAlign: TextAlign.center,
                style: ubanText(19, FontWeight.w700, c.text2)),
          ),
        if (!split)
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
                          ElderTaskRow(
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

/// 設計稿 `.tag`：右上角「done／total」小膠囊（首頁任務卡與抽屜共用）。
class ElderTaskTag extends StatelessWidget {
  final String text;
  const ElderTaskTag(this.text, {super.key});

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

/// 任務列（設計稿 `.trow`）：抽屜與首頁任務卡共用；onEdit／onDelete 為 null 時不顯示選單。
class ElderTaskRow extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final bool done;
  final VoidCallback onCheck;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ElderTaskRow({
    super.key,
    required this.reminder,
    required this.done,
    required this.onCheck,
    this.onEdit,
    this.onDelete,
  });

  Future<void> _showGoalMenu(BuildContext context) async {
    final pick = await showUbanSheet<String>(
      context,
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UbanButton(
              label: '修改', onPressed: () => Navigator.of(ctx).pop('edit')),
          const SizedBox(height: 8),
          UbanButton(
              label: '刪除',
              variant: UbanButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop('delete')),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (pick == 'edit') onEdit?.call();
    if (pick == 'delete') onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final st =
        reminderCategoryStyle(c, (reminder['category'] ?? '').toString());
    final time = (reminder['time_str'] ?? '').toString();
    final title = stripEmoji((reminder['title'] ?? '提醒').toString());
    return GestureDetector(
      onLongPress: onEdit,
      child: Container(
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
            if (onEdit != null)
              IconButton(
                tooltip: '修改或刪除 $title',
                icon: Icon(Icons.more_horiz_rounded, size: 26, color: c.text2),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => _showGoalMenu(context),
              ),
            const SizedBox(width: 4),
            ElderTaskTick(
                done: done, label: title, onTap: done ? null : onCheck),
          ],
        ),
      ),
    );
  }
}

/// 設計稿 `.tick`：52 圓、2.5 框；完成時填 brandFill 並顯示勾。點擊範圍放大到 60。
class ElderTaskTick extends StatelessWidget {
  final bool done;
  final String label;
  final VoidCallback? onTap;

  const ElderTaskTick(
      {super.key,
      required this.done,
      required this.label,
      required this.onTap});

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
