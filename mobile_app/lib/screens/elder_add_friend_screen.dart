import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/friend_service.dart';
import '../widgets/ui/ui.dart';
import 'elder_tabs/widgets/elder_social_widgets.dart';
import 'widgets/friend_avatar.dart';

/// 長輩「加好友」畫面（第四十一輪 item 3）。
///
/// 三種加好友方式（我的 QR 碼／掃描朋友／輸入 ID）在同一個畫面內用分頁切換，
/// 刻意不做成多層跳轉（使用者要求 UX 不過度複雜，像 LINE 的加好友頁）。
/// 掃描與搜尋共用同一份「查詢結果卡」與「送出邀請」邏輯。
///
/// QR 內容格式為 `uban-friend:<4位數elder_id>`（例如 `uban-friend:7545`）——
/// 刻意不只放裸數字，掃到非 Uban 好友碼（例如商店 QR、網址）時才能明確分辨
/// 並提示「這不是 Uban 好友的 QR 碼」，而不是誤把任意數字字串當成 elder_id 去查。
class ElderAddFriendScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderAddFriendScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderAddFriendScreen> createState() => _ElderAddFriendScreenState();
}

enum _AddFriendMode { myQr, scan, search }

class _ElderAddFriendScreenState extends State<ElderAddFriendScreen> {
  static const String _qrPrefix = 'uban-friend:';

  String? _myElderId;
  bool _isLoadingMyId = true;

  _AddFriendMode _mode = _AddFriendMode.myQr;

  MobileScannerController? _scannerController;
  bool _hasHandledScan = false;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isSendingRequest = false;
  Map<String, dynamic>? _searchResult;
  String? _searchError;
  String? _sendResultMessage;

