import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../services/friend_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../pet_companion_studio/services/garden_ambient_audio_service.dart';
import '../../../pet_companion_studio/services/pet_progress_service.dart';
import '../../../pet_companion_studio/widgets/pet_leaderboard_card.dart';
import '../../../pet_companion_studio/widgets/pet_season_card.dart';

/// 🗓️🏆🎵 小豬之家右上角懸浮膠囊群：賽季／好友排行榜／背景音樂控制。
///
/// 從 `PetStudioScreen._buildLeaderboardButton`／`_buildMusicControlButton`
/// （連同各自開啟的 `_showLeaderboardSheet`／`_showMusicSettingsSheet`）
/// 逐一複製抽離而成，樣式與互動邏輯保持一致；差別只在本元件自己負責解析
/// elder_id、載入賽季資訊、持有一份背景音樂服務——呼叫端不需要額外傳入
/// 這些資料／服務。賽季那一顆本來也是複製，第五十一輪改成與
/// `PetStudioScreen` 共用同一個 [PetSeasonCard]（見該檔說明），不再各自
/// 維護一份。
///
/// ⚠️ `pet_studio_screen.dart` 仍是 `lib/main_pet_preview.dart` 使用中的
/// 獨立入口畫面，本元件（除了共用的 [PetSeasonCard] 之外）是「複製」而非
/// 「搬走」，該檔其餘部分未被改動。
class PetCornerActions extends StatefulWidget {
  /// 登入使用者的資料庫整數 PK，用來解析好友排行榜要用的 elder_id
  /// （見 `PetStudioScreen.userId` 的欄位說明——這不是 elder_id 本身，
  /// 兩者是資料庫中兩個獨立欄位，一律靠 [FriendService.resolveMyElderId]
  /// 換出權威值，不可補零臆測）。
  final int userId;

  /// 窄螢幕（手機直向）用的精簡樣式：三顆改為純圖示的圓鈕橫排。
  /// 完整文字版在 360px 寬度下會吃掉超過一半的橫向空間，把問候語擠成
  /// 「晚…」，賽季膠囊也會壓到小豬的對話氣泡。
  final bool compact;

  /// ⚠️ 僅供 widget test 注入假賽季資料使用。production 呼叫端
  /// （`elder_profile_tab.dart`／`pet_studio_screen.dart`）恆不傳這個
  /// 欄位，不影響任何現有行為。
  ///
  /// 背景：`_loadSeason()` 打的是真實 `GET /api/pet/season`，
  /// `flutter test` 的 `TestWidgetsFlutterBinding` 會攔截所有 HTTP 請求
  /// 並一律回傳失敗（比照 `elder_home_tab_news_visibility_test.dart` 檔頭
  /// 說明），導致 `_season` 恆為 null、賽季圖示與本彈窗永遠不會被建出來
  /// ——沒有這個欄位就無法用 widget test 驗證第五十三輪 item 6 新增的
  /// 說明彈窗。
  @visibleForTesting
  final PetSeasonInfo? debugInitialSeasonForTest;

  const PetCornerActions({
    super.key,
    required this.userId,
    this.compact = false,
    this.debugInitialSeasonForTest,
  });

  @override
  State<PetCornerActions> createState() => _PetCornerActionsState();
}

class _PetCornerActionsState extends State<PetCornerActions> {
  String? _myElderId;
  final int _leaderboardRefreshTick = 0;
  PetSeasonInfo? _season;

  final GardenAmbientAudioService _audioService = GardenAmbientAudioService();

