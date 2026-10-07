import 'package:flutter/material.dart';

import '../../../services/api/step_challenge_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_sheet.dart';
import '../widgets/fam_ui.dart';

/// 設定每週目標的簽名（測試可注入；預設走 [StepChallengeApi.setGoal]）。
typedef StepGoalSetter = Future<bool> Function(int goal);

/// ★ 2026-10-07 家庭步數挑戰：家屬挑本週目標（後端只接受 [kStepChallengeGoals] 五種）。
///
/// 成功以 `Navigator.pop(goal)` 關閉；失敗訊息留在面板內，可再試。
class StepGoalSheet extends StatefulWidget {
  final int currentGoal;
  final StepGoalSetter setter;

  const StepGoalSheet({
    super.key,
    required this.currentGoal,
    required this.setter,
  });

  /// 回傳新目標；取消或失敗關閉回傳 null。
  static Future<int?> show(
    BuildContext context, {
    required int currentGoal,
    required StepGoalSetter setter,
  }) {
    return showUbanSheet<int>(
      context,
      (ctx) => StepGoalSheet(currentGoal: currentGoal, setter: setter),
    );
  }

  @override
  State<StepGoalSheet> createState() => _StepGoalSheetState();
}

class _StepGoalSheetState extends State<StepGoalSheet> {
  late int _selected = widget.currentGoal;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    bool ok;
    try {
      ok = await widget.setter(_selected);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(_selected);
    } else {
      setState(() {
        _saving = false;
        _error = '暫時設定不了目標，請確認網路後再試一次';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('調整本週目標',
            style: famText(c.text, 18, weight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('全家（含長輩）一週合計要走的步數',
            style: famText(c.text2, 13, height: 1.45)),
        const SizedBox(height: 14),
        // Wrap：窄螢幕／大字級自動換行不溢位（規則 14）。
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final g in kStepChallengeGoals) _chip(c, g)],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              key: const ValueKey('step_goal_error'),
              style: famText(c.danger, 13.5,
                  weight: FontWeight.w600, height: 1.4)),
        ],
        const SizedBox(height: 16),
        FamButton(
          key: const ValueKey('step_goal_save'),
          label: '儲存',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _chip(UbanColors c, int g) {
    final selected = _selected == g;
    return Semantics(
      button: true,
      selected: selected,
      label: formatStepsWan(g),
      child: GestureDetector(
        key: ValueKey('step_goal_$g'),
        behavior: HitTestBehavior.opaque,
        onTap: _saving
            ? null
            : () => setState(() {
                  _selected = g;
                  _error = null;
                }),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandContainer : c.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? c.brand : Colors.transparent, width: 2),
          ),
          child: Text(
            formatStepsWan(g),
            maxLines: 1,
            style: famText(selected ? c.brandStrong : c.text, 15,
                weight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
