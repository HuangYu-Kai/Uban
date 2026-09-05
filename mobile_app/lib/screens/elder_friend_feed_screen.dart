import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/friend_service.dart';
import '../theme/app_theme.dart';
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
                    Text('分享到朋友圈', style: ElderScale.sectionTitle),
                    const SizedBox(height: 6),
                    Text('好友都看得到這則貼文', style: ElderScale.caption),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 200,
                      style: ElderScale.body,
                      decoration: InputDecoration(
                        hintText: '想說些什麼呢？',
                        hintStyle: ElderScale.caption,
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                                onPressed: () =>
                                    setSheetState(() => selectedLocalImagePath = null),
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                final picked = await _pickLocalImage();
                                if (picked != null) {
                                  setSheetState(() => selectedLocalImagePath = picked);
                                }
                              },
                        icon: const Icon(Icons.add_photo_alternate_rounded, size: 26),
                        label: Text(
                          selectedLocalImagePath == null ? '加張照片（選填）' : '已選照片',
                          style: ElderScale.caption,
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: ElderScale.buttonHeight,
                      child: ElevatedButton.icon(
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
                        icon: isUploading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.send_rounded, size: 26),
                        label: Text(
                          isUploading ? '發佈中...' : '發佈',
                          style: ElderScale.button.copyWith(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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

    if (shouldPublish == true) {
      await _loadFeed(reset: true);
    }
  }

  Future<void> _showComments(Map<String, dynamic> post) async {
    if (_myElderId == null) return;
    final controller = _commentController..clear();
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final comments =
                (post['comments'] as List?)?.whereType<Map>().toList() ?? [];
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
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
                      Text('(${comments.length})', style: ElderScale.caption),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('還沒有留言，來跟朋友打聲招呼吧！', style: ElderScale.caption),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final c = comments[index];
                          final cName = (c['author_name'] ?? '朋友').toString();
                          final cContent = (c['content'] ?? '').toString();
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ElderScale.caption.copyWith(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(cContent, style: ElderScale.body),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
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
                  SizedBox(
                    height: ElderScale.buttonHeight,
                    child: ElevatedButton.icon(
                      onPressed: isSubmitting || controller.text.trim().isEmpty
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              final rawId = post['id'];
                              final postId = rawId is int ? rawId : int.tryParse('$rawId');
                              final result = postId == null
                                  ? null
                                  : await FriendService.commentOnPost(
                                      postId: postId,
                                      authorElderId: _myElderId!,
                                      content: controller.text.trim(),
                                    );
                              if (result != null) {
                                setState(() {
                                  final existing = (post['comments'] as List?) ?? [];
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
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 26),
                      label: Text(
                        isSubmitting ? '傳送中' : '送出',
                        style: ElderScale.button.copyWith(color: Colors.white, fontSize: 22),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                  ),
                ],
              ),
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
      return _buildFullError('目前無法取得您的資料，請檢查網路後重試', _init);
    }
    if (_loadError != null && _posts.isEmpty) {
      return _buildFullError(_loadError!, () => _loadFeed(reset: true));
    }
    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
        children: [
          _buildCreatePostButton(),
          const SizedBox(height: 18),
          if (_posts.isEmpty) _buildEmptyState(),
          ..._posts.map(_buildPostCard),
          if (_posts.isNotEmpty) _buildLoadMoreControl(),
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
              Text('分享到朋友圈', style: ElderScale.button.copyWith(color: Colors.white)),
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
          const Icon(Icons.groups_rounded, size: 72, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            '還沒有朋友圈動態，加朋友後就能看到彼此的近況！',
            textAlign: TextAlign.center,
            style: ElderScale.body,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreControl() {
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('已經到底囉', style: ElderScale.caption)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : OutlinedButton(
                onPressed: () => _loadFeed(reset: false),
                child: Text('載入更多', style: ElderScale.body),
              ),
      ),
    );
  }

  Widget _buildFullError(String message, Future<void> Function() onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 72, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: ElderScale.body),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('重試', style: ElderScale.button.copyWith(color: Colors.white, fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final authorName = (post['author_name'] ?? '朋友').toString();
    final avatarUrl = post['avatar_url'] as String?;
    final content = (post['content'] ?? '').toString();
    final imageUrl = post['image_url'] as String?;
    final likeCount = post['like_count'] ?? 0;
    final isLiked = post['is_liked'] == true;
    final createdAtStr = post['created_at']?.toString();
    final comments = (post['comments'] as List?)?.whereType<Map>().toList() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(avatarUrl: avatarUrl, name: authorName, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ElderScale.body.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(_formatTime(createdAtStr), style: ElderScale.caption),
                  ],
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(content, style: ElderScale.body),
          ],
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                FriendAvatar.resolveUrl(imageUrl),
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 220,
                    color: AppColors.background,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  height: 150,
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: Text('圖片載入失敗', style: ElderScale.caption),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _bigActionButton(
                  icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  label: '讚 ($likeCount)',
                  color: isLiked ? AppColors.danger : AppColors.textSecondary,
                  onTap: () => _handleLike(post),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: '留言 (${comments.length})',
                  color: AppColors.primaryDark,
                  onTap: () => _showComments(post),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ElderScale.caption.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 長輩「朋友圈」動態牆的獨立畫面入口（電話 → 朋友 → 朋友圈，
/// `friends_screen.dart:455`）。
///
/// 第四十三輪抽出 [FriendFeedBody] 後，這裡只剩 Scaffold／AppBar 外殼；
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '朋友圈',
          style: GoogleFonts.notoSansTc(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: FriendFeedBody(userId: widget.userId, userName: widget.userName),
    );
  }
}
