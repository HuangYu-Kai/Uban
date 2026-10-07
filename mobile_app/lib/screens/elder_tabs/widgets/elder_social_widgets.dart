import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';
import '../../widgets/friend_avatar.dart';

/// 長輩端「朋友圈／加好友／家庭時光牆」共用的小元件（設計稿 `.post`、`.pacts`、`.cm`、
/// `.photo-add`、`.avatar`）。
///
/// 全部是純展示：點擊行為由呼叫端傳入，這裡不碰 service／API／SharedPreferences。
/// 顏色一律走 [UbanColors.of]——家屬端把時光牆包在 `FamilyThemeScope` 下時會自動換成
/// 海灣藍。字級採長輩尺度（內文 ≥18、貼文 20）。

/// 頭像色調（設計稿 `.avatar`／`.avatar.warm`／`.avatar.info`）。
enum ElderAvatarTone { brand, warm, info }

/// 設計稿 `.avatar`：圓形、姓名字首 900 粗、色調容器底。
class ElderInitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final ElderAvatarTone tone;

  const ElderInitialAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.tone = ElderAvatarTone.brand,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final Color bg, fg;
    switch (tone) {
      case ElderAvatarTone.brand:
        bg = c.brandContainer;
        fg = c.brandStrong;
      case ElderAvatarTone.warm:
        bg = c.warmContainer;
        fg = c.warm;
      case ElderAvatarTone.info:
        bg = c.infoContainer;
        fg = c.info;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '友' : name.substring(0, 1),
        style: ubanText(size * .43, FontWeight.w900, fg),
      ),
    );
  }
}

/// 設計稿 `.tag`／`.badge` 的小膠囊。
class ElderTagPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final double fontSize;

  const ElderTagPill({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ubanText(fontSize, FontWeight.w700, fg),
      ),
    );
  }
}

/// 設計稿 `.pacts`：讚／留言兩顆等寬大鈕（高 56、圓角 18、surface2 底；已讚時 danger 色）。
///
/// 兩顆鈕各自可掛 [likeKey]／[commentKey]（新手指引高光目標）。
class ElderPostActions extends StatelessWidget {
  final bool liked;
  final String likeLabel;
  final String commentLabel;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final Key? likeKey;
  final Key? commentKey;

  /// 按讚時讓讚鈕彈一下的縮放動畫（時光牆的讚動畫）；null 不縮放。
  final Animation<double>? likeScale;

  const ElderPostActions({
    super.key,
    required this.liked,
    required this.likeLabel,
    required this.commentLabel,
    required this.onLike,
    required this.onComment,
    this.likeKey,
    this.commentKey,
    this.likeScale,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final likeBtn = _ActButton(
      key: likeKey,
      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: likeLabel,
      bg: liked ? c.dangerContainer : c.surface2,
      fg: liked ? c.danger : c.text,
      onTap: onLike,
    );
    return Row(
      children: [
        Expanded(
          child: likeScale == null
              ? likeBtn
              : ScaleTransition(scale: likeScale!, child: likeBtn),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActButton(
            key: commentKey,
            icon: Icons.mode_comment_outlined,
            label: commentLabel,
            bg: c.surface2,
            fg: c.text,
            onTap: onComment,
          ),
        ),
      ],
    );
  }
}

class _ActButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _ActButton({
    super.key,
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: BlobRipple(
          color: c.brand.withValues(alpha: .22),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: radius),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(18, FontWeight.w700, fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 設計稿 `.cm`：留言泡泡（brandSoft 底、圓角 18、名字 15/700 brandStrong、內文 18）。
class ElderCommentTile extends StatelessWidget {
  final String name;
  final String message;

  /// 名字右側的小徽章（例如「家人」）；null 不顯示。
  final String? badge;
  final bool badgeIsFamily;
  final String? timeText;
  final Widget? image;

  const ElderCommentTile({
    super.key,
    required this.name,
    required this.message,
    this.badge,
    this.badgeIsFamily = false,
    this.timeText,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 名字長度不可控（家人／長輩顯示名稱），同列還有徽章與時間，故可收縮。
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(15, FontWeight.w700, c.brandStrong),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                ElderTagPill(
                  label: badge!,
                  bg: badgeIsFamily ? c.infoContainer : c.surface,
                  fg: badgeIsFamily ? c.info : c.brandStrong,
                  fontSize: 13,
                ),
              ],
              if (timeText != null) ...[
                const Spacer(),
                const SizedBox(width: 8),
                Text(timeText!, style: ubanText(14, FontWeight.w500, c.text3)),
              ],
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(message,
                style: ubanText(18, FontWeight.w500, c.text, height: 1.5)),
          ],
          if (image != null) ...[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(14), child: image!),
          ],
        ],
      ),
    );
  }
}

