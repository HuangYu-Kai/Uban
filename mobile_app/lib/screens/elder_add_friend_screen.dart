import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/friend_service.dart';
import '../theme/app_theme.dart';
import 'widgets/friend_avatar.dart';

/// 長輩「加朋友」畫面（第四十一輪 item 3）。
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
    if (targetId.length != 4 || int.tryParse(targetId) == null) {
      setState(() => _searchError = '請輸入 4 位數的好友 ID');
      return;
    }
    if (targetId == _myElderId) {
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
      elderId: targetId,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '加朋友',
          style: GoogleFonts.notoSansTc(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeSwitcher(),
              const SizedBox(height: 20),
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _modeTab(_AddFriendMode.myQr, Icons.qr_code_rounded, '我的 QR 碼'),
          _modeTab(_AddFriendMode.scan, Icons.qr_code_scanner_rounded, '掃描朋友'),
          _modeTab(_AddFriendMode.search, Icons.pin_rounded, '輸入 ID'),
        ],
      ),
    );
  }

  Widget _modeTab(_AddFriendMode mode, IconData icon, String label) {
    final bool selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _switchMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 26,
                  color: selected ? AppColors.primaryDark : AppColors.textHint),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
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
      case _AddFriendMode.myQr:
        return _buildMyQrBody();
      case _AddFriendMode.scan:
        return _buildScanBody();
      case _AddFriendMode.search:
        return _buildSearchBody();
    }
  }

  // ── 我的 QR 碼 ──────────────────────────────────────────
  Widget _buildMyQrBody() {
    if (_isLoadingMyId) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myElderId == null) {
      return _buildInlineErrorBlock(
        '目前無法取得您的好友 ID，請檢查網路後重試',
        _loadMyElderId,
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: QrImageView(
            data: '$_qrPrefix$_myElderId',
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _myElderId!,
          style: GoogleFonts.inter(
            fontSize: 56,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '把這組號碼唸給朋友，或讓朋友掃描上面的 QR 碼',
          textAlign: TextAlign.center,
          style: ElderScale.caption,
        ),
      ],
    );
  }

  // ── 掃描朋友 ────────────────────────────────────────────
  Widget _buildScanBody() {
    if (_isLoadingMyId) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myElderId == null) {
      return _buildInlineErrorBlock(
        '目前無法取得您的好友 ID，請檢查網路後重試',
        _loadMyElderId,
      );
    }
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('查詢中…'),
            ],
          ),
        ),
      );
    }
    if (_searchResult != null) {
      return Column(
        children: [
          _buildResultCard(),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _restartScan,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('重新掃描', style: ElderScale.caption),
          ),
        ],
      );
    }
    if (_hasHandledScan && _searchError != null) {
      return Column(
        children: [
          _buildErrorBanner(_searchError!),
          const SizedBox(height: 20),
          SizedBox(
            height: ElderScale.buttonHeight,
            child: ElevatedButton.icon(
              onPressed: _restartScan,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('重新掃描', style: ElderScale.button.copyWith(color: Colors.white, fontSize: 22)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Text(
          '把朋友的 Uban QR 碼對準框框',
          textAlign: TextAlign.center,
          style: ElderScale.body,
        ),
        const SizedBox(height: 12),
        if (_scannerController != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 340,
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _onScanDetect,
              ),
            ),
          ),
      ],
    );
  }

  // ── 輸入 ID ────────────────────────────────────────────
  Widget _buildSearchBody() {
    if (_isLoadingMyId) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myElderId == null) {
      return _buildInlineErrorBlock(
        '目前無法取得您的好友 ID，請檢查網路後重試',
        _loadMyElderId,
      );
    }
    return Column(
      children: [
        Text('輸入朋友的 4 位數 ID', style: ElderScale.body),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 4,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '0000',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: ElderScale.buttonHeight,
          child: ElevatedButton.icon(
            onPressed: _isSearching
                ? null
                : () => _performSearch(_searchController.text.trim()),
            icon: _isSearching
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.search_rounded, size: 28),
            label: Text(
              _isSearching ? '查詢中...' : '搜尋',
              style: ElderScale.button.copyWith(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(_searchError!),
        ],
        if (_searchResult != null) ...[
          const SizedBox(height: 20),
          _buildResultCard(),
        ],
      ],
    );
  }

  // ── 共用元件 ────────────────────────────────────────────
  Widget _buildResultCard() {
    final data = _searchResult!;
    final name = (data['elder_name'] ?? '長輩').toString();
    final idStr = (data['elder_id'] ?? '').toString();
    final avatarUrl = data['avatar_url'] as String?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          FriendAvatar(avatarUrl: avatarUrl, name: name, radius: 44),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ElderScale.body.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text('ID：$idStr', style: ElderScale.caption),
          const SizedBox(height: 18),
          if (_sendResultMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              width: double.infinity,
              child: Text(
                _sendResultMessage!,
                textAlign: TextAlign.center,
                style: ElderScale.caption.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: ElderScale.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: _isSendingRequest ? null : _sendRequest,
                icon: _isSendingRequest
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 28),
                label: Text(
                  _isSendingRequest ? '送出中' : '加好友',
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
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ElderScale.caption.copyWith(color: const Color(0xFFB91C1C)),
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
          const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: ElderScale.body),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}
