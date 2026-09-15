import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../theme/app_theme.dart';

/// ★ 第四十一輪（item 3）：顯示自己的朋友圈好友 ID（4 位數 elder_id）。
/// ★ 任務 C：從長輩「我的」分頁搬到「社群 → 朋友」標籤上方——文案語境本就
///   屬於朋友圈，且與社群頁的 AppColors 配色一致；配色改用主題常數後視覺
///   結果不變（僅色碼來源改變）。搬到朋友動態上方後尺寸略縮小，避免擠壓
///   動態清單的空間。
class FriendIdCard extends StatelessWidget {
  final String? myFriendElderId;

  const FriendIdCard({
    super.key,
    required this.myFriendElderId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '我的好友 ID',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (myFriendElderId != null)
            Text(
              myFriendElderId!,
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryDark,
                letterSpacing: 5,
              ),
            )
          else
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  '載入中…',
                  style: GoogleFonts.notoSansTc(
                      fontSize: 14, color: AppColors.textHint),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            '把這組號碼給朋友，就能加你為好友',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(
              fontSize: 12.5,
              color: AppColors.textHint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