/// 設計稿 `.photo-add`：虛線框、高 ≥56、圓角 18。
class ElderPhotoAddButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData icon;

  const ElderPhotoAddButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_photo_alternate_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: PressableScale(
          enabled: onTap != null,
          onTap: onTap,
          child: BlobRipple(
            enabled: onTap != null,
            color: c.brand.withValues(alpha: .22),
            borderRadius: radius,
            child: CustomPaint(
              painter: _DashedRRectPainter(color: c.line, radius: 18),
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: c.text2),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: ubanText(17, FontWeight.w700, c.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// 空狀態卡：大圖示＋一句話（長輩字級 18）。
class ElderEmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const ElderEmptyCard({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return UbanCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration:
                BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 42, color: c.brandStrong),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: ubanText(18, FontWeight.w500, c.text2, height: 1.55),
          ),
        ],
      ),
    );
  }
}

/// 載入失敗區塊：圖示＋訊息＋「重試」按鈕（高 60）。
class ElderErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ElderErrorBlock(
      {super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration:
                  BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(Icons.wifi_off_rounded, size: 42, color: c.text3),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ubanText(18, FontWeight.w500, c.text2, height: 1.55),
            ),
            const SizedBox(height: 18),
            UbanButton(
              label: '重試',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// 提示條（錯誤用 danger 色、一般訊息用 brand 色）。
class ElderNoticeBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const ElderNoticeBanner(
      {super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final bg = isError ? c.dangerContainer : c.brandContainer;
    final fg = isError ? c.danger : c.brandStrong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Icon(
              isError
                  ? Icons.info_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: fg,
              size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: ubanText(18, FontWeight.w700, fg, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// 貼文圖片：載入中轉圈、失敗顯示提示（設計稿 `.pimg`：圓角 18）。
class ElderPostPhoto extends StatelessWidget {
  final String url;
  final double height;

  const ElderPostPhoto({super.key, required this.url, this.height = 220});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        url,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            color: c.surface2,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: 150,
          color: c.surface2,
          alignment: Alignment.center,
          child: Text('圖片載入失敗', style: ubanText(16, FontWeight.w500, c.text3)),
        ),
      ),
    );
  }
}

/// 朋友圈單則貼文（設計稿 `.card.post`）：頭像＋名字＋時間、內文 20、圖片、讚／留言。
class ElderFriendPostCard extends StatelessWidget {
  final String authorName;
  final String? avatarUrl;
  final String timeText;
  final String content;

  /// 已解析好的圖片絕對網址（空字串或 null 代表沒有圖）。
  final String? imageUrl;
  final int likeCount;
  final bool isLiked;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const ElderFriendPostCard({
    super.key,
    required this.authorName,
    required this.avatarUrl,
    required this.timeText,
    required this.content,
    required this.imageUrl,
    required this.likeCount,
    required this.isLiked,
    required this.commentCount,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return UbanCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(avatarUrl: avatarUrl, name: authorName, radius: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(20, FontWeight.w900, c.text),
                    ),
                    if (timeText.isNotEmpty)
                      Text(timeText,
                          style: ubanText(14, FontWeight.w500, c.text3)),
                  ],
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(content,
                style: ubanText(20, FontWeight.w500, c.text, height: 1.6)),
          ],
          if (imageUrl != null && imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ElderPostPhoto(url: imageUrl!),
          ],
          const SizedBox(height: 14),
          ElderPostActions(
            liked: isLiked,
            likeLabel: '讚 $likeCount',
            commentLabel: '留言 $commentCount',
            onLike: onLike,
            onComment: onComment,
          ),
        ],
      ),
    );
  }
}
