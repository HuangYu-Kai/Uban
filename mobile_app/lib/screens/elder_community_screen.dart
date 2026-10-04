import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/community_post.dart';
import '../services/api_service.dart';
import '../services/community_service.dart';
import '../services/friend_service.dart';
import '../widgets/ui/ui.dart';
import 'elder_add_friend_screen.dart';
import 'elder_friend_feed_screen.dart';
import 'elder_tabs/profile/widgets/friend_id_card.dart';
import 'elder_tabs/widgets/elder_social_widgets.dart';
import 'widgets/pet_reward_dialog.dart';
import 'widgets/polaroid_post_card.dart';

class ElderCommunityScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final int? familyId;

  // ★ 第四十二輪：長輩端「社群」分頁加「家人／朋友」頂部標籤。第五項需求
  //   （家屬好友系統）起，家屬端也跟進同一套頂部標籤——目前長輩端首頁
  //   （elder_home_screen.dart）與家屬端（family_interaction_tab.dart::
  //   _buildCommunitySection）皆已傳 true。不傳（預設 false）時維持改動前
  //   的單一畫面、無 TabBar 行為，零回歸；這個預設值仍保留給未來其他未跟進
  //   的呼叫端。
  final bool showFriendTab;

  // ★ 第五項需求（家屬好友系統）：把「朋友」標籤旁邊那個標籤（本來寫死
  //   '家人'）的文字，與朋友標籤要渲染的內容都做成可注入。兩者預設值
  //   等同改動前的長輩端寫死行為——長輩端呼叫點不傳這兩個參數，標籤文字
  //   固定「家人」、內容固定 FriendFeedBody(userId, userName)，100% 不變。
  //   家屬端呼叫時傳入 familyTabLabel: '家庭' 與自己的 FamilyFriendFeedBody，
  //   長輩朋友圈／家屬朋友圈兩邊資料完全不互通。
  final String familyTabLabel;
  final Widget? friendTabContent;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。由上層
  //   ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  //   firstPostLikeKey / firstPostCommentKey 只點亮「大家的近況」清單第一則
  //   貼文的按鈕（清單可能是空的，該步驟會自動退化為置中卡片）。
  final GlobalKey? privacyCardKey;
  final GlobalKey? createPostButtonKey;
  final GlobalKey? firstPostLikeKey;
  final GlobalKey? firstPostCommentKey;

  const ElderCommunityScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.familyId,
    this.showFriendTab = false,
    this.familyTabLabel = '家人',
    this.friendTabContent,
    this.privacyCardKey,
    this.createPostButtonKey,
    this.firstPostLikeKey,
    this.firstPostCommentKey,
  });

  @override
  State<ElderCommunityScreen> createState() => _ElderCommunityScreenState();
}