  @override
  void initState() {
    super.initState();
    _loadMyElderId();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyElderId() async {
    setState(() => _isLoadingMyId = true);
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (!mounted) return;
    setState(() {
      _myElderId = id;
      _isLoadingMyId = false;
    });
  }

  void _switchMode(_AddFriendMode mode) {
    if (_mode == mode) return;
    _scannerController?.dispose();
    _scannerController = null;
    setState(() {
      _mode = mode;
      _searchResult = null;
      _searchError = null;
      _sendResultMessage = null;
      _hasHandledScan = false;
    });
    if (mode == _AddFriendMode.scan) {
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
    if (!raw.startsWith(_qrPrefix)) {
      setState(() => _searchError = '這不是 Uban 好友的 QR 碼，請確認掃描的對象');
      return;
    }
    final targetId = raw.substring(_qrPrefix.length).trim();
    await _performSearch(targetId);
  }

  Future<void> _performSearch(String targetId) async {
    if (_myElderId == null) return;
    // ★ 第五十一輪：好友代碼改為 4 碼大寫英數字（排除易混淆的 0/O/1/I），
    // 不再只能是數字——`elder_id` 本身也可能含英文字母（如 `tools_service.py`
    // 產生的 `E075`），原本的 int.tryParse 檢查會讓這類長輩一律搜尋不到。
    final normalized = targetId.toUpperCase();
    if (!RegExp(r'^[0-9A-Z]{4}$').hasMatch(normalized)) {
      setState(() => _searchError = '請輸入 4 碼的好友 ID');
      return;
    }
    if (normalized == (_myElderId ?? '').toUpperCase()) {
      setState(() {
        _searchError = '這是您自己的 ID，換一組朋友的 ID 試試看';
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
    final result = await FriendService.searchElder(
      elderId: normalized,
      requesterElderId: _myElderId!,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      if (result != null) {
        _searchResult = result;
      } else {
        _searchError = FriendService.lastSearchError ?? '查無此人';
      }
    });
  }

  Future<void> _sendRequest() async {
    if (_myElderId == null || _searchResult == null || _isSendingRequest) return;
    final targetId = _searchResult!['elder_id']?.toString();
    if (targetId == null) return;
    setState(() => _isSendingRequest = true);
    final ok = await FriendService.sendFriendRequest(
      fromElderId: _myElderId!,
      toElderId: targetId,
    );
    if (!mounted) return;
    setState(() {
      _isSendingRequest = false;
      _sendResultMessage =
          ok ? '已送出邀請，等待對方同意' : (FriendService.lastRequestError ?? '送出失敗，請稍後再試');
    });
  }

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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: UbanTopBar(title: '加好友'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildModeSwitcher(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: _buildModeBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 三模式切換：外觀換成 [UbanSegmented]，仍呼叫既有 [_switchMode]。
  Widget _buildModeSwitcher() {
    return UbanSegmented(
      labels: const ['我的條碼', '掃描', '輸入 ID'],
      index: _mode.index,
      onChanged: (i) => _switchMode(_AddFriendMode.values[i]),
    );
  }

  Widget _buildModeBody() {
    switch (_mode) {
      case _AddFriendMode.myQr:
        return _buildMyQrBody();
      case _AddFriendMode.scan:
        return _buildScanBody();
      case _AddFriendMode.search:
        return _buildSearchBody();
    }
  }

  Widget _buildLoadingBlock() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _buildIdUnavailable() => ElderErrorBlock(
        message: '目前無法取得您的好友 ID，請檢查網路後重試',
        onRetry: _loadMyElderId,
      );

  // ── 我的條碼 ──────────────────────────────────────────
  Widget _buildMyQrBody() {
    if (_isLoadingMyId) return _buildLoadingBlock();
    if (_myElderId == null) return _buildIdUnavailable();
    final c = UbanColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UbanCard(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          child: Column(
            children: [
              // 設計稿 `.qr`：QR 一律白底（深色模式也一樣，掃描器才讀得到）。
              Container(
                width: 190,
                height: 190,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: '$_qrPrefix$_myElderId',
                  version: QrVersions.auto,
                  size: 170,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              // 設計稿 `.bigid`：Poppins 52/600、字距 .18em；FittedBox 讓大字級也不溢位。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _myElderId!,
                  maxLines: 1,
                  style: ubanBrandText(52, FontWeight.w600, c.text, height: 1.2)
                      .copyWith(letterSpacing: 52 * .18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '把這組號碼唸給朋友聽，或讓朋友掃描上面的條碼',
          textAlign: TextAlign.center,
          style: ubanText(18, FontWeight.w500, c.text2, height: 1.55),
        ),
      ],
    );
  }

  // ── 掃描朋友 ────────────────────────────────────────────
  Widget _buildScanBody() {
    final c = UbanColors.of(context);
    if (_isLoadingMyId) return _buildLoadingBlock();
    if (_myElderId == null) return _buildIdUnavailable();
    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('查詢中…', style: ubanText(18, FontWeight.w500, c.text2)),
            ],
          ),
        ),
      );
    }
    if (_searchResult != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(),
          const SizedBox(height: 14),
          UbanButton(
            label: '重新掃描',
            icon: Icons.refresh_rounded,
            variant: UbanButtonVariant.tonal,
            onPressed: _restartScan,
          ),
        ],
      );
    }
    if (_hasHandledScan && _searchError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElderNoticeBanner(message: _searchError!),
          const SizedBox(height: 18),
          UbanButton(
            label: '重新掃描',
            icon: Icons.refresh_rounded,
            size: UbanButtonSize.xl,
            onPressed: _restartScan,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '把朋友的 Uban 條碼對準框框',
          textAlign: TextAlign.center,
          style: ubanText(18, FontWeight.w500, c.text2, height: 1.55),
        ),
        const SizedBox(height: 12),
        // 設計稿 `.scanbox`：深色底、圓角 24、白色四角框＋品牌色掃描線。
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 320,
            color: const Color(0xFF1A2420),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_scannerController != null)
                  MobileScanner(
                    controller: _scannerController!,
                    onDetect: _onScanDetect,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '無法開啟相機，請到手機設定允許 Uban 使用相機',
                          textAlign: TextAlign.center,
                          style: ubanText(18, FontWeight.w500, Colors.white,
                              height: 1.5),
                        ),
                      ),
                    ),
                  ),
                const _ScanFrameOverlay(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 輸入 ID ────────────────────────────────────────────
  Widget _buildSearchBody() {
    final c = UbanColors.of(context);
    if (_isLoadingMyId) return _buildLoadingBlock();
    if (_myElderId == null) return _buildIdUnavailable();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '輸入朋友的 4 碼 ID',
          textAlign: TextAlign.center,
          style: ubanText(18, FontWeight.w500, c.text2, height: 1.55),
        ),
        const SizedBox(height: 14),
        _IdInput(controller: _searchController),
        const SizedBox(height: 14),
        UbanButton(
          label: _isSearching ? '查詢中...' : '搜尋',
          icon: Icons.search_rounded,
          size: UbanButtonSize.xl,
          loading: _isSearching,
          onPressed: _isSearching
              ? null
              : () => _performSearch(_searchController.text.trim()),
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 14),
          ElderNoticeBanner(message: _searchError!),
        ],
        if (_searchResult != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(),
        ],
      ],
    );
  }

  // ── 共用元件 ────────────────────────────────────────────
  /// 設計稿 `.card > .person`：頭像 72、名字 24/900、ID 15、下方「加好友」大鈕。
  Widget _buildResultCard() {
    final c = UbanColors.of(context);
    final data = _searchResult!;
    final name = (data['elder_name'] ?? '長輩').toString();
    final idStr = (data['elder_id'] ?? '').toString();
    final avatarUrl = data['avatar_url'] as String?;
    return UbanCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(24, FontWeight.w900, c.text, height: 1.25),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID：$idStr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(16, FontWeight.w500, c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_sendResultMessage != null)
            ElderNoticeBanner(message: _sendResultMessage!, isError: false)
          else
            UbanButton(
              label: _isSendingRequest ? '送出中' : '加好友',
              icon: Icons.person_add_alt_1_rounded,
              size: UbanButtonSize.xl,
              loading: _isSendingRequest,
              onPressed: _isSendingRequest ? null : _sendRequest,
            ),
        ],
      ),
    );
  }
}

