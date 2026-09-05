import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/family_friend_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/friend_avatar.dart';

/// 家屬「加好友」畫面（第五項需求：家屬好友系統，家屬端一半，item 4）。
///
/// 流程設計參考長輩端 `elder_add_friend_screen.dart`（我的代碼／搜尋／
/// 好友管理三個分頁切換，不做成多層跳轉），但刻意不用 `ElderScale`——
/// 家屬是一般使用者，不需要長輩端那種特大字級，這裡改用一般的
/// [AppTextStyles]／[AppColors]，按鈕高度、圖示尺寸也對應縮小。刻意不做
/// QR 掃描（長輩版三模式之一）：需求只要求代碼查詢＋邀請＋清單管理，掃碼
/// 對家屬這個使用情境不是必要功能，先不做以縮小風險面。
///
/// 三個分頁：
/// - 我的代碼：顯示（必要時觸發後端惰性產生）自己的 4 碼 `family_code`。
/// - 搜尋加好友：輸入對方 4 碼代碼查詢並送出邀請。
/// - 好友管理：待回應邀請（接受／拒絕）＋已是好友的清單（可解除）。
class FamilyAddFriendScreen extends StatefulWidget {
  final int familyId;
  final String familyName;

  const FamilyAddFriendScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  @override
  State<FamilyAddFriendScreen> createState() => _FamilyAddFriendScreenState();
}

enum _FamilyFriendMode { myCode, search, manage }

class _FamilyAddFriendScreenState extends State<FamilyAddFriendScreen> {
  _FamilyFriendMode _mode = _FamilyFriendMode.myCode;

  String? _myCode;
  bool _isLoadingMyCode = true;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isSendingRequest = false;
  Map<String, dynamic>? _searchResult;
  String? _searchError;
  String? _sendResultMessage;

  bool _isLoadingManage = true;
  String? _manageError;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _friends = [];
  final Set<int> _respondingIds = {};
  final Set<int> _removingIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyCode();
    _loadManageData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyCode() async {
    setState(() => _isLoadingMyCode = true);
    final code = await FamilyFriendService.getMyCode(widget.familyId);
    if (!mounted) return;
    setState(() {
      _myCode = code;
      _isLoadingMyCode = false;
    });
  }

  Future<void> _loadManageData() async {
    setState(() {
      _isLoadingManage = true;
      _manageError = null;
    });
    final requests = await FamilyFriendService.getIncomingRequests(widget.familyId);
    final friends = await FamilyFriendService.getFriendList(widget.familyId);
    if (!mounted) return;
    final requestsFailed = FamilyFriendService.lastRequestsError != null;
    final friendsFailed = FamilyFriendService.lastFriendListError != null;
    setState(() {
      _requests = requests.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _friends = friends.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _isLoadingManage = false;
      // 只有兩份清單都因為失敗而是空的，才顯示整頁重試——其中一份載入成功
      // 就正常顯示，避免一邊網路抖動就讓另一邊已經拿到的資料也被蓋掉。
      _manageError = (requestsFailed && _requests.isEmpty && _friends.isEmpty)
          ? FamilyFriendService.lastRequestsError
          : (friendsFailed && _friends.isEmpty && _requests.isEmpty
              ? FamilyFriendService.lastFriendListError
              : null);
    });
  }

