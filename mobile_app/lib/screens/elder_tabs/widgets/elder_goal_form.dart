import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/api_service.dart';
import '../../../widgets/ui/ui.dart';

/// 長輩自建目標的表單與動作（新增／編輯／刪除）。
///
/// 目標存在與家人提醒同一張表（`remote_reminders`，`created_by_role='elder'`），
/// 因此打卡、進度環、胡蘿蔔、連續天數全部走既有路徑，這裡只負責「建立／修改／刪除」。

/// 是否為長輩自建的目標。
bool isElderGoal(Map<String, dynamic> r) =>
    (r['created_by_role'] ?? 'family').toString() == 'elder';

const List<({String label, String category})> _presets = [
  (label: '散步', category: 'exercise'),
  (label: '喝水', category: 'water'),
  (label: '量血壓', category: 'custom'),
  (label: '做運動', category: 'exercise'),
];

class _GoalDraft {
  final String title;
  final String category;
  final String timeStr;
  final bool onlyToday;
  const _GoalDraft(this.title, this.category, this.timeStr, this.onlyToday);
}

/// 開表單；成功寫入後回傳 true（呼叫端據此重新載入清單）。
Future<bool> runElderGoalForm(
  BuildContext context, {
  required String elderId,
  required int userId,
  Map<String, dynamic>? existing,
}) async {
  final draft = await showUbanSheet<_GoalDraft>(
    context,
    (ctx) => _ElderGoalForm(existing: existing),
  );
  if (draft == null) return false;

  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final repeat = draft.onlyToday ? '單次' : '每天';
  bool ok;
  if (existing == null) {
    ok = await ApiService.createElderReminder({
      'elder_id': elderId,
      'created_by_role': 'elder',
      'created_by_user_id': userId,
      'title': draft.title,
      'category': draft.category,
      'time_str': draft.timeStr,
      'repeat_days': repeat,
      'start_date': draft.onlyToday ? today : null,
    });
  } else {
    final id = int.tryParse(existing['id'].toString()) ?? -1;
    ok = await ApiService.updateElderReminder(id, {
      'title': draft.title,
      'category': draft.category,
      'time_str': draft.timeStr,
      'repeat_days': repeat,
      'start_date': draft.onlyToday ? today : '',
      'requester_role': 'elder',
      'requester_user_id': userId,
    });
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('儲存失敗，請稍後再試')),
    );
  }
  return ok;
}

/// 確認後刪除長輩自建目標；成功回傳 true。
Future<bool> confirmDeleteElderGoal(
  BuildContext context,
  Map<String, dynamic> goal, {
  required int userId,
}) async {
  final title = (goal['title'] ?? '').toString();
  final sure = await showUbanDialog<bool>(
    context,
    (ctx) {
      final c = UbanColors.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('刪除這個目標？', style: ubanText(22, FontWeight.w900, c.text)),
          const SizedBox(height: 8),
          Text('「$title」會從清單移除。',
              style: ubanText(18, FontWeight.w600, c.text2)),
          const SizedBox(height: 18),
          UbanButton(label: '刪除', onPressed: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: 8),
          UbanButton(
              label: '先不要',
              variant: UbanButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(false)),
        ],
      );
    },
  );
  if (sure != true) return false;
  final id = int.tryParse(goal['id'].toString()) ?? -1;
  final ok = await ApiService.deleteElderReminder(id,
      requesterRole: 'elder', requesterUserId: userId);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('刪除失敗，請稍後再試')),
    );
  }
  return ok;
}

class _ElderGoalForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ElderGoalForm({this.existing});

  @override
  State<_ElderGoalForm> createState() => _ElderGoalFormState();
}

class _ElderGoalFormState extends State<_ElderGoalForm> {
  late final TextEditingController _title;
  late TimeOfDay _time;
  late bool _onlyToday;
  String _category = 'custom';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: (e?['title'] ?? '').toString());
    _category = (e?['category'] ?? 'custom').toString();
    _time = const TimeOfDay(hour: 9, minute: 0);
    final parts = (e?['time_str'] ?? '').toString().split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) _time = TimeOfDay(hour: h, minute: m);
    }
    final rd = (e?['repeat_days'] ?? '每天').toString();
    _onlyToday = rd == '單次' || rd == '單次提醒';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeStr =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(_GoalDraft(t, _category, _timeStr, _onlyToday));
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(editing ? '修改我的目標' : '新增我的目標',
                style: ubanText(22, FontWeight.w900, c.text)),
            const SizedBox(height: 14),
            UbanTextField(
              label: '想做什麼？',
              hintText: '例如：散步',
              controller: _title,
              maxLength: 20,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _presets)
                  _Chip(
                    label: p.label,
                    selected: _title.text.trim() == p.label,
                    onTap: () => setState(() {
                      _title.text = p.label;
                      _category = p.category;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('幾點做？', style: ubanText(16, FontWeight.w700, c.text2)),
            const SizedBox(height: 6),
            UbanButton(
              label: _timeStr,
              icon: Icons.schedule_rounded,
              variant: UbanButtonVariant.ghost,
              onPressed: _pickTime,
            ),
            const SizedBox(height: 12),
            UbanSegmented(
              labels: const ['每天', '只有今天'],
              index: _onlyToday ? 1 : 0,
              onChanged: (i) => setState(() => _onlyToday = i == 1),
            ),
            const SizedBox(height: 18),
            UbanButton(
              label: '儲存',
              onPressed: _title.text.trim().isEmpty ? null : _save,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandSoft : c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? c.brandFill : Colors.transparent, width: 2),
          ),
          child: Text(label,
              style: ubanText(
                  18, FontWeight.w700, selected ? c.brandStrong : c.text)),
        ),
      ),
    );
  }
}
