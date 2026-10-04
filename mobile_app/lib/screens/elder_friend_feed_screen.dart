import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/friend_service.dart';
import '../widgets/ui/ui.dart';
import 'elder_tabs/widgets/elder_social_widgets.dart';
import 'widgets/friend_avatar.dart';

/// 長輩「朋友圈」動態牆內容（第四十一輪 item 3；第四十三輪抽成可嵌入 widget）。
///
/// Threads／FB／IG 風格的單欄時間軸：頭像＋名字＋時間＋內文＋圖片＋按讚／留言，
/// 但長輩可用性優先——字級大、觸控目標大、讚／留言各一顆大按鈕，不做小圖示列；
/// 不做無限捲動，分頁用「載入更多」按鈕（後端 `/friend/feed` 支援 limit/offset）。
///
/// 與家庭圈（`elder_community_screen.dart`）完全獨立——這裡呼叫的是
/// `FriendService`／`routers/friend.py`，不會讀寫任何 `community_posts` 資料。
/// 貼文附圖沿用既有的 `ApiService.uploadCommunityImage`（通用圖片上傳端點，
/// 與家庭圈貼文資料表無關，純粹是共用的檔案儲存工具）。
///
/// 只回傳內容本身（不含 Scaffold／AppBar），供兩處共用同一份邏輯與 UI，
/// 零重複實作：
/// - [ElderFriendFeedScreen]：電話 → 朋友 → 朋友圈的獨立畫面入口
///   （`friends_screen.dart:455`），維持原本獨立進入點不變。
/// - `ElderCommunityScreen`（`showFriendTab: true` 時）：長輩端「社群」分頁
///   新增的「朋友」標籤，與「家人」標籤共用同一個 AppBar／TabBar。
class FriendFeedBody extends StatefulWidget {
  final int userId;
  final String userName;

  const FriendFeedBody({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FriendFeedBody> createState() => _FriendFeedBodyState();
}

class _FriendFeedBodyState extends State<FriendFeedBody> {
  static const int _pageSize = 20;

  String? _myElderId;
  bool _isLoadingId = true;
  bool _isLoadingFeed = false;
  bool _isLoadingMore = false;
  String? _loadError;
  bool _hasMore = true;
  int _offset = 0;
  List<Map<String, dynamic>> _posts = [];

  final TextEditingController _postController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _postController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoadingId = true);
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (!mounted) return;
    setState(() {
      _myElderId = id;
      _isLoadingId = false;
    });
    if (id != null) {
      await _loadFeed(reset: true);
    }
  }

