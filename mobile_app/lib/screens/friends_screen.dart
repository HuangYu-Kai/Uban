import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '我的朋友',
          style: GoogleFonts.notoSansTc(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        toolbarHeight: 80,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        // ★ 第四十一輪（item 4）：「家人／朋友」分頁。長輩端字級放大、圖示
        // 置頂，沿用 elder_home_screen.dart::_buildNavItem 的視覺語言（圖示
        // 在上、文字在下）；TabBar 是 Flutter 內建元件，未引入新 UI 套件。
        bottom: TabBar(
          key: widget.tabBarKey,
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 4,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          labelStyle: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          unselectedLabelStyle: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.family_restroom_rounded, size: 28),
              text: '家人',
            ),
            Tab(
              icon: Icon(Icons.person_add_alt_1_rounded, size: 28),
              text: '朋友',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 家人：現有清單與行為，未改動。
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _familyList.isEmpty
                    ? _buildEmptyState()
                    : _buildFriendList(),
          ),
          // 朋友：好友社群系統（第四十一輪 item 3）。
          SafeArea(child: _buildFriendsTab()),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 96, color: AppColors.textHint),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '目前還沒有朋友',
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '請家人先完成配對',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
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
    return RefreshIndicator(
      onRefresh: _loadFriendsData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
        children: [
          _buildAddFriendButton(),
          const SizedBox(height: AppSpacing.md),
          _buildFriendCircleEntryCard(),
          if (_incomingRequests.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              '好友邀請',
              style: GoogleFonts.notoSansTc(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._incomingRequests.map(_buildIncomingRequestCard),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            '我的好友',
            style: GoogleFonts.notoSansTc(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._buildFriendsListSection(),
        ],
      ),
    );
  }

  Widget _buildAddFriendButton() {
    return SizedBox(
      height: ElderScale.buttonHeight,
      child: ElevatedButton.icon(
        onPressed: _openAddFriendScreen,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: ElderScale.buttonIcon),
        label: Text('加好友', style: ElderScale.button.copyWith(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ElderScale.cardRadius)),
        ),
      ),
    );
  }

  Widget _buildFriendCircleEntryCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ElderFriendFeedScreen(userId: widget.userId, userName: widget.userName),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.primaryDark, borderRadius: AppRadius.lgAll),
        child: Row(
          children: [
            const Icon(Icons.dynamic_feed_rounded, color: Colors.white, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '朋友圈',
                    style: GoogleFonts.notoSansTc(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '看看朋友的近況、分享自己的生活',
                    style: GoogleFonts.notoSansTc(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequestCard(Map<String, dynamic> req) {
    final name = (req['from_elder_name'] ?? '長輩').toString();
    final id = (req['from_elder_id'] ?? '').toString();
    final requestId = req['request_id'];
    final isBusy = _respondingRequestIds.contains(requestId);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(avatarUrl: req['avatar_url'] as String?, name: name, radius: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$name（ID: $id）想加你為好友',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : () => _respondRequest(requestId, false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Text('拒絕', style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: isBusy ? null : () => _respondRequest(requestId, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(52)),
                  child: isBusy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('接受', style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
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
    final name = (friend['elder_name'] ?? '朋友').toString();
    final id = (friend['elder_id'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          FriendAvatar(avatarUrl: friend['avatar_url'] as String?, name: name, radius: 30),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: $id',
                  style: GoogleFonts.notoSansTc(fontSize: 15, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          // ★ 第四十二輪：好友視訊撥打鍵。加在「解除好友」之前，正面動作優先於
          // 破壞性動作；與旁邊的 IconButton 一樣是固定寬度元件，Row 的溢位防線
          // 仍由左側 Expanded 內的 name Text（maxLines:1 + ellipsis）承擔，
          // 未破壞既有的可收縮設計（鐵律 #14／G142：判準是「字級 × 同列元素
          // 數」，這裡多一顆固定寬度的 IconButton 不影響 Expanded 的收縮行為）。
          IconButton(
            tooltip: '視訊通話',
            onPressed: () => _startFriendCall(id, name, isVideo: true),
            icon: const Icon(Icons.videocam_rounded, color: AppColors.primary),
          ),
          IconButton(
            tooltip: '解除好友',
            onPressed: () => _confirmRemoveFriend(id, name),
            icon: const Icon(Icons.person_remove_alt_1_outlined, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFriendsYet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_rounded, size: 96, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '還沒有朋友',
              style: GoogleFonts.notoSansTc(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '點上面的「加好友」開始交朋友吧',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsFullError(String message, Future<void> Function() onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 80, color: AppColors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(fontSize: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
      itemCount: _familyList.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final map = _familyList[index] is Map
            ? _familyList[index] as Map
            : <String, dynamic>{};
        final name = (map['user_name'] ?? '家人').toString();
        // ★ 第四十一輪（item 2）：新手指引只點亮第一張卡片的按鈕，其餘卡片
        //   不受影響。
        return _buildFriendCard(name, isFirst: index == 0);
      },
    );
  }

  Widget _buildFriendCard(String name, {bool isFirst = false}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              name.isNotEmpty ? name.substring(0, 1) : '家',
              style: GoogleFonts.notoSansTc(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // 名字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '家人',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // 右邊：電話 + 視訊
          _callAction(
            actionKey: isFirst ? widget.firstCallKey : null,
            icon: Icons.call_rounded,
            label: '電話',
            color: AppColors.primary,
            onTap: () => _startCall(name, isVideo: false),
          ),
          const SizedBox(width: AppSpacing.sm),
          _callAction(
            actionKey: isFirst ? widget.firstVideoKey : null,
            icon: Icons.videocam_rounded,
            label: '視訊',
            color: AppColors.primaryDark,
            onTap: () => _startCall(name, isVideo: true),
          ),
        ],
      ),
    );
  }

  // 右側圓形動作鈕（圖示 + 下方小字）
  Widget _callAction({
    Key? actionKey,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: actionKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
