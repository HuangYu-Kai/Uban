import 'package:flutter/material.dart';

import '../../../../widgets/ui/ui.dart';

/// ★ 第四十一輪（item 3）：顯示自己的朋友圈好友 ID（4 位數 elder_id）。
/// ★ 任務 C：從長輩「我的」分頁搬到「社群 → 朋友」標籤上方。
/// 2026-10 新設計：UbanCard＋圓形圖示＋Poppins 大字 ID（設計稿 `.bigid` 縮小版，
/// 尺寸略縮以免擠壓下方動態清單）。顏色走 [UbanColors.of]，長輩端為品牌綠。
class FriendIdCard extends StatelessWidget {
  final String? myFriendElderId;

  const FriendIdCard({
    super.key,
    required this.myFriendElderId,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: UbanCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(color: c.brandContainer, shape: BoxShape.circle),
              child: Icon(Icons.badge_rounded, color: c.brandStrong, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的好友 ID',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(16, FontWeight.w700, c.text2),
                  ),
                  const SizedBox(height: 2),
                  if (myFriendElderId != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        myFriendElderId!,
                        maxLines: 1,
                        style: ubanBrandText(34, FontWeight.w600, c.text,
                                height: 1.2)
                            .copyWith(letterSpacing: 34 * .18),
                      ),
                    )
                  else
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text('載入中…',
                            style: ubanText(18, FontWeight.w500, c.text3)),
                      ],
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '把這組號碼給朋友，就能加你為好友',
                    style: ubanText(16, FontWeight.w500, c.text2, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
