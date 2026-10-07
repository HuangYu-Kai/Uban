import 'package:flutter/material.dart';

import '../../../services/api/elder_daily_question_api.dart';
import '../../../widgets/ui/ui.dart';

/// ★ 2026-10-07 每日一問：長輩首頁「今天的小問題」卡片。
///
/// 純展示元件（資料與動作由首頁注入）：
/// - 未回答：大字題目＋（家人出題時）出題者＋「聽小嘎唸」＋大「我來回答」。
/// - 已回答：「今天已經回答了，家人會看到喔」＋回答摘要＋「改一下」。
/// 長輩端字級 ≥20、按鈕高 ≥60；所有可變長度文字都限制行數（規則 14）。
class ElderDailyQuestionCard extends StatelessWidget {
  final DailyQuestion question;
  final VoidCallback? onListen;
  final VoidCallback onAnswer;

  const ElderDailyQuestionCard({
    super.key,
    required this.question,
    required this.onAnswer,
    this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final q = question;
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '今天的小問題',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ubanText(20, FontWeight.w800, c.brandStrong),
          ),
          const SizedBox(height: 10),
          Text(
            q.question,
            key: const ValueKey('daily_question_text'),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: ubanText(26, FontWeight.w800, c.text, height: 1.4),
          ),
          if (q.isFromFamily && q.askedByName != null) ...[
            const SizedBox(height: 8),
            Text(
              '（家人 ${q.askedByName} 出的題目）',
              key: const ValueKey('daily_question_from'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ubanText(20, FontWeight.w600, c.text2, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          if (q.answered) ..._answered(c) else ..._unanswered(),
        ],
      ),
    );
  }

  List<Widget> _unanswered() => [
        if (onListen != null) ...[
          UbanButton(
            key: const ValueKey('daily_question_listen'),
            label: '聽小嘎唸',
            icon: Icons.volume_up_rounded,
            variant: UbanButtonVariant.tonal,
            onPressed: onListen,
          ),
          const SizedBox(height: 10),
        ],
        UbanButton(
          key: const ValueKey('daily_question_answer'),
          label: '我來回答',
          icon: Icons.mic_rounded,
          size: UbanButtonSize.xl,
          onPressed: onAnswer,
        ),
      ];

  List<Widget> _answered(UbanColors c) {
    final snippet = question.answerText ??
        (question.hasAnswerAudio ? '（您錄了一段聲音）' : null);
    return [
      Text(
        '今天已經回答了，家人會看到喔',
        key: const ValueKey('daily_question_done'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ubanText(22, FontWeight.w800, c.brandStrong, height: 1.4),
      ),
      if (snippet != null) ...[
        const SizedBox(height: 8),
        Text(
          snippet,
          key: const ValueKey('daily_question_snippet'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: ubanText(20, FontWeight.w600, c.text2, height: 1.4),
        ),
      ],
      const SizedBox(height: 12),
      UbanButton(
        key: const ValueKey('daily_question_edit'),
        label: '改一下',
        icon: Icons.edit_rounded,
        variant: UbanButtonVariant.outline,
        onPressed: onAnswer,
      ),
    ];
  }
}
