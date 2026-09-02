import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/community_post.dart';
import '../services/api_service.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import 'widgets/pet_reward_dialog.dart';
import 'widgets/polaroid_post_card.dart';

class ElderCommunityScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final int? familyId;

  const ElderCommunityScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.familyId,
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
      familyId: widget.familyId,
    );
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _isLoading = false;
    });
  }

  Future<void> _toggleLike(CommunityPost post) async {
    debugPrint('🔥 [ElderCommunityScreen] _toggleLike clicked for post: ${post.id}');
    HapticFeedback.mediumImpact();
    final isLiking = !post.isLiked;
    final posts = await _communityService.toggleLike(
      userId: widget.userId,
      userName: widget.userName,
      familyId: widget.familyId,
      postId: post.id,
    );
    if (mounted) {
      setState(() => _posts = posts);
      if (isLiking) {
        PetRewardDialog.show(
          context,
          title: '送出爪印！',
          message: '小嘎幫你把溫暖心意送給家人囉～',
          intimacyExp: 3,
          coins: 1,
        );
      }
    }
  }

  Widget _buildAdaptiveImage(
    String imageSource, {
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) {
    final isRemote = imageSource.startsWith('http://') ||
        imageSource.startsWith('https://') ||
        imageSource.startsWith('/uploads');
    final fullUrl = imageSource.startsWith('/uploads')
        ? '${ApiService.serverRootUrl}$imageSource'
        : imageSource;

    if (isRemote) {
      return Image.network(
        fullUrl,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height ?? 150,
            width: width,
            color: AppColors.background,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: height ?? 90,
          width: width,
          alignment: Alignment.center,
          color: AppColors.background,
          child: Text('圖片載入失敗', style: ElderScale.caption),
        ),
      );
    } else {
      return Image.file(
        File(imageSource),
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          height: height ?? 90,
          width: width,
          alignment: Alignment.center,
          color: AppColors.background,
          child: Text('圖片無法顯示', style: ElderScale.caption),
        ),
      );
    }
  }

  Future<void> _showCreatePostSheet() async {
    debugPrint('🔥 [ElderCommunityScreen] _showCreatePostSheet clicked!');
    final controller = _postController..clear();
    String selectedMood = '😊';
    String selectedStamp = 'walk';
    String? selectedLocalImagePath;
    bool isUploading = false;

    const quickMessages = [
      '今天心情很好！',
      '大家早安，祝平安健康。',
      '剛剛出去走一走，很舒服。',
      '天氣轉涼了，大家要注意保暖。',
    ];

    final stamps = [
      {'key': 'walk', 'icon': '🐾', 'name': '散步'},
      {'key': 'tea', 'icon': '🍵', 'name': '喝茶'},
      {'key': 'sun', 'icon': '☀️', 'name': '早安'},
      {'key': 'flower', 'icon': '🌸', 'name': '平安'},
      {'key': 'food', 'icon': '🍚', 'name': '吃飽'},
      {'key': 'energy', 'icon': '💪', 'name': '活力'},
    ];

    final shouldPublish = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
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
                    Row(
                      children: [
                        Text('分享近況', style: ElderScale.sectionTitle),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_rounded, size: 16, color: AppColors.primaryDark),
                              const SizedBox(width: 4),
                              Text('家人專屬', style: ElderScale.caption.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('只有家人與認識的朋友看得到', style: ElderScale.caption),
                    const SizedBox(height: 16),

                    Text('選擇寵物心情印章', style: ElderScale.body),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: stamps.map((st) {
                          final isSelected = selectedStamp == st['key'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setSheetState(() => selectedStamp = st['key']!),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF166534) : const Color(0xFFCBD5E1),
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(st['icon']!, style: const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 6),
                                    Text(
                                      st['name']!,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? const Color(0xFF166534) : const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text('今天心情', style: ElderScale.body),
                    const SizedBox(height: 8),
                    Row(
                      children: ['😊', '❤️', '🌼', '👍'].map((mood) {
                        final isSelected = selectedMood == mood;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () => setSheetState(() => selectedMood = mood),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                height: 58,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primaryLight : AppColors.background,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                    width: 2,
                                  ),
                                ),
                                child: Text(mood, style: const TextStyle(fontSize: 30)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('快速選一句', style: ElderScale.body),
                    const SizedBox(height: 8),
                    ...quickMessages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            controller.text = message;
                            controller.selection = TextSelection.collapsed(offset: controller.text.length);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                            ),
                            child: Text(
                              message,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
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
                    if (selectedLocalImagePath != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(selectedLocalImagePath!),
                              width: double.infinity,
                              height: 160,
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
                                onPressed: () => setSheetState(() => selectedLocalImagePath = null),
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: isUploading
                                ? null
                                : () async {
                                    final picked = await _pickLocalImage();
                                    if (picked != null) {
                                      setSheetState(() => selectedLocalImagePath = picked);
                                    }
                                  },
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_photo_alternate_rounded, size: 28, color: Color(0xFF475569)),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedLocalImagePath == null ? '加張照片' : '已選照片',
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: isUploading
                                ? null
                                : () async {
                                    if (controller.text.trim().isEmpty && selectedLocalImagePath == null) {
                                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                                        const SnackBar(content: Text('請先選一句、輸入內容或附上照片')),
                                      );
                                      return;
                                    }
                                    setSheetState(() => isUploading = true);

                                    String? uploadedUrl;
                                    if (selectedLocalImagePath != null) {
                                      uploadedUrl = await ApiService.uploadCommunityImage(
                                        File(selectedLocalImagePath!),
                                      );
                                    }

                                    if (!context.mounted) return;
                                    final posts = await _communityService.createPost(
                                      userId: widget.userId,
                                      userName: widget.userName,
                                      userRole: 'elder',
                                      familyId: widget.familyId,
                                      content: controller.text.isEmpty ? '分享了生活照片' : controller.text,
                                      mood: selectedMood,
                                      stampType: selectedStamp,
                                      imageUrl: uploadedUrl ?? selectedLocalImagePath,
                                    );
                                    if (mounted) {
                                      setState(() => _posts = posts);
                                    }
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext, true);
                                    }
                                  },
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFF55B695),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF55B695).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isUploading)
                                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                  else
                                    const Icon(Icons.send_rounded, size: 26, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    isUploading ? '發佈中...' : '發佈近況',
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldPublish == true) {
      if (!mounted) return;
      PetRewardDialog.show(
        context,
        title: '近況發佈成功！',
        message: '小嘎幫你把溫暖動態分享給家人囉～',
        intimacyExp: 10,
        coins: 2,
      );
    }
  }

  Future<void> _showComments(CommunityPost post) async {
    debugPrint('🔥 [ElderCommunityScreen] _showComments clicked for post: ${post.id}');
    final controller = _commentController..clear();
    const quickReplies = ['真好！', '保重身體喔', '改天一起聊聊', '收到～'];
    String? selectedImagePath;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
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
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
                  Row(
                    children: [
                      Text('留言', style: ElderScale.sectionTitle),
                      const SizedBox(width: 8),
                      Text('(${latestPost.comments.length})', style: ElderScale.caption),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (latestPost.comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('還沒有留言，來給予第一句溫馨叮嚀吧！', style: ElderScale.caption),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: latestPost.comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final comment = latestPost.comments[index];
                          final isFamily = comment.authorRole == 'family';
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isFamily ? const Color(0xFFF0FDF4) : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isFamily ? const Color(0xFF86EFAC) : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      comment.authorName,
                                      style: ElderScale.caption.copyWith(
                                        color: isFamily ? const Color(0xFF15803D) : AppColors.primaryDark,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isFamily ? const Color(0xFFDCFCE7) : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isFamily ? '家人 💖' : '長輩 🌿',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isFamily ? const Color(0xFF166534) : AppColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _formatTime(comment.createdAt),
                                      style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                                    ),
                                  ],
                                ),
                                if (comment.message.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    comment.message,
                                    style: ElderScale.caption.copyWith(
                                      color: AppColors.textPrimary,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                                if (comment.imagePath != null && comment.imagePath!.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: _buildAdaptiveImage(
                                      comment.imagePath!,
                                      height: 180,
                                      fit: BoxFit.cover,
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
                              controller.selection = TextSelection.collapsed(offset: controller.text.length);
                              setSheetState(() {});
                            },
                            backgroundColor: AppColors.background,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.all(8),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (selectedImagePath != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(selectedImagePath!),
                            width: double.infinity,
                            height: 130,
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
                              onPressed: () => setSheetState(() => selectedImagePath = null),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
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
                      hintText: '寫下想對家人說的話⋯⋯',
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
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final picked = await _pickLocalImage();
                                  if (picked != null) {
                                    setSheetState(() => selectedImagePath = picked);
                                  }
                                },
                          icon: const Icon(Icons.add_photo_alternate_rounded, size: 28),
                          label: Text(
                            selectedImagePath == null ? '加入圖片' : '已選照片',
                            style: ElderScale.caption,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (controller.text.trim().isEmpty && selectedImagePath == null) || isSubmitting
                              ? null
                              : () async {
                                  setSheetState(() => isSubmitting = true);
                                  String? uploadedUrl;
                                  if (selectedImagePath != null) {
                                    uploadedUrl = await ApiService.uploadCommunityImage(
                                      File(selectedImagePath!),
                                    );
                                  }

                                  if (!context.mounted) return;
                                  final posts = await _communityService.addComment(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                    userRole: 'elder',
                                    familyId: widget.familyId,
                                    postId: post.id,
                                    message: controller.text.trim(),
                                    imageUrl: uploadedUrl ?? selectedImagePath,
                                  );
                                  if (mounted) {
                                    setState(() => _posts = posts);
                                  }
                                  setSheetState(() {
                                    isSubmitting = false;
                                    selectedImagePath = null;
                                    controller.clear();
                                  });
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  if (context.mounted) {
                                    PetRewardDialog.show(
                                      context,
                                      title: '留言已送出！',
                                      message: '小嘎幫你把溫馨叮嚀送到家人身邊～',
                                      intimacyExp: 5,
                                      coins: 1,
                                    );
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send_rounded, size: 28),
                          label: Text(isSubmitting ? '傳送中' : '送出', style: ElderScale.caption),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
  }

  Future<String?> _pickLocalImage() async {
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '家庭社群',
          style: GoogleFonts.notoSansTc(
            fontSize: 28,
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
                  children: [
                    _buildPrivacyCard(),
                    const SizedBox(height: 14),
                    _buildCreatePostButton(),
                    const SizedBox(height: 18),
                    Text('大家的近況', style: ElderScale.sectionTitle),
                    const SizedBox(height: 12),
                    if (_posts.isEmpty) _buildEmptyState(),
                    ..._posts.map((post) => PolaroidPostCard(
                          post: post,
                          onLike: () => _toggleLike(post),
                          onComment: () => _showComments(post),
                        )),
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
          const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showCreatePostSheet,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(ElderScale.cardRadius),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_rounded, size: ElderScale.buttonIcon, color: Colors.white),
              const SizedBox(width: 8),
              Text('分享我的近況', style: ElderScale.button.copyWith(color: Colors.white)),
            ],
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
          Text('還沒有近況，點上方按鈕發佈第一則吧！', style: ElderScale.body),
        ],
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