  void _switchMode(_FamilyFriendMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      if (mode == _FamilyFriendMode.search) {
        _searchResult = null;
        _searchError = null;
        _sendResultMessage = null;
      }
    });
  }

  Future<void> _performSearch(String code) async {
    final trimmed = code.trim();
    if (trimmed.length != 4 || int.tryParse(trimmed) == null) {
      setState(() => _searchError = '請輸入 4 位數的好友代碼');
      return;
    }
    if (_myCode != null && trimmed == _myCode) {
      setState(() {
        _searchError = '這是您自己的代碼，換一組朋友的代碼試試看';
        _searchResult = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResult = null;
      _sendResultMessage = null;
    });
    final result = await FamilyFriendService.searchFamily(
      familyCode: trimmed,
      requesterFamilyId: widget.familyId,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      if (result != null) {
        _searchResult = result;
      } else {
        _searchError = FamilyFriendService.lastSearchError ?? '找不到這個好友代碼';
      }
    });
  }

  Future<void> _sendRequest() async {
    if (_searchResult == null || _isSendingRequest) return;
    final rawTargetId = _searchResult!['family_id'];
    final targetId = rawTargetId is int ? rawTargetId : int.tryParse('$rawTargetId');
    if (targetId == null) return;
    setState(() => _isSendingRequest = true);
    final ok = await FamilyFriendService.sendFriendRequest(
      fromFamilyId: widget.familyId,
      toFamilyId: targetId,
    );
    if (!mounted) return;
    setState(() {
      _isSendingRequest = false;
      _sendResultMessage =
          ok ? '已送出邀請，等待對方同意' : (FamilyFriendService.lastRequestError ?? '送出失敗，請稍後再試');
    });
  }

  Future<void> _respond(Map<String, dynamic> request, bool accept) async {
    final rawId = request['request_id'];
    final requestId = rawId is int ? rawId : int.tryParse('$rawId');
    if (requestId == null || _respondingIds.contains(requestId)) return;
    setState(() => _respondingIds.add(requestId));
    final ok = await FamilyFriendService.respondToRequest(
      familyId: widget.familyId,
      requestId: requestId,
      accept: accept,
    );
    if (!mounted) return;
    setState(() => _respondingIds.remove(requestId));
    if (ok) {
      setState(() => _requests.removeWhere((r) => r['request_id'] == rawId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? '已成為好友' : '已拒絕邀請')),
      );
      if (accept) {
        // 剛成為好友，重新整理好友清單（也順便校正邀請清單）。
        _loadManageData();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FamilyFriendService.lastRespondError ?? '操作失敗，請稍後再試')),
      );
    }
  }

  Future<void> _confirmRemoveFriend(Map<String, dynamic> friend) async {
    final rawId = friend['family_id'];
    final friendId = rawId is int ? rawId : int.tryParse('$rawId');
    if (friendId == null) return;
    final name = (friend['family_name'] ?? '這位好友').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解除好友'),
        content: Text('確定要解除與「$name」的好友關係嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingIds.add(friendId));
    final ok = await FamilyFriendService.removeFriend(
      familyId: widget.familyId,
      friendFamilyId: friendId,
    );
    if (!mounted) return;
    setState(() => _removingIds.remove(friendId));
    if (ok) {
      setState(() => _friends.removeWhere((f) => f['family_id'] == rawId));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已解除好友關係')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FamilyFriendService.lastRemoveFriendError ?? '操作失敗，請稍後再試')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('好友', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeSwitcher(),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildModeBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _modeTab(_FamilyFriendMode.myCode, Icons.qr_code_2_rounded, '我的代碼'),
          _modeTab(_FamilyFriendMode.search, Icons.person_search_rounded, '搜尋加好友'),
          _modeTab(_FamilyFriendMode.manage, Icons.group_rounded, '好友管理',
              badge: _requests.length),
        ],
      ),
    );
  }

  Widget _modeTab(_FamilyFriendMode mode, IconData icon, String label, {int badge = 0}) {
    final bool selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _switchMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: selected ? AppColors.primaryDark : AppColors.textHint),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primaryDark : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBody() {
    switch (_mode) {
      case _FamilyFriendMode.myCode:
        return _buildMyCodeBody();
      case _FamilyFriendMode.search:
        return _buildSearchBody();
      case _FamilyFriendMode.manage:
        return _buildManageBody();
    }
  }

  // ── 我的代碼 ──────────────────────────────────────────
  Widget _buildMyCodeBody() {
    if (_isLoadingMyCode) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myCode == null) {
      return _buildInlineErrorBlock('目前無法取得您的好友代碼，請檢查網路後重試', _loadMyCode);
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Text('我的好友代碼', style: AppTextStyles.secondary),
              const SizedBox(height: 12),
              // 4 碼定長字串搭配大字級展示，用 FittedBox 而非 ellipsis——
              // 代碼被截斷會誤導使用者（鐵律 #14 / 護欄 G159）。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _myCode!,
                  style: GoogleFonts.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 10,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _myCode!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製代碼')));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('複製代碼'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '把這組代碼分享給朋友，讓對方在「搜尋加好友」輸入即可送出邀請',
          textAlign: TextAlign.center,
          style: AppTextStyles.secondary,
        ),
      ],
    );
  }

  // ── 搜尋加好友 ────────────────────────────────────────
  Widget _buildSearchBody() {
    return Column(
      children: [
        Text('輸入朋友的 4 位數好友代碼', style: AppTextStyles.body),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 4,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            hintText: '0000',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isSearching ? null : () => _performSearch(_searchController.text),
            icon: _isSearching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.search_rounded, size: 20),
            label: Text(
              _isSearching ? '查詢中...' : '搜尋',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 14),
          _buildErrorBanner(_searchError!),
        ],
        if (_searchResult != null) ...[
          const SizedBox(height: 18),
          _buildResultCard(),
        ],
      ],
    );
  }

  Widget _buildResultCard() {
    final data = _searchResult!;
    final name = (data['family_name'] ?? '家人').toString();
    final codeStr = (data['family_code'] ?? '').toString();
    final avatarUrl = data['avatar_url'] as String?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 36),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('代碼：$codeStr', style: AppTextStyles.secondary),
          const SizedBox(height: 16),
          if (_sendResultMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              width: double.infinity,
              child: Text(
                _sendResultMessage!,
                textAlign: TextAlign.center,
                style: AppTextStyles.secondary.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSendingRequest ? null : _sendRequest,
                icon: _isSendingRequest
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: Text(
                  _isSendingRequest ? '送出中' : '加好友',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
  }

  // ── 好友管理（邀請＋清單） ──────────────────────────────
  Widget _buildManageBody() {
    if (_isLoadingManage) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_manageError != null && _requests.isEmpty && _friends.isEmpty) {
      return _buildInlineErrorBlock(_manageError!, _loadManageData);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_requests.isNotEmpty) ...[
          Text('待回應邀請', style: AppTextStyles.heading),
          const SizedBox(height: 10),
          ..._requests.map(_buildRequestCard),
          const SizedBox(height: 20),
        ],
        Text('我的好友（${_friends.length}）', style: AppTextStyles.heading),
        const SizedBox(height: 10),
        if (_friends.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(Icons.people_outline_rounded, size: 48, color: AppColors.textHint),
                const SizedBox(height: 8),
                Text('還沒有好友，去搜尋加好友試試看吧！', style: AppTextStyles.secondary),
              ],
            ),
          )
        else
          ..._friends.map(_buildFriendCard),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final rawId = request['request_id'];
    final requestId = rawId is int ? rawId : int.tryParse('$rawId');
    final isResponding = requestId != null && _respondingIds.contains(requestId);
    final name = (request['from_family_name'] ?? '家人').toString();
    final avatarUrl = request['avatar_url'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 22),
          const SizedBox(width: 10),
          // ★ 鐵律 #14 / 護欄 G159：同列有頭像＋兩顆按鈕，姓名必須可收縮。
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          if (isResponding)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            IconButton(
              tooltip: '拒絕',
              onPressed: () => _respond(request, false),
              icon: const Icon(Icons.close_rounded, color: AppColors.danger),
            ),
            IconButton(
              tooltip: '接受',
              onPressed: () => _respond(request, true),
              icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final rawId = friend['family_id'];
    final friendId = rawId is int ? rawId : int.tryParse('$rawId');
    final isRemoving = friendId != null && _removingIds.contains(friendId);
    final name = (friend['family_name'] ?? '家人').toString();
    final avatarUrl = friend['avatar_url'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 22),
          const SizedBox(width: 10),
          // ★ 鐵律 #14 / 護欄 G159：同列有頭像＋解除按鈕，姓名必須可收縮。
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          isRemoving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  tooltip: '解除好友',
                  onPressed: () => _confirmRemoveFriend(friend),
                  icon: const Icon(Icons.person_remove_rounded, color: AppColors.textHint),
                ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.secondary.copyWith(color: const Color(0xFFB91C1C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineErrorBlock(String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textHint),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.body),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}
