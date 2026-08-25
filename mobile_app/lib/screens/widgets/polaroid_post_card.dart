import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/community_post.dart';

class PolaroidPostCard extends StatefulWidget {
  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onCallFamily;

  const PolaroidPostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    this.onCallFamily,
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
      curve: Curves.easeInOutBack,
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

  Widget _buildStampBadge(String? stampType) {
    if (stampType == null || stampType.isEmpty) return const SizedBox.shrink();

    String icon = '🐾';
    String label = '散步打卡';
    Color color = const Color(0xFF166534);
    Color bg = const Color(0xFFDCFCE7);

    switch (stampType) {
      case 'walk':
        icon = '🐾';
        label = '散步打卡';
        color = const Color(0xFF166534);
        bg = const Color(0xFFDCFCE7);
        break;
      case 'tea':
        icon = '🍵';
        label = '喝茶報平安';
        color = const Color(0xFF854D0E);
        bg = const Color(0xFFFEF9C3);
        break;
      case 'sun':
        icon = '☀️';
        label = '早安問候';
        color = const Color(0xFFC2410C);
        bg = const Color(0xFFFFEDD5);
        break;
      case 'flower':
        icon = '🌸';
        label = '平安喜樂';
        color = const Color(0xFF9D174D);
        bg = const Color(0xFFFCE7F3);
        break;
      case 'food':
        icon = '🍚';
        label = '吃飽飽';
        color = const Color(0xFF1E3A8A);
        bg = const Color(0xFFDBEAFE);
        break;
      case 'energy':
        icon = '💪';
        label = '活力滿滿';
        color = const Color(0xFF065F46);
        bg = const Color(0xFFD1FAE5);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoView(String imagePath) {
    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
        ),
      );
    }
    return Image.file(
      File(imagePath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inMinutes < 60) return ' 分鐘前';
    if (diff.inHours < 24) return ' 小時前';
    return ' 天前';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isFamily = post.authorRole == 'family';
    final hasPhoto =
        (post.imageUrl != null && post.imageUrl!.isNotEmpty) ||
        (post.imagePath != null && post.imagePath!.isNotEmpty);
    final photoPath = post.imageUrl ?? post.imagePath ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF55B695).withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部拍立得手寫風格 Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                // 大頭貼
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isFamily
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFDFFFF4),
                  child: Text(
                    post.authorName.isEmpty
                        ? '友'
                        : post.authorName.substring(0, 1),
                    style: GoogleFonts.notoSansTc(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isFamily
                          ? const Color(0xFF166534)
                          : const Color(0xFF0D9488),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post.authorName,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isFamily
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isFamily ? '家人 💖' : '長輩 🌿',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isFamily
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(post.createdAt),
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                // 心情表情與印章
                _buildStampBadge(post.stampType),
                const SizedBox(width: 8),
                Text(post.mood, style: const TextStyle(fontSize: 34)),
              ],
            ),
          ),

          // 拍立得相框照片（若有）
          if (hasPhoto) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                ),
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 240,
                    width: double.infinity,
                    child: _buildPhotoView(photoPath),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 貼文文字內容（生活便簽質感）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              post.content,
              style: GoogleFonts.notoSansTc(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
                height: 1.45,
              ),
            ),
          ),

          // 語音朗讀 TTS 按鈕卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: _toggleSpeech,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isSpeaking
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isSpeaking
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFE2E8F0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSpeaking
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      color: _isSpeaking
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSpeaking ? '正在為您朗讀中... (點擊停止)' : '🔊 點我朗讀貼文與留言',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _isSpeaking
                            ? const Color(0xFFB45309)
                            : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 留言預覽
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFBBF7D0),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${post.comments.last.authorName}：${post.comments.last.message}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 底部互動按鈕列（爪印按讚 / 留言 / 撥打電話）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                // 關心 (爪印/愛心按讚)
                Expanded(
                  child: GestureDetector(
                    onTap: _handleLikeTap,
                    behavior: HitTestBehavior.opaque,
                    child: ScaleTransition(
                      scale: _stampScaleAnimation,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: post.isLiked
                              ? const Color(0xFFFFF1F2)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: post.isLiked
                                ? const Color(0xFFFDA4AF)
                                : const Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              post.isLiked ? '🐾' : '🤍',
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              post.likeCount == 0
                                  ? '送爪印'
                                  : '${post.likeCount} 爪印',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: post.isLiked
                                    ? const Color(0xFFE11D48)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 留言按鈕
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onComment,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFBBF7D0),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded,
                              size: 24, color: Color(0xFF166534)),
                          const SizedBox(width: 6),
                          Text(
                            post.comments.isEmpty
                                ? '留言'
                                : ' 留言',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
