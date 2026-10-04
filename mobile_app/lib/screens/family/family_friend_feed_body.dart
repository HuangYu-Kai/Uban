import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/family_friend_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import '../widgets/friend_avatar.dart';
import 'family_add_friend_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// 家屬「朋友圈」動態牆內容（第五項需求：家屬好友系統，家屬端一半）。
///
/// 結構比照長輩版 `FriendFeedBody`（`elder_friend_feed_screen.dart`）——
/// 頭像＋名字＋時間＋內文＋圖片＋按讚／留言，分頁用「載入更多」按鈕——但
/// 刻意有兩處不同：
///
/// 1. 呼叫的是 [FamilyFriendService]／後端 `routers/family_friend.py`，
///    資料完全獨立於長輩朋友圈（`friend_*` 表）與家庭圈
///    （`community_posts`），不會互相污染。
/// 2. 2026-10 起外觀改家屬新設計（海灣藍：[UbanColors]／fam_ui 元件，不用
///    `ElderScale` 的長輩放大字級）；原本沿用 `ElderCommunityScreen` 的 teal
///    白卡風格，現在與家屬其他頁面一致。行為與資料流完全不變。
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

  // 開 sheet 要用位於家屬主題之內的 context（build 內 Builder 更新）。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

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
        famSnackBar(_themeCtx, FamilyFriendService.lastFeedError ?? '載入更多失敗，請稍後再試', error: true),
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
          .showSnackBar(famSnackBar(_themeCtx, '按讚失敗，請稍後再試', error: true));
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
            .showSnackBar(famSnackBar(_themeCtx, '無法讀取圖片，請稍後再試', error: true));
      }
      return null;
    }
  }

  Future<void> _showCreatePostSheet() async {
    final controller = _postController..clear();
    String? selectedLocalImagePath;
    bool isUploading = false;

    // 2026-10：改用 UbanSheet（面板外觀）；發佈流程與改版前相同。
    final shouldPublish = await showUbanSheet<bool>(
      _themeCtx,
      (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final c = UbanColors.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                famDialogTitle(c, '分享到朋友圈'),
                const SizedBox(height: 4),
                Text('好友都看得到這則貼文', style: famText(c.text2, 14)),
                const SizedBox(height: 14),
                FamInput(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 200,
                  hintText: '想說些什麼呢？',
                  radius: 18,
                  fillColor: c.surface2,
                ),
                const SizedBox(height: 10),
                if (selectedLocalImagePath != null) ...[
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
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
                        child: FamIconButton(
                          icon: Icons.close_rounded,
                          tooltip: '移除圖片',
                          onTap: () => setSheetState(() => selectedLocalImagePath = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                FamButton(
                  label: selectedLocalImagePath == null ? '加張照片（選填）' : '已選照片',
                  kind: FamButtonKind.tonal,
                  height: _buttonHeight,
                  onPressed: isUploading
                      ? null
                      : () async {
                          final picked = await _pickLocalImage();
                          if (picked != null) {
                            setSheetState(() => selectedLocalImagePath = picked);
                          }
                        },
                ),
                const SizedBox(height: 10),
                FamButton(
                  label: isUploading ? '發佈中...' : '發佈',
                  height: _buttonHeight,
                  loading: isUploading,
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty &&
                              selectedLocalImagePath == null) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              famSnackBar(sheetContext, '請先輸入內容或附上照片'),
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
                              famSnackBar(sheetContext, '發佈失敗，請稍後再試', error: true),
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
    final controller = _commentController..clear();
    bool isSubmitting = false;

    await showUbanSheet<void>(
      _themeCtx,
      (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final c = UbanColors.of(context);
            final comments =
                (post['comments'] as List?)?.whereType<Map>().toList() ?? [];
            // UbanSheet 內容本身會捲動，所以留言清單用一般 Column，不放內層 ListView。
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    famDialogTitle(c, '留言'),
                    const SizedBox(width: 8),
                    Text('(${comments.length})', style: famText(c.text2, 15)),
                  ],
                ),
                const SizedBox(height: 10),
                if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('還沒有留言，來跟朋友打聲招呼吧！',
                          textAlign: TextAlign.center,
                          style: famText(c.text2, 14.5, height: 1.5)),
                    ),
                  )
                else
                  for (var index = 0; index < comments.length; index++)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (comments[index]['author_name'] ?? '家人').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: famText(c.brandStrong, 13.5, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              (comments[index]['content'] ?? '').toString(),
                              style: famText(c.text, 14.5, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
                FamInput(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  radius: 18,
                  hintText: '寫下想說的話⋯⋯',
                  fillColor: c.surface2,
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 10),
                FamButton(
                  label: isSubmitting ? '傳送中' : '送出',
                  height: _buttonHeight,
                  loading: isSubmitting,
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
                              famSnackBar(sheetContext, '留言失敗，請稍後再試', error: true),
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
    // 2026-10：家屬新設計——本元件也會被單獨嵌進共用的 ElderCommunityScreen，
    // 自己掛家屬主題（Builder 讓下方 context 位於主題之內；sheet 用 [_themeCtx] 開）。
    return FamilyThemeScope(
      child: Builder(builder: (ctx) {
        _themed = ctx;
        return SafeArea(bottom: false, child: _buildBody());
      }),
    );
  }

  // ★ 第五十二輪任務 B 收尾（social52 中斷後接續）：原本 _isLoadingFeed／
  // _loadError 兩個早期 return 會讓「整頁」只剩讀取圈或整頁錯誤重試畫面，
  // 連帶把上面的 _buildFriendEntryCard()／_buildCreatePostButton() 也一起
  // 蓋掉。getFeed 走真實網路（見 family_friend_service.dart:299「無法連線
  // 到後端」），只要家屬那一刻網路不穩或後端剛好重啟，這個入口就會整個
  // 消失、直到下次重試成功——這正是本輪「家屬端找不到加好友入口」複查時
  // 應該一併堵住的路徑，不能讓「動態牆」的載入狀態連帶決定「加好友」入口
  // 是否可見。改成一律走同一個 RefreshIndicator + ListView，只把讀取中／
  // 錯誤重試換成「動態區塊」自己的一個項目，入口卡片與發文按鈕永遠在最上方、
  // 永遠看得到、永遠點得到。
  Widget _buildBody() {
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
          ..._buildFeedSection(),
        ],
      ),
    );
  }

  /// 動態牆本身的讀取中／整頁錯誤／清單三態，與上方加好友入口的顯示與否
  /// 無關（見 [_buildBody] 的說明）。
  List<Widget> _buildFeedSection() {
    if (_isLoadingFeed && _posts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: CircularProgressIndicator(color: _c.brand),
          ),
        ),
      ];
    }
    if (_loadError != null && _posts.isEmpty) {
      return [_buildFullError(_loadError!, () => _loadFeed(reset: true))];
    }
    return [
      if (_posts.isEmpty) _buildEmptyState(),
      ..._posts.map(_buildPostCard),
      if (_posts.isNotEmpty) _buildLoadMoreControl(),
    ];
  }

  /// 加好友的入口卡片——第 4 項需求刻意放在朋友標籤內，而不是
  /// `ElderCommunityScreen` 的 AppBar，這樣完全不需要改動長輩端既有的
  /// AppBar 結構。有待回應邀請時，「＋加好友」標籤轉暖色（待處理）、副標顯示
  /// 邀請數（[_loadPendingCount]），讓家屬不用點進去就知道有沒有新邀請。
  Widget _buildFriendEntryCard() {
    return FamAction(
      title: '我的好友',
      subtitle: _pendingRequestCount > 0 ? '有 $_pendingRequestCount 則新邀請' : '加好友、看邀請、管理好友清單',
      // ★ 鐵律 #14 / 護欄 G159：同列有「＋加好友」標籤與箭頭，標題／副標在
      // FamAction 內是 Expanded 並可換行，不會把箭頭擠出畫面。
      // ★ 第五十二輪任務 B：標籤文字「＋加好友」維持不變（使用者回報找不到入口）。
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FamChip(
            label: '＋加好友',
            tone: _pendingRequestCount > 0 ? FamTone.warm : FamTone.brand,
          ),
          const SizedBox(width: 4),
          FamAction.chevron(context),
        ],
      ),
      onTap: _openAddFriend,
    );
  }

  Widget _buildCreatePostButton() {
    return FamButton(
      label: '分享到朋友圈',
      height: _buttonHeight,
      onPressed: _showCreatePostSheet,
    );
  }

  Widget _buildEmptyState() {
    return FamCard(
      padding: const EdgeInsets.all(28),
      child: Text(
        '還沒有朋友圈動態，加朋友後就能看到彼此的近況！',
        textAlign: TextAlign.center,
        style: famText(_c.text2, 15, height: 1.6),
      ),
    );
  }

  Widget _buildLoadMoreControl() {
    final c = _c;
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text('已經到底囉', style: famText(c.text3, 14))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: _isLoadingMore
            ? CircularProgressIndicator(color: c.brand)
            : FamButton(
                label: '載入更多',
                kind: FamButtonKind.tonal,
                expand: false,
                onPressed: () => _loadFeed(reset: false),
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
            Text(message,
                textAlign: TextAlign.center,
                style: famText(_c.text2, 15, height: 1.6)),
            const SizedBox(height: 14),
            FamButton(
              label: '重試',
              kind: FamButtonKind.tonal,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final c = _c;
    final authorName = (post['author_name'] ?? '家人').toString();
    final avatarUrl = post['avatar_url'] as String?;
    final content = (post['content'] ?? '').toString();
    final imageUrl = post['image_url'] as String?;
    final likeCount = post['like_count'] ?? 0;
    final isLiked = post['is_liked'] == true;
    final createdAtStr = post['created_at']?.toString();
    final comments = (post['comments'] as List?)?.whereType<Map>().toList() ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FamCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FamFriendAvatar(avatarUrl: avatarUrl, name: authorName, size: 44),
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
                        style: famText(c.text, 16, weight: FontWeight.w800),
                      ),
                      Text(_formatTime(createdAtStr), style: famText(c.text3, 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(content, style: famText(c.text, 15, height: 1.6)),
            ],
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  FriendAvatar.resolveUrl(imageUrl),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 200,
                      color: c.surface2,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: 140,
                    color: c.surface2,
                    alignment: Alignment.center,
                    child: Text('圖片載入失敗', style: famText(c.text3, 14)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '讚 ($likeCount)',
                    kind: isLiked ? FamButtonKind.filled : FamButtonKind.tonal,
                    height: 44,
                    onPressed: () => _handleLike(post),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '留言 (${comments.length})',
                    kind: FamButtonKind.tonal,
                    height: 44,
                    onPressed: () => _showComments(post),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
