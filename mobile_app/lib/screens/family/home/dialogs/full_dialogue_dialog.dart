import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/ui/uban_dialog.dart';
import '../../widgets/fam_ui.dart';

/// 顯示 AI 語音陪伴對話紀錄彈窗（設計稿 `.dialog`：圓角 32、surface 底、內文不放圖示）。
void showFullDialogueDialog(BuildContext context, String query, String ai, String timeStr) {
  showDialog(
    context: context,
    barrierColor: UbanColors.of(context).scrim,
    builder: (dialogContext) {
      final c = UbanColors.of(dialogContext);
      return UbanDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AI 語音陪伴對話紀錄 ($timeStr)',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text, 18, weight: FontWeight.w900, height: 1.35),
            ),
            const SizedBox(height: 14),
            Text('長輩提問', style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(query, style: famText(c.text, 15, height: 1.5)),
            ),
            const SizedBox(height: 14),
            Text('AI 小嘎回報與陪伴', style: famText(c.text3, 13, weight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(ai, style: famText(c.text, 15, height: 1.5)),
            ),
            const SizedBox(height: 16),
            FamButton(
              label: '關閉',
              kind: FamButtonKind.tonal,
              height: 48,
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      );
    },
  );
}
