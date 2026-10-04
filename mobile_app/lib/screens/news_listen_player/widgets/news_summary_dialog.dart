import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../widgets/ui/ui.dart';

/// 「重點整理」對話框（設計稿 `#dl-summary`）：小豬＋標題＋整理內容＋「我知道了」。
class NewsSummaryDialog extends StatelessWidget {
  final String summaryText;
  final VoidCallback onClose;

  const NewsSummaryDialog({
    super.key,
    required this.summaryText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return UbanDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/pig_summary_expert.png',
                width: 72,
                height: 72,
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.06, 1.06),
                      duration: 1.2.seconds,
                      curve: Curves.easeInOut),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '總結專家小豬',
                  style: ubanText(24, FontWeight.w900, c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summaryText,
            style: ubanText(20, FontWeight.w500, c.text, height: 1.6),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 20),
          UbanButton(label: '我知道了', onPressed: onClose),
        ],
      ),
    );
  }
}
