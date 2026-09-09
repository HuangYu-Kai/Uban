import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 長輩個人頁快捷功能卡片（家人綁定、語音助理、切換身分等）
class ProfileActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isLandscape;

  const ProfileActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFDF9),
      borderRadius: BorderRadius.circular(isLandscape ? 16 : 24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isLandscape ? 16 : 24),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 10 : 16,
            vertical: isLandscape ? 7 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isLandscape ? 16 : 24),
            border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF78350F).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isLandscape ? 6 : 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: isLandscape ? 18 : 26),
              ),
              SizedBox(width: isLandscape ? 6 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 13.5 : 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isLandscape ? 1 : 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 11 : 13.5,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: isLandscape ? 11 : 15,
                color: const Color(0xFFD4C5B9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
