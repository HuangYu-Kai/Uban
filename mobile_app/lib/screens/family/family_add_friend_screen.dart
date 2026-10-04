import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/family_friend_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import '../widgets/friend_avatar.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';

/// 家屬「加好友」畫面（第五項需求：家屬好友系統，家屬端一半，item 4；
/// 第五十二輪任務 C 補上 QR 顯示／分享／掃描）。
///
/// 流程設計參考長輩端 `elder_add_friend_screen.dart` 的三個分頁（我的
/// QR 碼／掃描朋友／輸入 ID，見該檔 `_AddFriendMode`，不做成多層跳轉），
/// 但多加第四個分頁「好友管理」——長輩端沒有這個分頁，長輩管理好友清單
/// 走別的畫面（`FriendFeedBody`／`friends_screen.dart`）；家屬端刻意把
/// 待回應邀請與好友清單合併進同一個畫面，四個分頁一次到位，不用再多開一層
/// 導頁。也刻意不用 `ElderScale`——家屬是一般使用者，不需要長輩端那種特大
/// 字級，這裡改用一般的 [AppTextStyles]／[AppColors]，按鈕高度、圖示尺寸
/// 也對應縮小。
///
/// ★ 第五十二輪以前這裡刻意不做 QR 掃描（理由是「不是必要功能，先縮小風險
/// 面」，見本檔 git 歷史）；第五十二輪任務 C 依使用者與 team-lead 的明確
/// 要求補上——長輩端已有穩定運作的 mobile_scanner 實作可以比照，風險可控，
/// 因此不再維持原本「先不做」的判斷，直接重用長輩端同一套權限處理與偵測
/// 邏輯（`detectionSpeed: DetectionSpeed.noDuplicates`、`_hasHandledScan`
/// 防重複觸發）。
///
/// 四個分頁：
/// - 我的代碼：顯示（必要時觸發後端惰性產生）自己的 4 碼 `family_code`，
///   並排 QR 碼（`qr_flutter`）與複製／分享（`share_plus`）三種取得方式。
/// - 掃描：用 `mobile_scanner` 掃朋友的 QR 碼（格式 `uban-family:<CODE>`，
///   見 [kFamilyFriendQrPrefix]／[decodeFamilyFriendQr]），掃到後直接走與
///   「搜尋加好友」相同的 [_performSearch]。
/// - 搜尋加好友：輸入對方 4 碼代碼查詢並送出邀請。
/// - 好友管理：待回應邀請（接受／拒絕）＋已是好友的清單（可解除）。
///
/// ⚠️ 誠實性要求：`android/app/src/main/AndroidManifest.xml` 目前只註冊了
/// `uban://recovery` 一組 deep link，沒有「點連結就自動加好友」的處理，
/// 分享文案（見 [_shareMyCode]）因此只講「代碼」，請對方手動輸入或掃描，
/// 不可以寫成「點連結就能加好友」這種目前做不到的承諾。

/// QR 內容格式 `uban-family:<4碼代碼>`——刻意帶字首而不是裸代碼，讓掃描端
/// 能明確分辨「這是不是 Uban 好友的 QR 碼」，與長輩端 `_qrPrefix`
/// （`uban-friend:`，見 elder_add_friend_screen.dart）同一套設計，只是
/// 命名空間不同，避免長輩／家屬雙方互掃到對方陣營的 QR 碼時誤判成功。
///
/// ★ 第五十二輪任務 C：這個常數與下面兩個函式刻意拉到 State 類別外面、
/// 宣告成頂層符號（不是類別的私有成員）——單純字串組合／解析，不依賴任何
/// widget 狀態，這樣測試（見 test/screens/family/family_add_friend_screen_test.dart）
/// 能直接呼叫真正在跑的程式碼驗證「產生的字串」與「解析函式」互相對應，
/// 不用另外重寫一份平行邏輯，也不需要碰觸 `_FamilyAddFriendScreenState`
/// 的私有成員。
const String kFamilyFriendQrPrefix = 'uban-family:';

/// 把 4 碼好友代碼編碼成 QR 內容。
String encodeFamilyFriendQr(String code) => '$kFamilyFriendQrPrefix$code';

/// 解析掃描到的原始字串；不是 Uban 家屬好友 QR（字首不符）回傳 null。
String? decodeFamilyFriendQr(String raw) {
  if (!raw.startsWith(kFamilyFriendQrPrefix)) return null;
  return raw.substring(kFamilyFriendQrPrefix.length).trim();
}

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

enum _FamilyFriendMode { myCode, scan, search, manage }

