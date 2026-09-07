import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/family_friend_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/friend_avatar.dart';
import 'family_add_friend_screen.dart';
import 'package:image_picker/image_picker.dart';

/// 家屬「朋友圈」動態牆內容（第五項需求：家屬好友系統，家屬端一半）。
///
/// 結構比照長輩版 `FriendFeedBody`（`elder_friend_feed_screen.dart`）——
/// 頭像＋名字＋時間＋內文＋圖片＋按讚／留言，分頁用「載入更多」按鈕——但
/// 刻意有兩處不同：
///
/// 1. 呼叫的是 [FamilyFriendService]／後端 `routers/family_friend.py`，
///    資料完全獨立於長輩朋友圈（`friend_*` 表）與家庭圈
///    （`community_posts`），不會互相污染。
/// 2. 字級改用 [AppTextStyles]／[AppColors]（一般使用者字級），不用
///    `ElderScale`（長輩端專用的放大字級）——家屬是一般使用者，這是與長輩版
///    刻意的唯一差異；卡片風格（白卡＋淺灰底＋teal 主色）仍沿用
///    `ElderCommunityScreen` 既有的視覺語言，符合「不動整體設計」的要求。
///
/// 不含 Scaffold／AppBar，供 `ElderCommunityScreen(friendTabContent: ...)`
/// 當「朋友」標籤內容嵌入。不需要另外解析 ID——家屬的 `familyId` 呼叫端
/// 已經從 SharedPreferences 的 `caregiver_id` 取得（兩者是同一個值），
/// 不像長輩朋友圈那樣要多打一支 API 反查 `elder_id`。
///
/// 加好友入口（第 4 項需求）刻意放在這裡（[_buildFriendEntryCard]），不是
/// `ElderCommunityScreen` 的 AppBar——這樣完全不用碰長輩端既有的 AppBar
/// 結構，零風險。
class FamilyFriendFeedBody extends StatefulWidget {
  final int familyId;
  final String familyName;

