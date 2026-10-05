import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/ui/ui.dart';
import 'elder_tabs/elder_layout.dart';
import 'elder_tabs/profile/dialogs/family_pairing_dialog.dart';
import 'elder_tabs/widgets/elder_call_button.dart';
import '../services/api_service.dart';
import '../services/friend_service.dart';
import 'elder_add_friend_screen.dart';
import 'elder_friend_feed_screen.dart';
import 'elder_screen.dart';
import 'widgets/friend_avatar.dart';

/// 長輩端「朋友列表」全畫面（撥號為主）。
///
/// 只負責 UI 呈現：讀取已配對家屬（沿用 `ApiService.getPairedFamily`），
/// 以長輩友善的大卡片列出，點擊即可語音 / 視訊通話（沿用既有 `ElderScreen` 通話入口）。
/// 不涉及任何 WebRTC / 信令 / GPS 等功能邏輯的修改。
class FriendsScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。
  //   由上層 ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  //   firstCallKey / firstVideoKey 只點亮「家人」清單第一張卡片的按鈕
  //   （清單可能是空的——沒有卡片時該步驟自動退化為置中卡片，見
  //   spotlight_tutorial.dart 的防呆說明）。
  final GlobalKey? tabBarKey;
  final GlobalKey? firstCallKey;
  final GlobalKey? firstVideoKey;

  const FriendsScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
    this.tabBarKey,
    this.firstCallKey,
    this.firstVideoKey,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _familyList = [];
  bool _isLoading = true;

  // ★ 第四十一輪（item 4）：長輩端電話介面「家人／朋友」分頁。
  //   「家人」＝現有清單與行為（本次一字未改）。
  late final TabController _tabController;

  // ★ 第四十一輪（item 3）：「朋友」分頁——真正的好友社群系統。
  //   myElderId 是朋友圈所有端點的權威身分鍵，解析方式見
  //   FriendService.resolveMyElderId 的說明（不可用 userId 補零臆測）。
  String? _myElderId;
  bool _isLoadingMyElderId = true;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  String? _friendsError;
  final Set<dynamic> _respondingRequestIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFamily();
    _loadFriendsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchFamily() async {
    try {
      final family = await ApiService.getPairedFamily(widget.userId);
      if (mounted) {
        setState(() {
          _familyList = family;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ★ 第四十一輪（item 3）：載入「朋友」分頁資料。myElderId 只解析一次
  //   （成功後快取在 state 裡）；好友清單／待回應邀請兩個請求並行送出，
  //   彼此獨立失敗互不影響（各自的 lastXxxError 是獨立的靜態欄位）。
  Future<void> _loadFriendsData() async {
    if (_myElderId == null) {
      if (mounted) setState(() => _isLoadingMyElderId = true);
      final id = await FriendService.resolveMyElderId(widget.userId);
      if (!mounted) return;
      setState(() {
        _myElderId = id;
        _isLoadingMyElderId = false;
      });
      if (id == null) return;
    }
    final results = await Future.wait([
      FriendService.getFriendList(_myElderId!),
      FriendService.getIncomingRequests(_myElderId!),
    ]);
    if (!mounted) return;
    setState(() {
      _friends = results[0]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _incomingRequests = results[1]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _friendsError = FriendService.lastFriendListError;
    });
  }

  Future<void> _respondRequest(dynamic requestId, bool accept) async {
    if (_myElderId == null || requestId == null) return;
    final int? id = requestId is int ? requestId : int.tryParse(requestId.toString());
    if (id == null) return;
    setState(() => _respondingRequestIds.add(requestId));
    final ok = await FriendService.respondToRequest(
      elderId: _myElderId!,
      requestId: id,
      accept: accept,
    );
    if (!mounted) return;
    setState(() => _respondingRequestIds.remove(requestId));
    if (ok) {
      await _loadFriendsData();
      if (mounted && accept) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已成為好友！')));
      }
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失敗，請稍後再試')));
    }
  }

  Future<void> _confirmRemoveFriend(String friendId, String friendName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('解除好友', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold, fontSize: 20)),
        content: Text(
          '確定要與「$friendName」解除好友關係嗎？',
          style: GoogleFonts.notoSansTc(fontSize: 16, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: GoogleFonts.notoSansTc(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('解除', style: GoogleFonts.notoSansTc(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || _myElderId == null) return;
    final ok = await FriendService.removeFriend(elderId: _myElderId!, friendElderId: friendId);
    if (!mounted) return;
    if (ok) {
      await _loadFriendsData();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('解除失敗，請稍後再試')));
    }
  }

  void _openAddFriendScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ElderAddFriendScreen(userId: widget.userId, userName: widget.userName),
      ),
    );
    if (mounted) _loadFriendsData();
  }

  // 沿用長輩端既有通話入口（ElderScreen），不修改通話邏輯。
  //
  // ★ 2026-08-11 第二十一輪（需求 1）：房間 ID 的解析改為容錯。
  //   原本是 `widget.roomId ?? widget.userId.toString()`——但 `userId` 是
  //   `caregiver_id`（資料庫帳號整數 ID），**不是** elder_id。只要上游沒把 roomId
  //   傳下來（例如 video_call_screen.dart 的 `_buildFallbackHome()` 建構
  //   ElderHomeScreen 時就沒有帶 roomId），撥出的房名會變成
  //   `comm_elder_<caregiver_id>`，後端 `_get_family_ids_for_elder()` 查不到任何
  //   家屬 → log 印「無任何轉發目標」→ 長輩端按下撥打後完全沒有反應。
  //   改為：roomId 缺漏時回頭讀 prefs 的 `elder_room_id`（登入／配對時寫入的權威值）；
  //   兩者都沒有就明確告知使用者，絕不拿 caregiver_id 硬湊一個不存在的房間。
  Future<void> _startCall(String friendName, {required bool isVideo}) async {
    String? roomId = widget.roomId?.trim();
    if (roomId == null || roomId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        roomId = prefs.getString('elder_room_id')?.trim();
      } catch (e) {
        debugPrint('⚠️ [FriendsScreen] 讀取 elder_room_id 失敗: $e');
      }
    }
    if (!mounted) return;
    if (roomId == null || roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到您的通話帳號資料，請重新登入後再試')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: roomId!,
          deviceName: widget.userName,
          autoCall: true,
          isVideoCall: isVideo,
        ),
      ),
    );
  }

  // ★ 第四十二輪：好友通話——以「好友」身分進入對方的房間撥打。
  //
  // 呼叫者自己房間 ID 的解析邏輯與 [_startCall] 完全相同（widget.roomId →
  // prefs 的 elder_room_id → 明確報錯）：**絕不可**退回 `widget.userId`——
  // 那是 caregiver_id（帳號整數 ID），不是 elder_id，見 [_startCall] 上方
  // 第二十一輪的說明與踩過的坑。
  Future<void> _startFriendCall(
    String friendElderId,
    String friendName, {
    required bool isVideo,
  }) async {
    String? myRoomId = widget.roomId?.trim();
    if (myRoomId == null || myRoomId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        myRoomId = prefs.getString('elder_room_id')?.trim();
      } catch (e) {
        debugPrint('⚠️ [FriendsScreen] 讀取 elder_room_id 失敗: $e');
      }
    }
    if (!mounted) return;
    if (myRoomId == null || myRoomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到您的通話帳號資料，請重新登入後再試')),
      );
      return;
    }
    if (friendElderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到這位朋友的通話帳號資料')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: myRoomId!,
          friendCallTargetElderId: friendElderId,
          deviceName: widget.userName,
          autoCall: true,
          isVideoCall: isVideo,
        ),
      ),
    );
  }

  // ── 以下全是呈現層（設計稿 #tabPhone）：撥打／好友操作全部沿用上方原函式 ──

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '打電話',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(30, FontWeight.w900, c.text, height: 1.25),
                  ),
                  const SizedBox(height: 14),
                  // ★ 第四十一輪（item 4）的「家人／朋友」分頁：切換仍由同一個
                  // TabController 驅動（兩個分頁內容的建構函式不變）；分段鈕只是它的
                  // 新外觀。tabBarKey（新手指引高光目標）掛在 UbanSegmented 上。
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) => UbanSegmented(
                      key: widget.tabBarKey,
                      labels: const ['家人', '朋友'],
                      index: _tabController.index,
                      onChanged: (i) => _tabController.animateTo(i),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 家人：現有清單與行為，未改動。
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _familyList.isEmpty
                          ? _buildEmptyState()
                          : _buildFriendList(),
                  // 朋友：好友社群系統（第四十一輪 item 3）。
                  _buildFriendsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = UbanColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 96, color: c.text3),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '目前還沒有朋友',
              textAlign: TextAlign.center,
              style: ubanText(24, FontWeight.w800, c.text2),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '請家人先完成配對',
              textAlign: TextAlign.center,
              style: ubanText(18, FontWeight.w400, c.text3),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 長輩端專用畫面（FriendsScreen 只有長輩端使用）：直接出示配對碼，
            // 只開對話框，不碰通話／撥號邏輯。
            UbanButton(
              label: '出示配對碼給家人',
              icon: Icons.link_rounded,
              size: UbanButtonSize.xl,
              onPressed: () => showFamilyPairingDialog(context, widget.userId),
            ),
          ],
        ),
      ),
    );
  }

  /// 設計稿 `.sec-head`：區塊標題＋（選填）數量徽章。
  Widget _sectionHead(UbanColors c, String title, {int? badge}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ubanText(22, FontWeight.w900, c.text)),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: c.dangerContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$badge',
                  style: ubanBrandText(16, FontWeight.w600, c.danger)),
            ),
          ],
        ],
      ),
    );
  }

  /// 設計稿 `.person .avatar`：圓形頭像；有網址顯示圖片，否則（或載入失敗）顯示姓名字首。
  Widget _personAvatar(UbanColors c, String name, String? avatarUrl,
      {double size = 64, int tone = 0}) {
    final bg = tone == 1
        ? c.warmContainer
        : tone == 2
            ? c.infoContainer
            : c.brandContainer;
    final fg = tone == 1
        ? c.warm
        : tone == 2
            ? c.info
            : c.brandStrong;
    final initial =
        name.isNotEmpty ? String.fromCharCode(name.runes.first) : '友';
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(initial, style: ubanText(26, FontWeight.w900, fg)),
    );
    if (avatarUrl == null || avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        FriendAvatar.resolveUrl(avatarUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// 設計稿 `.person`：頭像＋姓名／副標＋（選填）在線標記。
  Widget _personRow(
    UbanColors c, {
    required Widget avatar,
    required String name,
    required String subtitle,
    double nameSize = 24,
  }) {
    return Row(
      children: [
        avatar,
        const SizedBox(width: 14),
        // ⚠️ 姓名／副標是使用者或後端的動態字串，必須可收縮（鐵律 #14）。
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(nameSize, FontWeight.w900, c.text)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ubanText(16, FontWeight.w400, c.text2)),
            ],
          ),
        ),
      ],
    );
  }

  // ★ 第四十一輪（item 3）：「朋友」分頁——好友社群系統本體。
  //
  // ★ 第四十二輪：長輩↔長輩好友通話已上線。後端新增 'friend' 角色
  // （`socket_app.py::_verify_room_access`——查呼叫端與房間所屬長輩之間是否
  // 存在 `status='accepted'` 的 `elder_friendship`，fail-closed；friend 只能
  // 進 `comm_elder_*`，不算進監控機額度／IP 上限），前端以 `role:'friend'`
  // 加入對方的 `comm_elder_<對方>` 房間撥打（見 [_startFriendCall] 與
  // `ElderScreen.friendCallTargetElderId`），完全重用既有的
  // call-request/offer/answer/candidate/end-call 事件，沒有新增任何 Socket
  // 事件。好友卡片的撥打鍵見 [_buildFriendListCard]。
  Widget _buildFriendsTab() {
    if (_isLoadingMyElderId) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myElderId == null) {
      return _buildFriendsFullError('目前無法取得您的好友資料，請檢查網路後重試', _loadFriendsData);
    }
    final c = UbanColors.of(context);
    return RefreshIndicator(
      onRefresh: _loadFriendsData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18, 0, 18, elderNavClearance(context)),
        children: [
          _buildAddFriendButton(),
          const SizedBox(height: 12),
          _buildFriendCircleEntryCard(),
          if (_incomingRequests.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionHead(c, '好友邀請', badge: _incomingRequests.length),
            const SizedBox(height: 12),
            ..._incomingRequests.map(_buildIncomingRequestCard),
          ],
          const SizedBox(height: 20),
          _sectionHead(c, '我的好友'),
          const SizedBox(height: 12),
          ..._buildFriendsListSection(),
        ],
      ),
    );
  }

  Widget _buildAddFriendButton() {
    return UbanButton(
      label: '加好友',
      icon: Icons.person_add_alt_1_rounded,
      variant: UbanButtonVariant.tonal,
      onPressed: _openAddFriendScreen,
    );
  }

  Widget _buildFriendCircleEntryCard() {
    return UbanActionTile(
      icon: Icons.dynamic_feed_rounded,
      title: '朋友圈',
      subtitle: '看看朋友的近況、分享自己的生活',
      trailing: UbanActionTile.chevron(context),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ElderFriendFeedScreen(userId: widget.userId, userName: widget.userName),
        ),
      ),
    );
  }

  Widget _buildIncomingRequestCard(Map<String, dynamic> req) {
    final c = UbanColors.of(context);
    final name = (req['from_elder_name'] ?? '長輩').toString();
    final id = (req['from_elder_id'] ?? '').toString();
    final requestId = req['request_id'];
    final isBusy = _respondingRequestIds.contains(requestId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UbanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _personRow(
              c,
              avatar: _personAvatar(c, name, req['avatar_url'] as String?,
                  size: 56, tone: 2),
              name: name,
              nameSize: 21,
              subtitle: 'ID：$id　想加您為好友',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: UbanButton(
                    label: '拒絕',
                    variant: UbanButtonVariant.outline,
                    onPressed: isBusy ? null : () => _respondRequest(requestId, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UbanButton(
                    label: '接受',
                    loading: isBusy,
                    onPressed: isBusy ? null : () => _respondRequest(requestId, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFriendsListSection() {
    if (_friendsError != null && _friends.isEmpty) {
      return [_buildFriendsFullError(_friendsError!, _loadFriendsData)];
    }
    if (_friends.isEmpty) {
      return [_buildNoFriendsYet()];
    }
    return _friends.map(_buildFriendListCard).toList();
  }

  Widget _buildFriendListCard(Map<String, dynamic> friend) {
    final c = UbanColors.of(context);
    final name = (friend['elder_name'] ?? '朋友').toString();
    final id = (friend['elder_id'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UbanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _personRow(
              c,
              avatar: _personAvatar(c, name, friend['avatar_url'] as String?),
              name: name,
              subtitle: 'ID：$id',
            ),
            const SizedBox(height: 14),
            // ★ 第四十二輪：好友視訊撥打鍵在「解除好友」之前，正面動作優先於破壞性動作。
            Row(
              children: [
                Expanded(
                  child: ElderCallButton(
                    label: '視訊',
                    icon: Icons.videocam_rounded,
                    onTap: () => _startFriendCall(id, name, isVideo: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElderCallButton(
                    label: '解除好友',
                    tone: ElderCallButtonTone.neutral,
                    onTap: () => _confirmRemoveFriend(id, name),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFriendsYet() {
    final c = UbanColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_rounded, size: 96, color: c.text3),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '還沒有朋友',
              textAlign: TextAlign.center,
              style: ubanText(24, FontWeight.w800, c.text2),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '點上面的「加好友」開始交朋友吧',
              textAlign: TextAlign.center,
              style: ubanText(18, FontWeight.w400, c.text3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsFullError(String message, Future<void> Function() onRetry) {
    final c = UbanColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 80, color: c.text3),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ubanText(18, FontWeight.w400, c.text2),
            ),
            const SizedBox(height: AppSpacing.md),
            UbanButton(label: '重試', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendList() {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(18, 0, 18, elderNavClearance(context)),
      itemCount: _familyList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final map = _familyList[index] is Map
            ? _familyList[index] as Map
            : <String, dynamic>{};
        final name = (map['user_name'] ?? '家人').toString();
        // ★ 第四十一輪（item 2）：新手指引只點亮第一張卡片的按鈕，其餘卡片
        //   不受影響。
        // 不顯示「在線」：後端 /user/{id}/family 的 is_online 寫死為 True，
        // 沒有真實來源，顯示出來是假資訊。
        return _buildFriendCard(name, isFirst: index == 0, index: index);
      },
    );
  }

  Widget _buildFriendCard(String name,
      {bool isFirst = false, int index = 0}) {
    final c = UbanColors.of(context);
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _personRow(
            c,
            avatar: _personAvatar(c, name, null, tone: index % 3),
            name: name,
            subtitle: '家人',
          ),
          const SizedBox(height: 14),
          // 電話（filled）＋視訊（tonal）；firstCallKey／firstVideoKey 仍只掛第一位家人。
          Row(
            children: [
              Expanded(
                child: ElderCallButton(
                  key: isFirst ? widget.firstCallKey : null,
                  label: '電話',
                  icon: Icons.call_rounded,
                  tone: ElderCallButtonTone.filled,
                  onTap: () => _startCall(name, isVideo: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElderCallButton(
                  key: isFirst ? widget.firstVideoKey : null,
                  label: '視訊',
                  icon: Icons.videocam_rounded,
                  onTap: () => _startCall(name, isVideo: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
