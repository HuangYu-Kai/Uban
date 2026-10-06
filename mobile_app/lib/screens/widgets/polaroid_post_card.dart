import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/community_post.dart';
import '../../widgets/ui/ui.dart';
import '../elder_tabs/widgets/elder_social_widgets.dart';

/// 家庭生活時光牆的單則貼文（設計稿 post 卡片，2026-10 新設計）。
///
/// 長輩與家屬共用：顏色一律走 UbanColors.of（家屬端外層有 FamilyThemeScope 時自動變海灣藍）；
/// 字級採長輩尺度（內文 20、按鈕 56）。TTS 朗讀、按讚動畫、新手指引 key 全部沿用。
class PolaroidPostCard extends StatefulWidget {
  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onCallFamily;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，選填。由
  //   elder_community_screen.dart 只在第一則貼文傳入，其餘呼叫端不傳、
  //   維持 null，完全不影響現有畫面。
  final GlobalKey? likeButtonKey;
  final GlobalKey? commentButtonKey;

  const PolaroidPostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    this.onCallFamily,
    this.likeButtonKey,
    this.commentButtonKey,
  });

  @override
  State<PolaroidPostCard> createState() => _PolaroidPostCardState();
}

class _PolaroidPostCardState extends State<PolaroidPostCard>
    with SingleTickerProviderStateMixin {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  late AnimationController _stampController;
  late Animation<double> _stampScaleAnimation;

  @override
  void initState() {
    super.initState();
    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _stampScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _stampController,
      // 不可用 easeInOutBack 這類會超出 0～1 的曲線：TweenSequence 會在每一幀丟斷言，
      // 元素樹因此錯亂（爪印按鈕變兩顆、離開社群後紅畫面 _dependents.isEmpty）。
      // 彈跳感已由上面 1.0→1.4→1.0 的序列提供。
      curve: Curves.easeInOut,
    ));

    _initTts();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setSpeechRate(0.42); // 適老放慢語速
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });

    _flutterTts.setErrorHandler((msg) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _stampController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  /// 「誰送了爪印」一行字：≤3 人列全名，超過則「A、B、C 等 N 人」。
  String _likedByLine() {
    final names = widget.post.likedBy;
    if (names.length <= 3) return '🐾 ${names.join('、')} 送了爪印';
    final total = names.length > widget.post.likeCount
        ? names.length
        : widget.post.likeCount;
    return '🐾 ${names.take(3).join('、')} 等 $total 人送了爪印';
  }

  Future<void> _toggleSpeech() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      final roleText =
          widget.post.authorRole == 'family' ? '家人' : '長輩';
      final commentsText = widget.post.comments.isNotEmpty
          ? '，最新留言：${widget.post.comments.last.authorName} 說：${widget.post.comments.last.message}'
          : '';
      final textToRead =
          '$roleText ${widget.post.authorName} 說：${widget.post.content}$commentsText';
      await _flutterTts.speak(textToRead);
    }
  }

  void _handleLikeTap() {
    _stampController.forward(from: 0.0);
    widget.onLike();
  }

  /// 印章 → 徽章配色（用設計系統語意色，淺深色與家屬主題都適用）。
  Widget _buildStampBadge(UbanColors c, String? stampType) {
    if (stampType == null || stampType.isEmpty) return const SizedBox.shrink();

    String icon = '🐾';
    String label = '散步打卡';
    Color bg = c.brandContainer;
    Color fg = c.brandStrong;

    switch (stampType) {
      case 'walk':
        break;
      case 'tea':
        icon = '🍵';
        label = '喝茶報平安';
        bg = c.warmContainer;
        fg = c.warm;
      case 'sun':
        icon = '☀️';
        label = '早安問候';
        bg = c.warmContainer;
        fg = c.warm;
      case 'flower':
        icon = '🌸';
        label = '平安喜樂';
        bg = c.dangerContainer;
        fg = c.danger;
      case 'food':
        icon = '🍚';
        label = '吃飽飽';
        bg = c.infoContainer;
        fg = c.info;
      case 'energy':
        icon = '💪';
        label = '活力滿滿';
    }

    return ElderTagPill(label: '$icon $label', bg: bg, fg: fg, fontSize: 15);
  }

  Widget _buildPhotoView(UbanColors c, String imagePath) {
    Widget broken() => Container(
          color: c.surface2,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_rounded, size: 48, color: c.text3),
        );
    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => broken(),
      );
    }
    return Image.file(
      File(imagePath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => broken(),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final post = widget.post;
    final isFamily = post.authorRole == 'family';
    final hasPhoto = (post.imageUrl != null && post.imageUrl!.isNotEmpty) ||
        (post.imagePath != null && post.imagePath!.isNotEmpty);
    final photoPath = post.imageUrl ?? post.imagePath ?? '';
    final hasStamp = post.stampType != null && post.stampType!.isNotEmpty;
    final lastComment = post.comments.isEmpty ? null : post.comments.last;

    return UbanCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頭像＋名字＋身分＋時間＋心情
          Row(
            children: [
              ElderInitialAvatar(
                name: post.authorName,
                tone: isFamily ? ElderAvatarTone.info : ElderAvatarTone.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(20, FontWeight.w900, c.text),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElderTagPill(
                          label: isFamily ? '家人' : '長輩',
                          bg: isFamily ? c.infoContainer : c.brandContainer,
                          fg: isFamily ? c.info : c.brandStrong,
                          fontSize: 13,
                        ),
                        Text(
                          _formatTime(post.createdAt),
                          style: ubanText(14, FontWeight.w500, c.text3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(post.mood, style: const TextStyle(fontSize: 32)),
            ],
          ),

          if (hasStamp) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildStampBadge(c, post.stampType),
            ),
          ],

          // 照片（若有）
          if (hasPhoto) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: _buildPhotoView(c, photoPath),
              ),
            ),
          ],

          // 貼文文字（設計稿 `.post .content`：20、行高 1.6）
          const SizedBox(height: 12),
          Text(
            post.content,
            style: ubanText(20, FontWeight.w500, c.text, height: 1.6),
          ),

          // 語音朗讀（TTS）
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: _isSpeaking ? '停止朗讀' : '朗讀貼文與留言',
            excludeSemantics: true,
            child: PressableScale(
              onTap: _toggleSpeech,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isSpeaking ? c.warmContainer : c.surface2,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSpeaking
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      color: _isSpeaking ? c.warm : c.text2,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isSpeaking ? '正在為您朗讀中⋯（點一下停止）' : '點我朗讀貼文與留言',
                        style: ubanText(
                          18,
                          FontWeight.w700,
                          _isSpeaking ? c.warm : c.text2,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 誰送了爪印（鐵律 #14：最多 2 行並截斷）
          if (post.likedBy.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _likedByLine(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ubanText(16, FontWeight.w600, c.text2),
            ),
          ],

          // 最新一則留言預覽
          if (lastComment != null) ...[
            const SizedBox(height: 12),
            ElderCommentTile(
              name: lastComment.authorName,
              message: lastComment.message,
            ),
          ],

          // 讚（爪印）／留言
          const SizedBox(height: 14),
          ElderPostActions(
            liked: post.isLiked,
            likeLabel: post.likeCount == 0 ? '送爪印' : '${post.likeCount} 爪印',
            commentLabel:
                post.comments.isEmpty ? '留言' : '留言 ${post.comments.length}',
            onLike: _handleLikeTap,
            onComment: widget.onComment,
            likeKey: widget.likeButtonKey,
            commentKey: widget.commentButtonKey,
            likeScale: _stampScaleAnimation,
          ),
        ],
      ),
    );
  }
}