  @override
  void initState() {
    super.initState();
    _resolveElderId();
    // ⚠️ 見 `widget.debugInitialSeasonForTest` 欄位說明：僅供 widget test
    // 注入假資料，production 呼叫端恆為 null，行為與原本完全相同。
    final debugSeason = widget.debugInitialSeasonForTest;
    if (debugSeason != null) {
      _season = debugSeason;
    } else {
      _loadSeason();
    }
    _audioService.initAndStartAmbience();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _resolveElderId() async {
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (mounted) setState(() => _myElderId = id);
  }

  /// 載入目前生效中的賽季資訊（`GET /api/pet/season`）。失敗時 [_season]
  /// 保持 null，`build` 直接不渲染賽季膠囊，不顯示編造的數字。
  Future<void> _loadSeason() async {
    final season = await PetProgressService.loadSeason();
    if (mounted && season != null) {
      setState(() => _season = season);
    }
  }

  /// 🗓️ 賽季說明彈窗（精簡橫排模式下點擊賽季圖示的入口）。
  ///
  /// 第五十三輪 item 6 之前：精簡模式點下去只會彈出 2 秒鐘就自動消失的
  /// [SnackBar]（走 [_showSnackToast]、預設字級，內容僅「第 N 季，還剩 N
  /// 天」），長輩既看不清楚幾個字，也看不懂這跟自己有什麼關係、時間到了
  /// 會怎樣——這正是本輪使用者回報「僅顯示『第一季，還有 XX 天』」的來源。
  /// 非精簡模式（橫屏／`pet_studio_screen.dart`）其實早就换成了圖文並茂、
  /// 白話說明的 [PetSeasonCard]，只是精簡模式這個進入點沒有跟著換。
  ///
  /// 修法：直接重用 [PetSeasonCard]（[ElderScale.seasonTitle] 24pt／
  /// [ElderScale.seasonSubtitle] 20pt／[ElderScale.caption] 18pt 的白話
  /// 說明句「時間到會結算排名，小豬會從頭養起」），改成長輩自己按「知道了」
  /// 才會關閉的彈出對話框，不再受 2 秒自動消失的時間壓力限制。
  void _showSeasonInfoDialog() {
    if (_season == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PetSeasonCard(season: _season!, maxWidth: 320),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                '知道了',
                style: ElderScale.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompactRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_season != null) ...[
          PetSeasonCard(season: _season!),
          const SizedBox(height: 10),
        ],
        _buildLeaderboardButton(),
        const SizedBox(height: 10),
        _buildMusicControlButton(),
      ],
    );
  }

  /// 精簡橫排：三顆 40px 圓形圖示鈕，總寬約 136px，
  /// 讓問候語在 360px 寬度下仍有足夠空間完整顯示。
  Widget _buildCompactRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_season != null) ...[
          _buildIconPill(
            emoji: '🗓️',
            borderColor: const Color(0xFFBBF7D0),
            glowColor: const Color(0xFF059669),
            tooltip:
                '第 ${_season!.seasonNo} 季 · 還剩 ${_season!.daysRemaining} 天',
            onTap: () {
              HapticFeedback.lightImpact();
              // ★ 第五十三輪 item 6：改彈出說明對話框（見 [_showSeasonInfoDialog]
              // 檔頭說明），不再用看不清楚也來不及讀完的 2 秒 SnackBar。
              _showSeasonInfoDialog();
            },
          ),
          const SizedBox(width: 8),
        ],
        _buildIconPill(
          emoji: '🏆',
          borderColor: const Color(0xFFFDE68A),
          glowColor: const Color(0xFFF59E0B),
          tooltip: '排行榜',
          onTap: () {
            HapticFeedback.lightImpact();
            _showLeaderboardSheet();
          },
        ),
        const SizedBox(width: 8),
        _buildIconPill(
          emoji: _audioService.isMuted ? '🔇' : '🎵',
          borderColor: const Color(0xFFDDD6FE),
          glowColor: const Color(0xFF7C3AED),
          tooltip: _audioService.isMuted ? '背景音樂：關' : '背景音樂：開',
          onTap: () async {
            HapticFeedback.lightImpact();
            await _audioService.toggleMute();
            if (!mounted) return;
            setState(() {});
            _showSnackToast(
              _audioService.isMuted
                  ? '🔇 背景音樂已靜音'
                  : '🎵 背景音樂已開啟（${_audioService.currentTrack.title}）',
            );
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showMusicSettingsSheet();
          },
        ),
      ],
    );
  }

  Widget _buildIconPill({
    required String emoji,
    required Color borderColor,
    required Color glowColor,
    required String tooltip,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
        shape: CircleBorder(side: BorderSide(color: borderColor, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 17)),
            ),
          ),
        ),
      ),
    );
  }

  // 🗓️ 頂部賽季卡片：實際內容抽到共用元件 [PetSeasonCard]（與
  // `pet_studio_screen.dart` 共用，理由見該元件檔案說明），本檔不再自己
  // 維護一份複製。

  // 🏆 頂部排行榜控制膠囊按鈕（開啟好友寵物排行榜面板）
  Widget _buildLeaderboardButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _showLeaderboardSheet();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 6),
              Text(
                '排行榜',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF92400E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🏆 開啟好友寵物排行榜面板（內容沿用 [PetLeaderboardCard]）。
  //
  // 用 ConstrainedBox 限制最高螢幕高度 82% 再包 SingleChildScrollView──
  // PetLeaderboardCard 展開「看全部」時列數不固定，好友數多或系統字級被
  // 長輩調大時都可能超出可視高度，這裡是最後一道防線（鐵律 #14／護欄 G159）。
  void _showLeaderboardSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              child: PetLeaderboardCard(
                myElderId: _myElderId,
                refreshTick: _leaderboardRefreshTick,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🎵 頂部音樂控制膠囊按鈕
  Widget _buildMusicControlButton() {
    final bool isMuted = _audioService.isMuted;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isMuted ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isMuted
                  ? Colors.black.withValues(alpha: 0.05)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 點擊直接切換開/關
            InkWell(
              onTap: () async {
                HapticFeedback.lightImpact();
                await _audioService.toggleMute();
                setState(() {});
                _showSnackToast(
                  _audioService.isMuted
                      ? '🔇 背景音樂已靜音'
                      : '🎵 背景音樂已開啟（${_audioService.currentTrack.title}）',
                );
              },
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isMuted
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMuted
                            ? Icons.music_off_rounded
                            : Icons.music_note_rounded,
                        color: isMuted
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFFD97706),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isMuted ? '音樂：關' : '音樂：開',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isMuted
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF78350F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 分隔細線
            Container(
              width: 1.2,
              height: 18,
              color: const Color(0xFFEADBCE),
            ),
            // 設定/曲目選擇按鈕
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showMusicSettingsSheet();
              },
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(24)),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(9, 9, 14, 9),
                child: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎼 背景音樂曲目與音量設定面板
  void _showMusicSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final isMuted = _audioService.isMuted;
          final currentTrackId = _audioService.currentTrackId;
          final volume = _audioService.volume;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF78350F).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 標題與關閉
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🎵', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '背景音樂設定',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF451A03),
                            ),
                          ),
                          Text(
                            '柔和悠揚的田園樂章，陪伴長輩與小豬',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12.5,
                              color: const Color(0xFF8C6D58),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF78350F)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 1. 音樂總開關 Switch
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMuted
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isMuted
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFFFDE68A),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: isMuted
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFFD97706),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMuted ? '音樂已靜音' : '背景音樂播放中',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isMuted
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF78350F),
                              ),
                            ),
                            Text(
                              isMuted ? '點擊右側開關即可開啟音樂' : '保持輕柔舒緩的田園陪伴',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !isMuted,
                        activeThumbColor: const Color(0xFFD97706),
                        activeTrackColor: const Color(0xFFFDE68A),
                        onChanged: (val) async {
                          HapticFeedback.lightImpact();
                          await _audioService.toggleMute();
                          setModalState(() {});
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. 音量拉桿（開啟狀態才顯示）
                if (!isMuted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '音量調節',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '${(volume * 100).round()}%',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFD97706),
                      inactiveTrackColor: const Color(0xFFF1EBE1),
                      thumbColor: const Color(0xFFD97706),
                      overlayColor:
                          const Color(0xFFD97706).withValues(alpha: 0.15),
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: volume,
                      min: 0.05,
                      max: 1.0,
                      onChanged: (val) async {
                        await _audioService.setVolume(val);
                        setModalState(() {});
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 3. 曲目清單選擇
                Text(
                  '選擇柔和曲目',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF78350F),
                  ),
                ),
                const SizedBox(height: 8),

                ...GardenAmbientAudioService.availableTracks.map((track) {
                  final bool isSelected = currentTrackId == track.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        await _audioService.setTrack(track.id);
                        setModalState(() {});
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFFBEB)
                              : const Color(0xFFFAF7F2),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEADBCE),
                            width: isSelected ? 2.0 : 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(track.emoji,
                                style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        track.title,
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? const Color(0xFF78350F)
                                              : const Color(0xFF451A03),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFFEF3C7)
                                              : const Color(0xFFF1EBE1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          track.durationText,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF78350F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.description,
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 12,
                                      color: const Color(0xFF8C6D58),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFFD97706),
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
