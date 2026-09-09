import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ★ 第四十一輪（item 3）：「我的」介面顯示自己的朋友圈好友 ID（4 位數 elder_id）
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF59B294).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_rounded,
                    color: Color(0xFF59B294), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '我的好友 ID',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (myFriendElderId != null)
            Text(
              myFriendElderId!,
              style: GoogleFonts.inter(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF2E7D78),
                letterSpacing: 6,
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
                Text(
                  '載入中…',
                  style: GoogleFonts.notoSansTc(
                      fontSize: 15, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Text(
            '把這組號碼給朋友，就能加你為好友',
            style: GoogleFonts.notoSansTc(
              fontSize: 13.5,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