  const FamilyFriendFeedBody({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  @override
  State<FamilyFriendFeedBody> createState() => _FamilyFriendFeedBodyState();
}

class _FamilyFriendFeedBodyState extends State<FamilyFriendFeedBody> {
  static const int _pageSize = 20;
  static const double _buttonHeight = 52;

  bool _isLoadingFeed = false;
  bool _isLoadingMore = false;
  String? _loadError;
  bool _hasMore = true;
  int _offset = 0;
  List<Map<String, dynamic>> _posts = [];

  int _pendingRequestCount = 0;

  final TextEditingController _postController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFeed(reset: true);
    _loadPendingCount();
  }

  @override
  void dispose() {
    _postController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  /// 僅供入口卡片顯示未讀角標，非關鍵資訊——失敗就維持 0，不彈錯誤、不影響
  /// 動態牆本身（比照 family_interaction_tab.dart::_syncAudioBridgeForAlerts
  /// 「輔助資訊失敗不能干擾主功能」的既有慣例）。
  Future<void> _loadPendingCount() async {
    final requests = await FamilyFriendService.getIncomingRequests(widget.familyId);
    if (!mounted) return;
    setState(() => _pendingRequestCount = requests.length);
  }

  Future<void> _loadFeed({bool reset = false}) async {
    final requestOffset = reset ? 0 : _offset;
    setState(() {
      if (reset) {
        _isLoadingFeed = true;
        _loadError = null;
      } else {
        _isLoadingMore = true;
      }
    });
    final result = await FamilyFriendService.getFeed(
      familyId: widget.familyId,
      limit: _pageSize,
      offset: requestOffset,
    );
    if (!mounted) return;
    final failed = FamilyFriendService.lastFeedError != null;
    final items = result
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      if (reset) {
        _posts = items;
        _offset = items.length;
        _loadError = failed ? FamilyFriendService.lastFeedError : null;
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
        SnackBar(content: Text(FamilyFriendService.lastFeedError ?? '載入更多失敗，請稍後再試')),
      );
    }
  }

  Future<void> _openAddFriend() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FamilyAddFriendScreen(
          familyId: widget.familyId,
          familyName: widget.familyName,
        ),
      ),
    );
    if (!mounted) return;
    // 從加好友畫面回來時，好友關係可能已變動（新好友、邀請被接受、解除
    // 好友），動態牆與角標一併重新整理。
    _loadPendingCount();
    _loadFeed(reset: true);
  }

  Future<void> _handleLike(Map<String, dynamic> post) async {
    final rawId = post['id'];
    final postId = rawId is int ? rawId : int.tryParse('$rawId');
    if (postId == null) return;
    final newCount = await FamilyFriendService.likePost(
      postId: postId,
      familyId: widget.familyId,
    );
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('分享到朋友圈', style: AppTextStyles.title),
                    const SizedBox(height: 4),
                    Text('好友都看得到這則貼文', style: AppTextStyles.secondary),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 200,
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: '想說些什麼呢？',
                        hintStyle: AppTextStyles.secondary,
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (selectedLocalImagePath != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(selectedLocalImagePath!),
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
                                onPressed: () =>
                                    setSheetState(() => selectedLocalImagePath = null),
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: _buttonHeight,
                      child: OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                final picked = await _pickLocalImage();
                                if (picked != null) {
                                  setSheetState(() => selectedLocalImagePath = picked);
                                }
                              },
                        icon: const Icon(Icons.add_photo_alternate_rounded, size: 22),
                        label: Text(
                          selectedLocalImagePath == null ? '加張照片（選填）' : '已選照片',
                          style: AppTextStyles.secondary,
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: _buttonHeight,
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
                                final created = await FamilyFriendService.createPost(
                                  authorFamilyId: widget.familyId,
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
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.send_rounded, size: 22),
                        label: Text(
                          isUploading ? '發佈中...' : '發佈',
                          style: AppTextStyles.body
                              .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('留言', style: AppTextStyles.title),
                      const SizedBox(width: 8),
                      Text('(${comments.length})', style: AppTextStyles.secondary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('還沒有留言，來跟朋友打聲招呼吧！', style: AppTextStyles.secondary),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final c = comments[index];
                          final cName = (c['author_name'] ?? '家人').toString();
                          final cContent = (c['content'] ?? '').toString();
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.secondary.copyWith(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(cContent, style: AppTextStyles.body),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    style: AppTextStyles.body,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 120,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: '寫下想說的話⋯⋯',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: _buttonHeight,
                    child: ElevatedButton.icon(
                      onPressed: isSubmitting || controller.text.trim().isEmpty
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              final rawId = post['id'];
                              final postId = rawId is int ? rawId : int.tryParse('$rawId');
                              final result = postId == null
                                  ? null
                                  : await FamilyFriendService.commentOnPost(
                                      postId: postId,
                                      authorFamilyId: widget.familyId,
                                      content: controller.text.trim(),
                                    );
                              if (result != null) {
                                setState(() {
                                  final existing = (post['comments'] as List?) ?? [];
                                  post['comments'] = [
                                    ...existing,
                                    {
                                      ...result,
                                      'author_name': result['author_name'] ?? widget.familyName,
                                    },
                                  ];
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
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        isSubmitting ? '傳送中' : '送出',
                        style: AppTextStyles.body
                            .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    if (_isLoadingFeed && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
          _buildFriendEntryCard(),
          const SizedBox(height: 14),
          _buildCreatePostButton(),
          const SizedBox(height: 18),
          if (_posts.isEmpty) _buildEmptyState(),
          ..._posts.map(_buildPostCard),
          if (_posts.isNotEmpty) _buildLoadMoreControl(),
        ],
      ),
    );
  }

  /// 加好友的入口卡片——第 4 項需求刻意放在朋友標籤內，而不是
  /// `ElderCommunityScreen` 的 AppBar，這樣完全不需要改動長輩端既有的
  /// AppBar 結構。角標數字＝待回應邀請數（[_loadPendingCount]），
  /// 讓家屬不用點進去就知道有沒有新邀請。
  Widget _buildFriendEntryCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _openAddFriend,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: AppColors.primaryDark, size: 22),
                  ),
                  if (_pendingRequestCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_pendingRequestCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // ★ 鐵律 #14 / 護欄 G159：同列還有頭像圖示與箭頭，姓名／說明文字
              // 必須包在 Expanded 內並可省略，避免長邀請數字串把箭頭擠出畫面。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('我的好友', style: AppTextStyles.heading, overflow: TextOverflow.ellipsis),
                    Text(
                      _pendingRequestCount > 0 ? '有 $_pendingRequestCount 則新邀請' : '加好友、看邀請、管理好友清單',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.secondary,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostButton() {
    return SizedBox(
      height: _buttonHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showCreatePostSheet,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.card),
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
              const Icon(Icons.add_circle_rounded, size: 24, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                '分享到朋友圈',
                style: AppTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          const Icon(Icons.groups_rounded, size: 64, color: AppColors.textHint),
          const SizedBox(height: 10),
          Text(
            '還沒有朋友圈動態，加朋友後就能看到彼此的近況！',
            textAlign: TextAlign.center,
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreControl() {
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text('已經到底囉', style: AppTextStyles.secondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : OutlinedButton(
                onPressed: () => _loadFeed(reset: false),
                child: Text('載入更多', style: AppTextStyles.body),
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
            const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textHint),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('重試', style: AppTextStyles.body.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final authorName = (post['author_name'] ?? '家人').toString();
    final avatarUrl = post['avatar_url'] as String?;
    final content = (post['content'] ?? '').toString();
    final imageUrl = post['image_url'] as String?;
    final likeCount = post['like_count'] ?? 0;
    final isLiked = post['is_liked'] == true;
    final createdAtStr = post['created_at']?.toString();
    final comments = (post['comments'] as List?)?.whereType<Map>().toList() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(avatarUrl: avatarUrl, name: authorName, radius: 22),
              const SizedBox(width: 10),
              // ★ 鐵律 #14 / 護欄 G159：同列還有頭像，姓名一律 Expanded + ellipsis。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(_formatTime(createdAtStr), style: AppTextStyles.secondary),
                  ],
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(content, style: AppTextStyles.body),
          ],
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                FriendAvatar.resolveUrl(imageUrl),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 200,
                    color: AppColors.background,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: Text('圖片載入失敗', style: AppTextStyles.secondary),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.secondary.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
