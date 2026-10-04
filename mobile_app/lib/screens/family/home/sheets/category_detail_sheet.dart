import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/fam_ui.dart';
import '../models/activity_log_entry.dart';
import '../dialogs/full_dialogue_dialog.dart';

/// 顯示單一主題分類詳細動態清單 BottomSheet（設計稿 `.sheet`＋`.fitem`）。
///
/// 外觀：面板 surface、圓角 32、左右下 inset 8、grab 44×5；每筆紀錄為 surface2 區塊，
/// 不放分類圖示與分類色（分類以文字標示）。
void showCategoryDetailModal(
  BuildContext context, {
  required String categoryTitle,
  required List<Map<String, dynamic>> items,
}) {
  final cs = Theme.of(context).colorScheme;
  final c0 = UbanColors.of(context);

  final cleanTitle = categoryTitle.replaceAll(RegExp(r'^[^\w一-龥]+'), '').trim();
  final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : categoryTitle;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: c0.scrim,
    builder: (sheetContext) {
      final c = UbanColors.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 14),
                decoration: BoxDecoration(
                  color: c.surface3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    // ★ 鐵律 #14：標題可收縮；關閉鈕固定在右側。
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text, 19, weight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共 ${items.length} 筆$displayTitle詳細紀錄',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: famText(c.text2, 13.5, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FamMore(label: '關閉', onTap: () => Navigator.pop(sheetContext)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          '尚無該主題分類的新紀錄',
                          style: famText(c.text2, 15),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final parsed = ActivityLogParser.parseActivityLogItem(item, cs);
                          final isChat = parsed.isChat || item['isChat'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${parsed.categoryTag}・${parsed.statusText}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: famText(c.text3, 12.5, weight: FontWeight.w700),
                                      ),
                                    ),
                                    if (parsed.timeText.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        parsed.timeText,
                                        maxLines: 1,
                                        style: famText(c.text2, 13,
                                            weight: FontWeight.w600, tabular: true),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  parsed.title,
                                  style: famText(c.text, 16, weight: FontWeight.w700, height: 1.4),
                                ),
                                if (parsed.subtitle != null && parsed.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    parsed.subtitle!,
                                    style: famText(c.text2, 13.5, height: 1.45),
                                  ),
                                ],
                                if (isChat && (parsed.fullQuery.isNotEmpty || item['fullQuery'] != null)) ...[
                                  const SizedBox(height: 10),
                                  FamButton(
                                    label: '展開檢視完整對話逐字稿',
                                    kind: FamButtonKind.tonal,
                                    height: 44,
                                    expand: false,
                                    onPressed: () {
                                      showFullDialogueDialog(
                                        context,
                                        parsed.fullQuery.isNotEmpty ? parsed.fullQuery : (item['fullQuery'] as String? ?? ''),
                                        parsed.fullAi.isNotEmpty ? parsed.fullAi : (item['fullAi'] as String? ?? ''),
                                        parsed.timeText.isNotEmpty ? parsed.timeText : (item['time'] as String? ?? ''),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
