import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/alert_display.dart';
import 'fam_ui.dart';

/// 警報卡片上的「情境摘要」與「長輩回覆」標籤（警示中心即時／歷史卡片共用）。
///
/// 兩項都是選填：[summary] 為 `null` 不顯示摘要，[response] 為 `null` 不顯示標籤；
/// 兩者都沒有時整個 widget 縮成 [SizedBox.shrink]，卡片外觀與改版前完全相同。
///
/// 鐵律 #14：摘要與長輩原話都用可換行的 [Text]（放在 Column 內由父層給寬度），
/// 標籤放進 [Wrap]，窄螢幕只會換行，不會 RenderFlex 溢位。
class AlertAgentSummary extends StatelessWidget {
  final String? summary;
  final ElderResponseInfo? response;

  const AlertAgentSummary({super.key, this.summary, this.response});

  @override
  Widget build(BuildContext context) {
    final String? s = summary;
    final ElderResponseInfo? r = response;
    if (s == null && r == null) return const SizedBox.shrink();
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s != null)
            Text(s, style: famText(c.text2, 12.5, height: 1.45)),
          if (r != null) ...[
            if (s != null) const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FamChip(
                  label: r.label,
                  tone: r.needHelp ? FamTone.danger : FamTone.brand,
                  dot: true,
                ),
                if (r.text != null)
                  // Wrap 給子元件的是「最大寬度＝Wrap 寬度」的鬆散約束，長句會自動換行。
                  Text('「${r.text}」',
                      style: famText(c.text2, 12.5, height: 1.4)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
