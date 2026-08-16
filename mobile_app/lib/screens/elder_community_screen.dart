import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/community_post.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';

class ElderCommunityScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderCommunityScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderCommunityScreen> createState() => _ElderCommunityScreenState();
}

class _ElderCommunityScreenState extends State<ElderCommunityScreen> {
  final CommunityService _communityService = CommunityService();
  final TextEditingController _postController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  List<CommunityPost> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _communityService.initialize();
    await _loadPosts();
  }

  Future<void> _loadPosts() async {
    final posts = await _communityService.getPosts(
      userId: widget.userId,
      userName: widget.userName,
    );
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _isLoading = false;
    });
  }

  Future<void> _toggleLike(CommunityPost post) async {
    HapticFeedback.mediumImpact();
    final posts = await _communityService.toggleLike(
      userId: widget.userId,
      userName: widget.userName,
      postId: post.id,
    );
    if (mounted) setState(() => _posts = posts);
  }

  Future<void> _showCreatePostSheet() async {
    final controller = _postController..clear();
    String selectedMood = '😊';
    const quickMessages = [
      '今天心情很好！',
      '大家早安，祝平安健康。',
      '剛剛出去走一走，很舒服。',
    ];

    final shouldPublish = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('分享近況', style: ElderScale.sectionTitle),
                    const SizedBox(height: 8),
                    Text('只有家人與認識的朋友看得到', style: ElderScale.caption),
                    const SizedBox(height: 20),
                    Text('今天心情', style: ElderScale.body),
                    const SizedBox(height: 10),
                    Row(
                      children: ['😊', '❤️', '🌼', '👍'].map((mood) {
                        final isSelected = selectedMood == mood;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () => setSheetState(
                                () => selectedMood = mood,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                height: 64,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryLight
                                      : AppColors.background,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.border,
                                    width: 2,
                                  ),
                                ),
                                child: Text(mood,
                                    style: const TextStyle(fontSize: 32)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Text('快速選一句', style: ElderScale.body),
                    const SizedBox(height: 8),
                    ...quickMessages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () {
                            controller.text = message;
                            controller.selection = TextSelection.collapsed(
                              offset: controller.text.length,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(
                                color: AppColors.border, width: 2),
                            padding: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(message, style: ElderScale.caption),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 120,
                      style: ElderScale.body,
                      decoration: InputDecoration(
                        hintText: '也可以自己輸入想說的話',
                        hintStyle: ElderScale.caption,
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: ElderScale.buttonHeight,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (controller.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('請先選一句或輸入內容')),
                            );
                            return;
                          }
                          Navigator.pop(sheetContext, true);
                        },
                        icon: const Icon(Icons.send_rounded, size: 32),
                        label: Text('發佈近況', style: ElderScale.button),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldPublish == true && controller.text.trim().isNotEmpty) {
      final posts = await _communityService.createPost(
        userId: widget.userId,
        userName: widget.userName,
        content: controller.text,
        mood: selectedMood,
      );
      if (!mounted) return;
      setState(() => _posts = posts);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('近況已分享給家人與朋友')),
      );
    }
  }

  Future<void> _showComments(CommunityPost post) async {
    final controller = _commentController..clear();
    const quickReplies = ['真好！', '保重身體喔', '改天一起聊聊'];
    String? selectedImagePath;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final latestPost = _posts.firstWhere(
              (item) => item.id == post.id,
              orElse: () => post,
            );
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.82,
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('留言', style: ElderScale.sectionTitle),
                  const SizedBox(height: 12),
                  if (latestPost.comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('還沒有留言，來關心一下吧！', style: ElderScale.caption),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: latestPost.comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final comment = latestPost.comments[index];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  comment.authorName,
                                  style: ElderScale.caption.copyWith(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (comment.message.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    comment.message,
                                    style: ElderScale.caption.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                                if (comment.imagePath != null) ...[
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.file(
                                      File(comment.imagePath!),
                                      height: 180,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 90,
                                        alignment: Alignment.center,
                                        color: AppColors.background,
                                        child: Text(
                                          '圖片無法顯示',
                                          style: ElderScale.caption,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickReplies
                        .map(
                          (reply) => ActionChip(
                            label: Text(reply, style: ElderScale.caption),
                            onPressed: () {
                              controller.text = reply;
                              controller.selection = TextSelection.collapsed(
                                offset: controller.text.length,
                              );
                              setSheetState(() {});
                            },
                            backgroundColor: AppColors.background,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.all(10),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (selectedImagePath != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(
                            File(selectedImagePath!),
                            width: double.infinity,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: '移除圖片',
                              onPressed: () async {
                                final imageFile = File(selectedImagePath!);
                                if (await imageFile.exists()) {
                                  await imageFile.delete();
                                }
                                setSheetState(() => selectedImagePath = null);
                              },
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: controller,
                    style: ElderScale.body,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 120,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: '寫下想說的話⋯⋯',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: selectedImagePath == null
                              ? () async {
                                  final pickedPath =
                                      await _pickAndStoreCommentImage();
                                  if (!context.mounted || pickedPath == null) {
                                    return;
                                  }
                                  setSheetState(
                                    () => selectedImagePath = pickedPath,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.add_photo_alternate_rounded,
                              size: 30),
                          label: Text(
                            selectedImagePath == null ? '加入圖片' : '已加入圖片',
                            style: ElderScale.caption,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(64),
                            foregroundColor: AppColors.primaryDark,
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: controller.text.trim().isEmpty &&
                                  selectedImagePath == null
                              ? null
                              : () async {
                                  final imagePath = selectedImagePath;
                                  final posts =
                                      await _communityService.addComment(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                    postId: post.id,
                                    message: controller.text,
                                    imagePath: imagePath,
                                  );
                                  if (!mounted) return;
                                  setState(() => _posts = posts);
                                  controller.clear();
                                  setSheetState(
                                    () => selectedImagePath = null,
                                  );
                                },
                          icon: const Icon(Icons.send_rounded, size: 30),
                          label: Text('送出', style: ElderScale.caption),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(64),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selectedImagePath != null) {
      final unusedImage = File(selectedImagePath!);
      if (await unusedImage.exists()) await unusedImage.delete();
    }
  }

  Future<String?> _pickAndStoreCommentImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (pickedImage == null) return null;

      final documentsDirectory = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory(
        path.join(documentsDirectory.path, 'community_comment_images'),
      );
      await imageDirectory.create(recursive: true);

      final extension = path.extension(pickedImage.path);
      final storedPath = path.join(
        imageDirectory.path,
        'comment-${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      await File(pickedImage.path).copy(storedPath);
      return storedPath;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法讀取圖片，請稍後再試')),
        );
      }
      return null;
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDE6DE),
      appBar: AppBar(
        toolbarHeight: 80,
        title: Text(
          '社群',
          style: GoogleFonts.notoSansTc(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadPosts,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
                  children: [
                    _buildPrivacyCard(),
                    const SizedBox(height: 14),
                    _buildCreatePostButton(),
                    const SizedBox(height: 18),
                    Text('大家的近況', style: ElderScale.sectionTitle),
                    const SizedBox(height: 12),
                    if (_posts.isEmpty) _buildEmptyState(),
                    ..._posts.map(_buildPostCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPrivacyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(ElderScale.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: Colors.white, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '這裡只有家人和認識的朋友',
              style: ElderScale.caption.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePostButton() {
    return SizedBox(
      height: ElderScale.buttonHeight,
      child: ElevatedButton.icon(
        onPressed: _showCreatePostSheet,
        icon: const Icon(Icons.add_circle_rounded, size: ElderScale.buttonIcon),
        label: Text('分享我的近況', style: ElderScale.button),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ElderScale.cardRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ElderScale.cardRadius),
      ),
      child: Column(
        children: [
          const Icon(Icons.forum_outlined, size: 72, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('還沒有近況', style: ElderScale.body),
        ],
      ),
    );
  }

  Widget _buildPostCard(CommunityPost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ElderScale.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  post.authorName.isEmpty
                      ? '友'
                      : post.authorName.substring(0, 1),
                  style: GoogleFonts.notoSansTc(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName, style: ElderScale.body),
                    Text(_formatTime(post.createdAt),
                        style: ElderScale.caption),
                  ],
                ),
              ),
              Text(post.mood, style: const TextStyle(fontSize: 38)),
            ],
          ),
          const SizedBox(height: 16),
          Text(post.content, style: ElderScale.body.copyWith(fontSize: 24)),
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${post.comments.last.authorName}：'
                '${post.comments.last.message.isNotEmpty ? post.comments.last.message : '分享了一張圖片'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    ElderScale.caption.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _postAction(
                  icon: post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: post.likeCount == 0 ? '關心' : '${post.likeCount} 關心',
                  color:
                      post.isLiked ? AppColors.danger : AppColors.textSecondary,
                  onTap: () => _toggleLike(post),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _postAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: post.comments.isEmpty
                      ? '留言'
                      : '${post.comments.length} 留言',
                  color: AppColors.primary,
                  onTap: () => _showComments(post),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _postAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return '剛剛';
    if (difference.inHours < 1) return '${difference.inMinutes} 分鐘前';
    if (difference.inDays < 1) return '${difference.inHours} 小時前';
    if (difference.inDays == 1) return '昨天';
    return '${time.month} 月 ${time.day} 日';
  }
}
