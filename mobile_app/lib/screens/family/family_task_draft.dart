import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../utils/server_time.dart';
import 'widgets/fam_ui.dart';

// ★ 2026-11 代理人協調：AI 照護秘書把問題「交給小嘎去問」。
// 本檔照 family_question_draft.dart 的寫法：後端 `task_draft` 的資料、卡片狀態、
// 草稿卡，以及「小嘎問到了」結果轉告用的純函式（已看過清單、過濾、訊息文字）。

/// 秘書產生的交辦草稿（後端 `task_draft: {question, purpose, followup}`，可能缺席／為 null）。
class TaskDraft {
  final String question;
  final String purpose;

  /// `schedule`（問到後排提醒）或 `report`（問到後回報）。
  final String followup;
  const TaskDraft({
    required this.question,
    required this.purpose,
    required this.followup,
  });

  /// 解析 `task_draft`。舊後端沒有此欄位、或問題為空時回 null（不顯示卡片）；
  /// followup 不認得時退回 `report`。
  static TaskDraft? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final q = raw['question'];
    final question = q is String ? q.trim() : '';
    if (question.isEmpty) return null;
    final p = raw['purpose'];
    final f = raw['followup'];
    return TaskDraft(
      question: question,
      purpose: p is String ? p.trim() : '',
      followup: f == 'schedule' ? 'schedule' : 'report',
    );
  }
}

enum TaskCardPhase { draft, sending, sent, cancelled }

/// 是否可按「交給小嘎」：送出中（防連點）或問題為空時停用。
bool canSendTask({required String question, required bool sending}) =>
    !sending && question.trim().isNotEmpty;

String taskFollowupLabel(String followup) =>
    followup == 'schedule' ? '問到後幫您排提醒' : '問到後回報給您';

class TaskDraftCard extends StatelessWidget {
  final TaskDraft draft;
  final TaskCardPhase phase;
  final String? errorText;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const TaskDraftCard({
    super.key,
    required this.draft,
    required this.phase,
    required this.errorText,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    if (phase == TaskCardPhase.sent) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '✓ 已交給小嘎去問',
          style: famText(c.brandStrong, 14.5, weight: FontWeight.w700, height: 1.5),
        ),
      );
    }
    if (phase == TaskCardPhase.cancelled) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('已取消交辦', style: famText(c.text3, 14, height: 1.5)),
      );
    }
    final sending = phase == TaskCardPhase.sending;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('交給小嘎去問', style: famText(c.text3, 13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(draft.question, style: famText(c.text, 15, height: 1.5)),
          const SizedBox(height: 4),
          Text(taskFollowupLabel(draft.followup),
              style: famText(c.text3, 13, height: 1.4)),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!, style: famText(c.danger, 13.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          FamButton(
            label: '交給小嘎',
            loading: sending,
            onPressed: canSendTask(question: draft.question, sending: sending)
                ? onSend
                : null,
          ),
          const SizedBox(height: 6),
          FamButton(
            label: '取消',
            kind: FamButtonKind.ghost,
            onPressed: sending ? null : onCancel,
          ),
        ],
      ),
    );
  }
}

// ───────── 小嘎問到了：結果由秘書轉告 ─────────

String copilotSeenAgentTasksKey(String elderId) => 'copilot_seen_agent_tasks_$elderId';

/// 挑出要轉告的任務：status 為 answered／expired、近 [days] 天內、task_id 不在 [seen]。
/// 時間取 answered_at，沒有則 created_at；都解析不到就略過（寧可少報也不洗版）。
/// 後端是新→舊，回傳改為舊→新。
List<Map<String, dynamic>> selectUnseenTasks(
  List<Map<String, dynamic>> tasks,
  Set<String> seen, {
  DateTime? now,
  int days = 7,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days));
  final out = <Map<String, dynamic>>[];
  for (final t in tasks) {
    final status = t['status'];
    if (status != 'answered' && status != 'expired') continue;
    final id = (t['task_id'] ?? '').toString();
    if (id.isEmpty || seen.contains(id)) continue;
    final at = ServerTime.parse(t['answered_at']) ?? ServerTime.parse(t['created_at']);
    if (at == null || at.isBefore(cutoff)) continue;
    out.add(t);
  }
  return out.reversed.toList();
}

/// 轉告訊息文字：優先 result_text；沒有時 answered 用 answer_text、expired 給固定說明。
String taskResultText(String elderName, Map<String, dynamic> t) {
  final result = (t['result_text'] ?? '').toString().trim();
  if (result.isNotEmpty) return result;
  if (t['status'] == 'expired') {
    return '小嘎還沒問到$elderName關於『${t['question'] ?? ''}』的回答。';
  }
  final ans = (t['answer_text'] ?? '').toString().trim();
  return '小嘎問到了：${ans.isEmpty ? '（已回答）' : ans}';
}

Future<Set<String>> loadSeenTaskIds(String elderId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(copilotSeenAgentTasksKey(elderId)) ?? const <String>[])
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> saveSeenTaskIds(String elderId, Set<String> ids) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = ids.toList();
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    await prefs.setStringList(copilotSeenAgentTasksKey(elderId), trimmed);
  } catch (_) {}
}