/// 設計稿 `.scanbox` 的疊層：四個白色轉角＋品牌色掃描線（2.2 秒來回；
/// 系統開啟「移除動畫」時掃描線停在中央）。純裝飾，不攔截觸控。
class _ScanFrameOverlay extends StatefulWidget {
  const _ScanFrameOverlay();

  @override
  State<_ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<_ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !reduceMotion(context)) {
      _started = true;
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    Widget corner({bool left = true, bool top = true}) {
      const side = BorderSide(color: Colors.white, width: 4);
      return Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border(
              left: left ? side : BorderSide.none,
              right: left ? BorderSide.none : side,
              top: top ? side : BorderSide.none,
              bottom: top ? BorderSide.none : side,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(left && top ? 14 : 0),
              topRight: Radius.circular(!left && top ? 14 : 0),
              bottomLeft: Radius.circular(left && !top ? 14 : 0),
              bottomRight: Radius.circular(!left && !top ? 14 : 0),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 60),
        child: LayoutBuilder(builder: (context, box) {
          return Stack(
            children: [
              corner(left: true, top: true),
              corner(left: false, top: true),
              corner(left: true, top: false),
              corner(left: false, top: false),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = reduceMotion(context)
                      ? .5
                      : Curves.easeInOut.transform(_ctrl.value);
                  return Positioned(
                    left: 8,
                    right: 8,
                    top: (box.maxHeight - 3) * (.08 + .82 * t),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: c.brand,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// 設計稿 `.idinput`：置中、Poppins 42/600、字距加大、高 84、自動轉大寫。
///
/// 輸入規則沿用第五十一輪：4 碼大寫英數字（後端排除易混淆的 0/O/1/I）。
class _IdInput extends StatefulWidget {
  final TextEditingController controller;

  const _IdInput({required this.controller});

  @override
  State<_IdInput> createState() => _IdInputState();
}

class _IdInputState extends State<_IdInput> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted && _focused != _node.hasFocus) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final radius = BorderRadius.circular(18);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _focused
            ? [BoxShadow(color: c.brand.withValues(alpha: .18), spreadRadius: 4)]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        keyboardType: TextInputType.text,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        maxLength: 4,
        cursorColor: c.brand,
        inputFormatters: [
          // ★ 第五十一輪：允許輸入英數字並即時轉大寫，不再限制只能輸入數字。
          FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
          LengthLimitingTextInputFormatter(4),
          TextInputFormatter.withFunction(
            (oldValue, newValue) =>
                newValue.copyWith(text: newValue.text.toUpperCase()),
          ),
        ],
        style: ubanBrandText(42, FontWeight.w600, c.text)
            .copyWith(letterSpacing: 42 * .2),
        decoration: InputDecoration(
          counterText: '',
          hintText: 'ABCD',
          hintStyle: ubanBrandText(42, FontWeight.w600, c.text3)
              .copyWith(letterSpacing: 42 * .2),
          filled: true,
          fillColor: c.surface,
          constraints: const BoxConstraints(minHeight: 84),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: border(_focused ? c.brand : c.line),
          enabledBorder: border(_focused ? c.brand : c.line),
          focusedBorder: border(c.brand),
        ),
      ),
    );
  }
}