class _ElderCommunityScreenState extends State<ElderCommunityScreen>
    with SingleTickerProviderStateMixin {
  final CommunityService _communityService = CommunityService();
  final TextEditingController _postController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  List<CommunityPost> _posts = [];
  bool _isLoading = true;

  // 只有 showFriendTab 時才建立，家屬端（預設 false）不會多出一個沒用到的
  // vsync ticker。
  TabController? _tabController;

  // ★ 任務 C：長輩自己的朋友圈好友 ID，搬到「朋友」標籤上方的 FriendIdCard
  //   顯示用。只有長輩端自己的路徑（friendTabContent == null）才需要載入，
  //   家屬端傳入 friendTabContent 時完全不會用到這個欄位。null 時
  //   FriendIdCard 自己會顯示「載入中…」。
  String? _myFriendElderId;

  @override
  void initState() {
    super.initState();
    if (widget.showFriendTab) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _initialize();
    if (widget.showFriendTab && widget.friendTabContent == null) {
      _loadMyFriendElderId();
    }
  }

  Future<void> _loadMyFriendElderId() async {
    final elderId = await FriendService.resolveMyElderId(widget.userId);
    if (!mounted) return;
    setState(() {
      _myFriendElderId = elderId;
    });
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
    final c = UbanColors.of(context);
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
            color: c.surface2,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: height ?? 90,
          width: width,
          alignment: Alignment.center,
          color: c.surface2,
          child: Text('圖片載入失敗', style: ubanText(16, FontWeight.w500, c.text3)),
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
          color: c.surface2,
          child: Text('圖片無法顯示', style: ubanText(16, FontWeight.w500, c.text3)),
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

    final shouldPublish = await showUbanSheet<bool>(
      context,
      (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final c = UbanColors.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('分享近況',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ubanText(22, FontWeight.w900, c.text)),
                    ),
                    const Spacer(),
                    const SizedBox(width: 8),
                    ElderTagPill(
                      label: '家人專屬',
                      bg: c.brandContainer,
                      fg: c.brandStrong,
                      fontSize: 15,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('只有家人與認識的朋友看得到',
                    style: ubanText(16, FontWeight.w500, c.text2)),
                const SizedBox(height: 16),
                Text('選擇寵物心情印章',
                    style: ubanText(18, FontWeight.w700, c.text)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final st in stamps)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ChoiceChip(
                            label: '${st['icon']} ${st['name']}',
                            selected: selectedStamp == st['key'],
                            onTap: () =>
                                setSheetState(() => selectedStamp = st['key']!),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('今天心情', style: ubanText(18, FontWeight.w700, c.text)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final mood in ['😊', '❤️', '🌼', '👍'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _MoodBox(
                            mood: mood,
                            selected: selectedMood == mood,
                            onTap: () => setSheetState(() => selectedMood = mood),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('快速選一句', style: ubanText(18, FontWeight.w700, c.text)),
                const SizedBox(height: 8),
                for (final message in quickMessages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _QuickLine(
                      text: message,
                      onTap: () {
                        controller.text = message;
                        controller.selection = TextSelection.collapsed(
                            offset: controller.text.length);
                      },
                    ),
                  ),
                const SizedBox(height: 4),
                UbanTextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 120,
                  hintText: '也可以自己輸入想說的話',
                ),
                const SizedBox(height: 12),
                if (selectedLocalImagePath != null) ...[
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
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
                            onPressed: () => setSheetState(
                                () => selectedLocalImagePath = null),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                ElderPhotoAddButton(
                  label: selectedLocalImagePath == null ? '加張照片' : '已選照片',
                  onTap: isUploading
                      ? null
                      : () async {
                          final picked = await _pickLocalImage();
                          if (picked != null) {
                            setSheetState(() => selectedLocalImagePath = picked);
                          }
                        },
                ),
                const SizedBox(height: 12),
                UbanButton(
                  label: isUploading ? '發佈中...' : '發佈近況',
                  icon: Icons.send_rounded,
                  size: UbanButtonSize.xl,
                  loading: isUploading,
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty &&
                              selectedLocalImagePath == null) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                  content: Text('請先選一句、輸入內容或附上照片')),
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
                            content: controller.text.isEmpty
                                ? '分享了生活照片'
                                : controller.text,
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
                ),
              ],
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

    await showUbanSheet<void>(
      context,
      (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final c = UbanColors.of(context);
            final latestPost = _posts.firstWhere(
              (item) => item.id == post.id,
              orElse: () => post,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('留言（${latestPost.comments.length}）',
                    style: ubanText(22, FontWeight.w900, c.text)),
                const SizedBox(height: 12),
                if (latestPost.comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('還沒有留言，來給予第一句溫馨叮嚀吧！',
                          textAlign: TextAlign.center,
                          style: ubanText(18, FontWeight.w500, c.text2)),
                    ),
                  )
                else
                  // 留言多時只讓清單捲動，輸入區與送出鈕仍在面板內看得到。
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: latestPost.comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final comment = latestPost.comments[index];
                        final isFamily = comment.authorRole == 'family';
                        return ElderCommentTile(
                          name: comment.authorName,
                          message: comment.message,
                          badge: isFamily ? '家人' : '長輩',
                          badgeIsFamily: isFamily,
                          timeText: _formatTime(comment.createdAt),
                          image: (comment.imagePath != null &&
                                  comment.imagePath!.isNotEmpty)
                              ? _buildAdaptiveImage(
                                  comment.imagePath!,
                                  height: 180,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reply in quickReplies)
                      _ChoiceChip(
                        label: reply,
                        selected: false,
                        onTap: () {
                          controller.text = reply;
                          controller.selection = TextSelection.collapsed(
                              offset: controller.text.length);
                          setSheetState(() {});
                        },
                      ),
                  ],
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
                            onPressed: () =>
                                setSheetState(() => selectedImagePath = null),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                UbanTextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  hintText: '寫下想對家人說的話⋯⋯',
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ElderPhotoAddButton(
                        label: selectedImagePath == null ? '加入圖片' : '已選照片',
                        onTap: isSubmitting
                            ? null
                            : () async {
                                final picked = await _pickLocalImage();
                                if (picked != null) {
                                  setSheetState(() => selectedImagePath = picked);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: UbanButton(
                        label: isSubmitting ? '傳送中' : '送出',
                        icon: Icons.send_rounded,
                        loading: isSubmitting,
                        onPressed: (controller.text.trim().isEmpty &&
                                    selectedImagePath == null) ||
                                isSubmitting
                            ? null
                            : () async {
                                setSheetState(() => isSubmitting = true);
                                String? uploadedUrl;
                                if (selectedImagePath != null) {
                                  uploadedUrl =
                                      await ApiService.uploadCommunityImage(
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
                      ),
                    ),
                  ],
                ),
              ],
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
    _tabController?.dispose();
    _postController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final familyContent = _buildFamilyContent();

    // 2026-10 新設計：AppBar 換成「大標題＋膠囊分段」。顏色全走 UbanColors——
    // 長輩端是品牌綠，家屬端（外層包 FamilyThemeScope）自動變海灣藍。
    // 字級採長輩尺度（標題 30、分段 18），家屬端看起來略大無妨。
    // 分段仍是 TabBar（內含 Tab），只是外觀做成設計稿 `.segbig` 的膠囊；
    // 這樣 TabController 與既有的 Tab 結構（測試也依賴）完全不變。
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '家庭社群',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ubanText(30, FontWeight.w900, c.text, height: 1.25),
          ),
          if (widget.showFriendTab) ...[
            const SizedBox(height: 14),
            _buildSegmentTabs(c),
          ],
        ],
      ),
    );

    // 家屬端（預設 showFriendTab: false）走單一畫面分支，沒有 TabBar。
    final Widget body = !widget.showFriendTab
        ? familyContent
        : TabBarView(
            controller: _tabController,
            children: [
              familyContent,
              // 朋友標籤：家屬端傳入 friendTabContent（FamilyFriendFeedBody）時
              // 維持原樣、完全不變——不會被下面的 FriendIdCard 影響。
              // 長輩端自己的路徑（friendTabContent 為 null）才在最上方加一張
              // FriendIdCard（★ 任務 C：從「我的」分頁搬過來），下方仍 100% 重用
              // FriendFeedBody（elder_friend_feed_screen.dart），與「電話 → 朋友 →
              // 朋友圈」（ElderFriendFeedScreen）共用同一份邏輯。
              widget.friendTabContent ??
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: FriendIdCard(myFriendElderId: _myFriendElderId),
                      ),
                      // ★ 第五十二輪任務 A：社群「朋友」分頁的明確加好友入口
                      // （導去同一個 ElderAddFriendScreen，與「電話 → 朋友」互不影響）。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                        child: _buildAddFriendButton(),
                      ),
                      Expanded(
                        child: FriendFeedBody(
                          userId: widget.userId,
                          userName: widget.userName,
                        ),
                      ),
                    ],
                  ),
            ],
          );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 4),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// 設計稿 `.segbig` 外觀的 TabBar：surface2 膠囊、padding 5、白色滑動 thumb。
  Widget _buildSegmentTabs(UbanColors c) {
    final labelStyle = ubanText(18, FontWeight.w700, c.text2);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(999),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelPadding: EdgeInsets.zero,
        labelColor: c.brandStrong,
        unselectedLabelColor: c.text2,
        labelStyle: labelStyle,
        unselectedLabelStyle: labelStyle,
        indicator: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, .08),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        tabs: [
          Tab(height: 52, text: widget.familyTabLabel),
          const Tab(height: 52, text: '朋友'),
        ],
      ),
    );
  }

  /// 加好友大按鈕——文案「加好友」與 friends_screen.dart 的入口一致（測試鎖定
  /// 它必須是 [ElevatedButton]，所以外觀用 style 做成 `.btn.filled.xl`：膠囊、高 76）。
  /// 回來後重新載入自己的好友 ID，讓剛送出的邀請／新好友狀態能反映在 FriendIdCard。
  Widget _buildAddFriendButton() {
    final c = UbanColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 76,
      child: ElevatedButton.icon(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ElderAddFriendScreen(
                userId: widget.userId,
                userName: widget.userName,
              ),
            ),
          );
          if (mounted) _loadMyFriendElderId();
        },
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 26),
        label: Text('加好友', style: ubanText(22, FontWeight.w700, c.onBrand)),
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brandFill,
          foregroundColor: c.onBrand,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _buildFamilyContent() {
    final c = UbanColors.of(context);
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadPosts,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 132),
              children: [
                _buildPrivacyCard(),
                const SizedBox(height: 14),
                _buildCreatePostButton(),
                const SizedBox(height: 20),
                Text('大家的近況', style: ubanText(22, FontWeight.w900, c.text)),
                const SizedBox(height: 12),
                if (_posts.isEmpty) _buildEmptyState(),
                // ★ 第四十一輪（item 2）：只在第一則貼文（index == 0）傳入教學
                //   高光用的 key，其餘貼文不受影響。
                ..._posts.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final CommunityPost post = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: PolaroidPostCard(
                      post: post,
                      onLike: () => _toggleLike(post),
                      onComment: () => _showComments(post),
                      likeButtonKey:
                          index == 0 ? widget.firstPostLikeKey : null,
                      commentButtonKey:
                          index == 0 ? widget.firstPostCommentKey : null,
                    ),
                  );
                }),
              ],
            ),
          );
  }

  Widget _buildPrivacyCard() {
    final c = UbanColors.of(context);
    return Container(
      key: widget.privacyCardKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.brandContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
            child: Icon(Icons.lock_rounded, color: c.brandStrong, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '這裡只有家人和認識的朋友',
              style: ubanText(18, FontWeight.w700, c.brandStrong, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePostButton() {
    return Container(
      key: widget.createPostButtonKey,
      child: UbanButton(
        label: '分享我的近況',
        icon: Icons.add_rounded,
        size: UbanButtonSize.xl,
        onPressed: _showCreatePostSheet,
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: ElderEmptyCard(
        icon: Icons.forum_outlined,
        message: '還沒有近況，點上方按鈕發佈第一則吧！',
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

/// 發文／留言面板的選項小膠囊（印章、快速留言）：高 ≥48，選中時 brand 色。
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandContainer : c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? c.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: ubanText(
                18, FontWeight.w700, selected ? c.brandStrong : c.text2),
          ),
        ),
      ),
    );
  }
}

/// 「今天心情」方塊：高 58、圓角 18。
class _MoodBox extends StatelessWidget {
  final String mood;
  final bool selected;
  final VoidCallback onTap;

  const _MoodBox({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '心情 $mood',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandContainer : c.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? c.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(mood, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}

/// 「快速選一句」整列：surface2 底、圓角 18、內文 18。
class _QuickLine extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _QuickLine({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            text,
            style: ubanText(18, FontWeight.w500, c.text, height: 1.4),
          ),
        ),
      ),
    );
  }
}