  Future<void> _loadFeed({bool reset = false}) async {
    if (_myElderId == null) return;
    final requestOffset = reset ? 0 : _offset;
    setState(() {
      if (reset) {
        _isLoadingFeed = true;
        _loadError = null;
      } else {
        _isLoadingMore = true;
      }
    });
    final result = await FriendService.getFeed(
      elderId: _myElderId!,
      limit: _pageSize,
      offset: requestOffset,
    );
    if (!mounted) return;
    final failed = FriendService.lastFeedError != null;
    final items = result
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      if (reset) {
        _posts = items;
        _offset = items.length;
        _loadError = failed ? FriendService.lastFeedError : null;
      } else {
        _posts.addAll(items);
        _offset += items.length;
      }
      _hasMore = items.length >= _pageSize;
      _isLoadingFeed = false;
      _isLoadingMore = false;
    });
    if (!reset && failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FriendService.lastFeedError ?? '載入更多失敗，請稍後再試')),
      );
    }
  }

  Future<void> _handleLike(Map<String, dynamic> post) async {
    if (_myElderId == null) return;
    final rawId = post['id'];
    final postId = rawId is int ? rawId : int.tryParse('$rawId');
    if (postId == null) return;
    final newCount = await FriendService.likePost(postId: postId, elderId: _myElderId!);
    if (!mounted) return;
    if (newCount != null) {
      setState(() {
        post['like_count'] = newCount;
        post['is_liked'] = true;
      });
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('按讚失敗，請稍後再試')));
    }
  }

  Future<String?> _pickLocalImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      return pickedImage?.path;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('無法讀取圖片，請稍後再試')));
      }
      return null;
    }
  }

  Future<void> _showCreatePostSheet() async {
    if (_myElderId == null) return;
    final controller = _postController..clear();
    String? selectedLocalImagePath;
    bool isUploading = false;

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
                Text('分享到朋友圈',
                    style: ubanText(22, FontWeight.w900, c.text)),
                const SizedBox(height: 2),
                Text('好友都看得到這則貼文',
                    style: ubanText(16, FontWeight.w500, c.text2)),
                const SizedBox(height: 14),
                UbanTextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 200,
                  hintText: '想說些什麼呢？',
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
                  label: selectedLocalImagePath == null
                      ? '加張照片（選填）'
                      : '已選照片',
                  onTap: isUploading
                      ? null
                      : () async {
                          final picked = await _pickLocalImage();
                          if (picked != null) {
                            setSheetState(() => selectedLocalImagePath = picked);
                          }
                        },
                ),
                const SizedBox(height: 14),
                UbanButton(
                  label: isUploading ? '發佈中...' : '發佈',
                  icon: Icons.send_rounded,
                  size: UbanButtonSize.xl,
                  loading: isUploading,
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty &&
                              selectedLocalImagePath == null) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('請先輸入內容或附上照片')),
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
                          final created = await FriendService.createPost(
                            authorElderId: _myElderId!,
                            content: controller.text.trim().isEmpty
                                ? '分享了一張照片'
                                : controller.text.trim(),
                            imageUrl: uploadedUrl,
                          );
                          setSheetState(() => isUploading = false);
                          if (!sheetContext.mounted) return;
                          if (created != null) {
                            Navigator.pop(sheetContext, true);
                          } else {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('發佈失敗，請稍後再試')),
                            );
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
      await _loadFeed(reset: true);
    }
  }

  Future<void> _showComments(Map<String, dynamic> post) async {
    if (_myElderId == null) return;
    final controller = _commentController..clear();
    bool isSubmitting = false;

    await showUbanSheet<void>(
      context,
      (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final c = UbanColors.of(context);
            final comments =
                (post['comments'] as List?)?.whereType<Map>().toList() ?? [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('留言（${comments.length}）',
                    style: ubanText(22, FontWeight.w900, c.text)),
                const SizedBox(height: 12),
                if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('還沒有留言，來跟朋友打聲招呼吧！',
                          textAlign: TextAlign.center,
                          style: ubanText(18, FontWeight.w500, c.text2)),
                    ),
                  )
                else
                  // 留言多時只讓清單捲動，輸入框與送出鈕仍在面板內看得到。
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final cm = comments[index];
                        return ElderCommentTile(
                          name: (cm['author_name'] ?? '朋友').toString(),
                          message: (cm['content'] ?? '').toString(),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                UbanTextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  hintText: '寫下想說的話⋯⋯',
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 10),
                UbanButton(
                  label: isSubmitting ? '傳送中' : '送出',
                  icon: Icons.send_rounded,
                  loading: isSubmitting,
                  onPressed: isSubmitting || controller.text.trim().isEmpty
                      ? null
                      : () async {
                          setSheetState(() => isSubmitting = true);
                          final rawId = post['id'];
                          final postId =
                              rawId is int ? rawId : int.tryParse('$rawId');
                          final result = postId == null
                              ? null
                              : await FriendService.commentOnPost(
                                  postId: postId,
                                  authorElderId: _myElderId!,
                                  content: controller.text.trim(),
                                );
                          if (result != null) {
                            setState(() {
                              final existing =
                                  (post['comments'] as List?) ?? [];
                              post['comments'] = [...existing, result];
                            });
                            controller.clear();
                          }
                          setSheetState(() => isSubmitting = false);
                          if (result == null && sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('留言失敗，請稍後再試')),
                            );
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime time;
    try {
      time = DateTime.parse(iso);
    } catch (_) {
      return '';
    }
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return '剛剛';
    if (difference.inHours < 1) return '${difference.inMinutes} 分鐘前';
    if (difference.inDays < 1) return '${difference.inHours} 小時前';
    if (difference.inDays == 1) return '昨天';
    return '${time.month} 月 ${time.day} 日';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(bottom: false, child: _buildBody());
  }

  Widget _buildBody() {
    if (_isLoadingId || (_isLoadingFeed && _posts.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myElderId == null) {
      return ElderErrorBlock(
          message: '目前無法取得您的資料，請檢查網路後重試', onRetry: _init);
    }
    if (_loadError != null && _posts.isEmpty) {
      return ElderErrorBlock(
        message: _loadError!,
        onRetry: () => _loadFeed(reset: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 132),
        children: [
          UbanButton(
            label: '分享到朋友圈',
            icon: Icons.add_rounded,
            size: UbanButtonSize.xl,
            onPressed: _showCreatePostSheet,
          ),
          const SizedBox(height: 16),
          if (_posts.isEmpty)
            const ElderEmptyCard(
              icon: Icons.groups_rounded,
              message: '還沒有朋友圈動態，加好友後就能看到彼此的近況！',
            ),
          for (final post in _posts) ...[
            _buildPostCard(post),
            const SizedBox(height: 14),
          ],
          if (_posts.isNotEmpty) _buildLoadMoreControl(),
        ],
      ),
    );
  }

  Widget _buildLoadMoreControl() {
    final c = UbanColors.of(context);
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text('已經到底囉', style: ubanText(16, FontWeight.w500, c.text3)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _isLoadingMore
          ? const Center(child: CircularProgressIndicator())
          : UbanButton(
              label: '載入更多',
              variant: UbanButtonVariant.outline,
              onPressed: () => _loadFeed(reset: false),
            ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final imageUrl = post['image_url'] as String?;
    final comments =
        (post['comments'] as List?)?.whereType<Map>().toList() ?? [];
    final rawLike = post['like_count'] ?? 0;
    return ElderFriendPostCard(
      authorName: (post['author_name'] ?? '朋友').toString(),
      avatarUrl: post['avatar_url'] as String?,
      timeText: _formatTime(post['created_at']?.toString()),
      content: (post['content'] ?? '').toString(),
      imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
          ? FriendAvatar.resolveUrl(imageUrl)
          : null,
      likeCount: rawLike is int ? rawLike : int.tryParse('$rawLike') ?? 0,
      isLiked: post['is_liked'] == true,
      commentCount: comments.length,
      onLike: () => _handleLike(post),
      onComment: () => _showComments(post),
    );
  }
}

/// 長輩「朋友圈」動態牆的獨立畫面入口（電話 → 朋友 → 朋友圈，
/// `friends_screen.dart:455`）。
///
/// 第四十三輪抽出 [FriendFeedBody] 後，這裡只剩外殼（2026-10 新設計：頂列＋內容）；
/// 內容邏輯與 UI 100% 共用 [FriendFeedBody]，與長輩「社群」分頁的「朋友」
/// 標籤（`ElderCommunityScreen(showFriendTab: true)`）零重複實作。
class ElderFriendFeedScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderFriendFeedScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderFriendFeedScreen> createState() => _ElderFriendFeedScreenState();
}

class _ElderFriendFeedScreenState extends State<ElderFriendFeedScreen> {
  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: UbanTopBar(title: '朋友圈'),
            ),
            Expanded(
              child: FriendFeedBody(
                  userId: widget.userId, userName: widget.userName),
            ),
          ],
        ),
      ),
    );
  }
}
