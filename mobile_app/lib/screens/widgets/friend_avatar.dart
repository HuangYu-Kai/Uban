import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

/// 朋友圈共用的頭像顯示元件（第四十一輪 item 3）。
///
/// `avatarUrl` 可能是相對路徑（後端 `friend.py::_avatar_url_for_user` 回傳的
/// `/api/user/{id}/avatar`）或已組好的絕對網址（朋友貼文圖片經
/// `ApiService.uploadCommunityImage` 上傳後就是絕對網址）；統一在這裡補上
/// `serverRootUrl` 前綴，避免每個畫面各寫一份判斷邏輯。
///
/// 沒有網址或圖片載入失敗時，退回姓名字首圓形色塊——與
/// `friends_screen.dart` 既有的家人卡片頭像樣式一致。
class FriendAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;

  const FriendAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.radius = 28,
  });

  /// 把可能是相對路徑的圖片網址補成可直接請求的絕對網址。
  static String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${ApiService.serverRootUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final resolved = (url != null && url.isNotEmpty) ? resolveUrl(url) : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      backgroundImage: resolved != null ? NetworkImage(resolved) : null,
      onBackgroundImageError: resolved != null ? (_, __) {} : null,
      child: resolved == null
          ? Text(
              name.isNotEmpty ? name.substring(0, 1) : '友',
              style: GoogleFonts.notoSansTc(
                fontSize: radius * 0.75,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryDark,
              ),
            )
          : null,
    );
  }
}
