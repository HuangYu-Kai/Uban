import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api/daily_question_api.dart';
import '../../theme/app_theme.dart';
import '../../utils/server_time.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

// ★ 2026-10-07 交接 A2：每日一問併入 AI 照護秘書。
// 本檔照抄 family_share_draft.dart 的寫法：後端 `question_draft`（出題草稿）的資料、
// 狀態列舉與草稿卡，另含「長輩回答由秘書轉告」用的純函式（已看過清單、7 天過濾、訊息文字）。

/// AI 照護秘書「出題給長輩」的草稿（後端 `question_draft: {text}`，可能缺席／為 null）。
class QuestionDraft {
  final String text;
  const QuestionDraft({required this.text});

  /// 解析後端回覆的 `question_draft`。舊版後端沒有此欄位、或沒有文字時回 null
  /// （呼叫端就當作沒有出題草稿，不顯示卡片）。
  static QuestionDraft? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final t = raw['text'];
    final text = t is String ? t.trim() : '';
    if (text.isEmpty) return null;
    return QuestionDraft(text: text);
  }
}

/// 出題卡的狀態（由畫面持有，卡片本身無狀態，避免捲出畫面後遺失）。
enum QuestionCardPhase { draft, sending, sent, cancelled }

/// 「交給小嘎問」是否可按：題目為空、或正在送出時停用（長度由 API 層再擋並回報原因）。
bool canSendQuestion({required String text, required bool sending}) {
  if (sending) return false;
  return text.trim().isNotEmpty;
}

/// 出題成功後秘書顯示的文字。
String questionSentMessage(String elderName) => '小嘎會在$elderName下次聊天時問';

/// 對話中的出題卡：可編輯題目、「交給小嘎問」／「取消」。
class QuestionDraftCard extends StatelessWidget {
  final TextEditingController controller;
  final String elderName;
  final QuestionCardPhase phase;
  final String? errorText;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const QuestionDraftCard({
    super.key,
    required this.controller,
    required this.elderName,
    required this.phase,
    required this.errorText,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    if (phase == QuestionCardPhase.sent) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          questionSentMessage(elderName),
          style: famText(c.brandStrong, 14.5, weight: FontWeight.w700, height: 1.5),
        ),
      );
    }
    if (phase == QuestionCardPhase.cancelled) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('已取消出題', style: famText(c.text3, 14, height: 1.5)),
      );
    }
    final sending = phase == QuestionCardPhase.sending;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('出題草稿', style: famText(c.text3, 13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          FamInput(
            controller: controller,
            hintText: '想問$elderName什麼？',
            minLines: 2,
            maxLines: 5,
            height: 72,
            keyboardType: TextInputType.multiline,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!, style: famText(c.danger, 13.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          // 按鈕依輸入框內容即時啟停（空白不可送）。
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final ok = canSendQuestion(text: value.text, sending: sending);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FamButton(
                    label: '交給小嘎問',
                    loading: sending,
                    onPressed: ok ? onSend : null,
                  ),
                  const SizedBox(height: 6),
                  FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: sending ? null : onCancel,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ───────── 長輩回答由秘書轉告 ─────────

/// 轉告「已看過」清單的本機 key（裝置層級、不是 session key）。
String copilotSeenAnswersKey(String elderId) => 'copilot_seen_daily_answers_$elderId';

/// 從歷史挑出要轉告的回答：已回答、近 [days] 天內、id 不在 [seen]。
/// 回答時間解析不到就略過（寧可少轉告，也不讓舊資料重複洗版）。
/// 歷史是新→舊，回傳改為舊→新，對話先看到較早的回答。
List<DailyQuestionItem> selectUnseenAnswers(
  List<DailyQuestionItem> items,
  Set<String> seen, {
  DateTime? now,
  int days = 7,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days));
  final out = <DailyQuestionItem>[];
  for (final it in items) {
    if (!it.answered) continue;
    if (seen.contains(it.id.toString())) continue;
    final at = ServerTime.parse(it.answeredAt);
    if (at == null || at.isBefore(cutoff)) continue;
    out.add(it);
  }
  return out.reversed.toList();
}

/// 秘書轉告訊息：`{稱呼}回答了『題目』：…`。
String answerRelayText(String elderName, DailyQuestionItem it) {
  final answer = it.answerSnippet.isEmpty ? '（已回答）' : it.answerSnippet;
  return '$elderName回答了『${it.question}』：$answer';
}

Future<Set<String>> loadSeenAnswerIds(String elderId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(copilotSeenAnswersKey(elderId)) ?? const <String>[]).toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> saveSeenAnswerIds(String elderId, Set<String> ids) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // 只留最近 200 筆，避免無限成長。
    final list = ids.toList();
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    await prefs.setStringList(copilotSeenAnswersKey(elderId), trimmed);
  } catch (_) {}
}