class _FamilyAddFriendScreenState extends State<FamilyAddFriendScreen> {
  _FamilyFriendMode _mode = _FamilyFriendMode.myCode;

  String? _myCode;
  bool _isLoadingMyCode = true;

  MobileScannerController? _scannerController;
  bool _hasHandledScan = false;

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
    _scannerController?.dispose();
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
    // 離開任何分頁前一律先釋放掃描器（比照長輩端 elder_add_friend_screen.dart
    // 的 _switchMode）——鏡頭是稀缺資源，不能等下次切到「掃描」分頁時才發現
    // 舊的 controller 還沒關掉。
    _scannerController?.dispose();
    _scannerController = null;
    setState(() {
      _mode = mode;
      if (mode == _FamilyFriendMode.search || mode == _FamilyFriendMode.scan) {
        _searchResult = null;
        _searchError = null;
        _sendResultMessage = null;
        _hasHandledScan = false;
      }
    });
    if (mode == _FamilyFriendMode.scan) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    }
  }

  void _restartScan() {
    setState(() {
      _searchResult = null;
      _searchError = null;
      _sendResultMessage = null;
      _hasHandledScan = false;
    });
    _scannerController?.start();
  }

  void _onScanDetect(BarcodeCapture capture) {
    if (_hasHandledScan) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      _hasHandledScan = true;
      _scannerController?.stop();
      _handleScannedValue(raw.trim());
      break;
    }
  }

  Future<void> _handleScannedValue(String raw) async {
    final targetCode = decodeFamilyFriendQr(raw);
    if (targetCode == null) {
      setState(() => _searchError = '這不是 Uban 家屬好友的 QR 碼，請確認掃描的對象');
      return;
    }
    await _performSearch(targetCode);
  }

  Future<void> _shareMyCode() async {
    if (_myCode == null) return;
    // 見檔頭「誠實性要求」：目前沒有 deep link 能點了就自動加好友，文案只
    // 講代碼／QR，請對方手動輸入或掃描。
    final shareText = '【Uban 加好友】\n'
        '我是 ${widget.familyName}，我的 Uban 好友代碼是：${_myCode!}\n\n'
        '請在 Uban App 開啟「社群 → 朋友 → 我的好友」，用「搜尋加好友」輸入這組代碼，'
        '或直接掃描我分享的 QR 碼，即可送出好友邀請。';
    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: 'Uban 好友代碼',
      ),
    );
  }

  Future<void> _performSearch(String code) async {
    // ★ 第五十一輪：好友代碼改為 4 碼大寫英數字（排除易混淆的 0/O/1/I），
    // 不再只能是數字，原本的 int.tryParse 檢查會讓含英文字母的代碼一律
    // 搜尋不到。
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-Z]{4}$').hasMatch(normalized)) {
      setState(() => _searchError = '請輸入 4 碼的好友代碼');
      return;
    }
    if (_myCode != null && normalized == _myCode!.toUpperCase()) {
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
      familyCode: normalized,
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
        famSnackBar(context, accept ? '已成為好友' : '已拒絕邀請', success: accept),
      );
      if (accept) {
        // 剛成為好友，重新整理好友清單（也順便校正邀請清單）。
        _loadManageData();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        famSnackBar(context, FamilyFriendService.lastRespondError ?? '操作失敗，請稍後再試',
            error: true),
      );
    }
  }

  Future<void> _confirmRemoveFriend(Map<String, dynamic> friend) async {
    final rawId = friend['family_id'];
    final friendId = rawId is int ? rawId : int.tryParse('$rawId');
    if (friendId == null) return;
    final name = (friend['family_name'] ?? '這位好友').toString();
    final confirmed = await showUbanDialog<bool>(
      context,
      (ctx) {
        final c = UbanColors.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '解除好友'),
            const SizedBox(height: 10),
            Text('確定要解除與「$name」的好友關係嗎？',
                style: famText(c.text2, 15, height: 1.5)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.ghost,
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '解除',
                    kind: FamButtonKind.danger,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
      ScaffoldMessenger.of(context).showSnackBar(famSnackBar(context, '已解除好友關係'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        famSnackBar(context, FamilyFriendService.lastRemoveFriendError ?? '操作失敗，請稍後再試',
            error: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10：從好友動態頁 push 出來的新路由吃不到上層的家屬主題，這裡自己掛。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(context, title: '好友'),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeSwitcher(),
              const SizedBox(height: 16),
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

  /// 四分頁切換列（純文字分段控制；surface2 底、選取者 surface 底＋卡片陰影）。
  Widget _buildModeSwitcher() {
    final c = UbanColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeTab(_FamilyFriendMode.myCode, '我的代碼'),
            _modeTab(_FamilyFriendMode.scan, '掃描'),
            _modeTab(_FamilyFriendMode.search, '搜尋加好友'),
            _modeTab(_FamilyFriendMode.manage, '好友管理', badge: _requests.length),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(_FamilyFriendMode mode, String label, {int badge = 0}) {
    final c = UbanColors.of(context);
    final bool selected = _mode == mode;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _switchMode(mode),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected ? c.shadows.card : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(
                    selected ? c.brandStrong : c.text2,
                    13.5,
                    weight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                // 待回應邀請＝待處理 → 暖色數字膠囊。
                if (badge > 0) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: c.warmContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$badge 待回應',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.warm, 11, weight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeBody() {
    switch (_mode) {
      case _FamilyFriendMode.myCode:
        return _buildMyCodeBody();
      case _FamilyFriendMode.scan:
        return _buildScanBody();
      case _FamilyFriendMode.search:
        return _buildSearchBody();
      case _FamilyFriendMode.manage:
        return _buildManageBody();
    }
  }

  Widget _buildLoading([String? label]) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: c.brand, strokeWidth: 2.5),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(label, style: famText(c.text2, 14)),
            ],
          ],
        ),
      ),
    );
  }

  // ── 我的代碼 ──────────────────────────────────────────
  Widget _buildMyCodeBody() {
    final c = UbanColors.of(context);
    if (_isLoadingMyCode) return _buildLoading();
    if (_myCode == null) {
      return _buildInlineErrorBlock('目前無法取得您的好友代碼，請檢查網路後重試', _loadMyCode);
    }
    return Column(
      children: [
        FamCard(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text('我的好友代碼', style: famText(c.text2, 14, weight: FontWeight.w700)),
              const SizedBox(height: 10),
              // 4 碼定長字串搭配大字級展示，用 FittedBox 而非 ellipsis——
              // 代碼被截斷會誤導使用者（鐵律 #14 / 護欄 G159）。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _myCode!,
                  style: famText(c.brandStrong, 48,
                      weight: FontWeight.w900, letterSpacing: 10, tabular: true),
                ),
              ),
              const SizedBox(height: 18),
              // ★ 第五十二輪任務 C：QR 碼顯示，格式見 [encodeFamilyFriendQr]。
              // QR 一律白底（深色模式也要維持對比，掃描器才讀得到）。
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: encodeFamilyFriendQr(_myCode!),
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FamButton(
                label: '複製代碼',
                kind: FamButtonKind.outline,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _myCode!));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(famSnackBar(context, '已複製代碼'));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // ★ 第五十二輪任務 C：分享（share_plus），文案見 [_shareMyCode]。
              child: FamButton(label: '分享代碼', onPressed: _shareMyCode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '把這組代碼或 QR 碼分享給朋友。請對方在「搜尋加好友」輸入代碼，或用「掃描」對準您的 QR 碼，即可送出邀請',
          textAlign: TextAlign.center,
          style: famText(c.text2, 13.5, height: 1.5),
        ),
      ],
    );
  }

  // ── 掃描朋友 ────────────────────────────────────────────
  Widget _buildScanBody() {
    final c = UbanColors.of(context);
    if (_isSearching) return _buildLoading('查詢中…');
    if (_searchResult != null) {
      return Column(
        children: [
          _buildResultCard(),
          const SizedBox(height: 14),
          FamButton(
            label: '重新掃描',
            kind: FamButtonKind.ghost,
            onPressed: _restartScan,
          ),
        ],
      );
    }
    if (_hasHandledScan && _searchError != null) {
      return Column(
        children: [
          _buildErrorBanner(_searchError!),
          const SizedBox(height: 16),
          FamButton(label: '重新掃描', onPressed: _restartScan),
        ],
      );
    }
    return Column(
      children: [
        Text('把朋友的 Uban QR 碼對準框框',
            textAlign: TextAlign.center,
            style: famText(c.text, 15.5, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_scannerController != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 300,
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _onScanDetect,
              ),
            ),
          ),
      ],
    );
  }

  // ── 搜尋加好友 ────────────────────────────────────────
  Widget _buildSearchBody() {
    final c = UbanColors.of(context);
    return Column(
      children: [
        Text('輸入朋友的 4 碼好友代碼',
            style: famText(c.text, 15.5, weight: FontWeight.w700)),
        const SizedBox(height: 14),
        FamInput(
          controller: _searchController,
          keyboardType: TextInputType.text,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          maxLength: 4,
          height: 68,
          hintText: 'ABCD',
          inputFormatters: [
            // ★ 第五十一輪：好友代碼改為 4 碼大寫英數字（後端同步排除易混淆
            // 的 0/O/1/I），允許輸入英數字並即時轉大寫，不再限制只能輸入數字。
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
            LengthLimitingTextInputFormatter(4),
            TextInputFormatter.withFunction(
              (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
            ),
          ],
          style: famText(c.text, 32, weight: FontWeight.w900, letterSpacing: 8, tabular: true),
        ),
        const SizedBox(height: 14),
        FamButton(
          label: _isSearching ? '查詢中...' : '搜尋',
          loading: _isSearching,
          onPressed: _isSearching ? null : () => _performSearch(_searchController.text),
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
    final c = UbanColors.of(context);
    final data = _searchResult!;
    final name = (data['family_name'] ?? '家人').toString();
    final codeStr = (data['family_code'] ?? '').toString();
    final avatarUrl = data['avatar_url'] as String?;
    return FamCard(
      child: Column(
        children: [
          FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 36),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text, 17, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('代碼：$codeStr', style: famText(c.text2, 14, tabular: true)),
          const SizedBox(height: 16),
          if (_sendResultMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: c.brandContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              width: double.infinity,
              child: Text(
                _sendResultMessage!,
                textAlign: TextAlign.center,
                style: famText(c.brandStrong, 14, weight: FontWeight.w700, height: 1.4),
              ),
            )
          else
            FamButton(
              label: _isSendingRequest ? '送出中' : '加好友',
              loading: _isSendingRequest,
              onPressed: _isSendingRequest ? null : _sendRequest,
            ),
        ],
      ),
    );
  }

  // ── 好友管理（邀請＋清單） ──────────────────────────────
  Widget _buildManageBody() {
    final c = UbanColors.of(context);
    if (_isLoadingManage) return _buildLoading();
    if (_manageError != null && _requests.isEmpty && _friends.isEmpty) {
      return _buildInlineErrorBlock(_manageError!, _loadManageData);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_requests.isNotEmpty) ...[
          const FamSecHead(title: '待回應邀請'),
          const SizedBox(height: 10),
          ..._requests.map(_buildRequestCard),
          const SizedBox(height: 20),
        ],
        FamSecHead(title: '我的好友（${_friends.length}）'),
        const SizedBox(height: 10),
        if (_friends.isEmpty)
          FamCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '還沒有好友，去搜尋加好友試試看吧！',
                textAlign: TextAlign.center,
                style: famText(c.text2, 14.5, height: 1.5),
              ),
            ),
          )
        else
          ..._friends.map(_buildFriendCard),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final c = UbanColors.of(context);
    final rawId = request['request_id'];
    final requestId = rawId is int ? rawId : int.tryParse('$rawId');
    final isResponding = requestId != null && _respondingIds.contains(requestId);
    final name = (request['from_family_name'] ?? '家人').toString();
    final avatarUrl = request['avatar_url'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 22),
                const SizedBox(width: 10),
                // ★ 鐵律 #14 / 護欄 G159：姓名必須可收縮。
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.text, 15.5, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isResponding)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  FamSmallBtn(label: '拒絕', onTap: () => _respond(request, false)),
                  FamSmallBtn(label: '接受', filled: true, onTap: () => _respond(request, true)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final c = UbanColors.of(context);
    final rawId = friend['family_id'];
    final friendId = rawId is int ? rawId : int.tryParse('$rawId');
    final isRemoving = friendId != null && _removingIds.contains(friendId);
    final name = (friend['family_name'] ?? '家人').toString();
    final avatarUrl = friend['avatar_url'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FamCard(
        child: Row(
          children: [
            FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 22),
            const SizedBox(width: 10),
            // ★ 鐵律 #14 / 護欄 G159：同列有頭像＋解除按鈕，姓名必須可收縮。
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: famText(c.text, 15.5, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            isRemoving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                  )
                : FamSmallBtn(
                    label: '解除好友',
                    danger: true,
                    onTap: () => _confirmRemoveFriend(friend),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    final c = UbanColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.dangerContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: famText(c.danger, 14, weight: FontWeight.w700, height: 1.45),
      ),
    );
  }

  Widget _buildInlineErrorBlock(String message, VoidCallback onRetry) {
    final c = UbanColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: famText(c.text, 15, weight: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 14),
          FamButton(label: '重試', expand: false, onPressed: onRetry),
        ],
      ),
    );
  }
}
