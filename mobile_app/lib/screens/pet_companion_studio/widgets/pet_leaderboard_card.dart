import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/friend_avatar.dart';
import '../services/pet_leaderboard_service.dart';

/// 🏆 寵物介面「好友排行榜」卡片。
///
/// 顯示範圍＝自己＋已接受好友（`GET /api/pet/leaderboard/{elder_id}`），名次
/// 與「跟上一名的差距」一律採用後端算好的值，本卡片不重新計算、不重新排序，
/// 只負責呈現與「預設前 10 名／展開看全部」的顯示狀態。
///
/// ⚠️ 鐵律 #14 / 護欄 G159：本 App 沒有鎖 `textScaler`，長輩常把系統字體調大。
/// 這一列同時擠著「名次＋頭像＋姓名＋體重＋差距」多個元素，姓名（長輩自訂、
/// 長度不可控）一律包 `Expanded`／`Flexible` + `ellipsis`；名次與體重數字
/// 用 `FittedBox(fit: BoxFit.scaleDown)` 包在固定寬度容器內，字級再放大也
/// 只會等比縮小、不會撐爆整列。
class PetLeaderboardCard extends StatefulWidget {
  /// 目前登入長輩自己的 elder_id；尚未解析出來前傳 null，卡片會顯示「載入中」
  /// 而不是直接打一支必定失敗的 API。
  final String? myElderId;

  /// 每次餵食／同步寵物體重成功或失敗後，由外層遞增此值以觸發重新讀取排行榜。
  /// 刻意不直接拿體重當觸發鍵——體重在 `setState` 當下就已經變了，但上傳到
  /// 後端是非同步的，若直接綁體重會在上傳完成「之前」就搶先刷新，看到舊名次。
  final int refreshTick;

  const PetLeaderboardCard({
    super.key,
    required this.myElderId,
    this.refreshTick = 0,
  });

  @override
  State<PetLeaderboardCard> createState() => _PetLeaderboardCardState();
}

class _PetLeaderboardCardState extends State<PetLeaderboardCard> {
  static const int _defaultVisibleCount = 10;

  bool _isLoading = true;
  Map<String, dynamic>? _data;
  String? _error;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PetLeaderboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myElderId != widget.myElderId ||
        oldWidget.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final eid = widget.myElderId;
    if (eid == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _data = null;
          _error = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    final result = await PetLeaderboardService.getLeaderboard(eid);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _data = result;
      _error = result == null
          ? (PetLeaderboardService.lastLeaderboardError ?? '排行榜載入失敗，請稍後再試')
          : null;
    });
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String _formatKg(int grams) => '${(grams / 1000.0).toStringAsFixed(1)} kg';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text('🏆', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '好友寵物排行榜',
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF451A03),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!_isLoading)
          InkWell(
            onTap: _load,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.refresh_rounded, size: 22, color: Color(0xFF92400E)),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (widget.myElderId == null) {
      return _buildInfoLine('登入資料載入中，稍後即可看到好友排行榜…');
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: Color(0xFFD97706))),
      );
    }
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoLine(_error!),
          const SizedBox(height: 10),
          _buildRetryButton(),
        ],
      );
    }

    final entries = ((_data?['entries'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (entries.isEmpty) {
      return _buildInfoLine('目前還沒有好友同步寵物體重，加好友、多餵食就會出現在這裡！🐷');
    }

    final int? myRank = _asInt(_data?['my_rank']);
    final int totalCount = _asInt(_data?['total_count']) ?? entries.length;

    final int visibleCount = _expanded
        ? entries.length
        : (entries.length < _defaultVisibleCount ? entries.length : _defaultVisibleCount);
    final visibleEntries = entries.sublist(0, visibleCount);

    final bool selfInVisible = visibleEntries.any((e) => e['is_me'] == true);
    Map<String, dynamic>? selfEntry;
    if (!selfInVisible) {
      for (final e in entries) {
        if (e['is_me'] == true) {
          selfEntry = e;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (myRank != null) ...[
          // totalCount<=1 代表榜上只有自己（還沒加好友，或好友都還沒同步過
          // 寵物體重）——「共 1 位好友較勁中」會誤導長輩以為真的有一位對手，
          // 改用不需要名次感的鼓勵文案。
          if (totalCount <= 1)
            _buildInfoLine('你是目前唯一上榜的小豬主人，等好友也開始養小豬，就能互相比較體重囉！🐷')
          else
            Text(
              '你目前第 $myRank 名（共 $totalCount 位好友較勁中）',
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF92400E),
              ),
            ),
          const SizedBox(height: 10),
        ] else ...[
          // my_rank 為 null 代表自己還沒同步過寵物體重（entries 裡沒有
          // is_me==true 的項目）——這裡明確提示原因，避免長輩誤以為是錯誤，
          // 也不會出現「第 null 名」這種字樣。
          _buildInfoLine('你的寵物體重還沒同步上榜，先去餵食一次，就會出現在排行榜裡囉！🐷'),
          const SizedBox(height: 10),
        ],
        for (final e in visibleEntries) _buildRow(e),
        if (entries.length > _defaultVisibleCount)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: const Color(0xFFB45309),
              ),
              label: Text(
                _expanded ? '收合排行榜' : '展開看全部（共 ${entries.length} 位）',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB45309),
                ),
              ),
            ),
          ),
        if (selfEntry != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFEADBCE), thickness: 1.2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '你的名次',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFEADBCE), thickness: 1.2)),
            ],
          ),
          const SizedBox(height: 8),
          _buildRow(selfEntry),
        ],
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> entry) {
    final bool isMe = entry['is_me'] == true;
    final int rank = _asInt(entry['rank']) ?? 0;
    final int weight = _asInt(entry['weight_grams']) ?? 0;
    final int? gap = _asInt(entry['gap_from_previous_grams']);
    final String? rawName = entry['elder_name'] as String?;
    final String name = (rawName != null && rawName.trim().isNotEmpty)
        ? rawName
        : '長輩 ${entry['elder_id'] ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFFFFBEB) : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMe ? const Color(0xFFF59E0B) : const Color(0xFFEADBCE),
          width: isMe ? 2.2 : 1.2,
        ),
      ),
      child: Row(
        children: [
          // 名次徽章：固定 34x34 容器 + FittedBox，兩位數以上的名次也不會撐爆。
          SizedBox(
            width: 34,
            height: 34,
            child: FittedBox(fit: BoxFit.scaleDown, child: _buildRankBadge(rank)),
          ),
          const SizedBox(width: 10),
          FriendAvatar(avatarUrl: entry['avatar_url'] as String?, name: name, radius: 18),
          const SizedBox(width: 10),
          // 姓名是長輩自訂、長度不可控的動態字串——用 Expanded 讓它可收縮，
          // 同列不論擠了幾個徽章／數字，姓名都只會被裁切成「…」不會溢位。
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 17,
                      fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                      color: const Color(0xFF451A03),
                    ),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '你',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 體重／差距也一律包 FittedBox：判準是「字級 × 同列元素數」，不是
          // 「字串是不是動態」——就算數字本身有位數上限，系統字級被調到最大時
          // 一樣可能把整列撐爆，固定寬度容器 + FittedBox 是最後一道防線。
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatKg(weight),
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF78350F),
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (gap != null && gap > 0) ? '距上一名 ${(gap / 1000.0).toStringAsFixed(1)} kg' : '目前第一名 🥇',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: (gap != null && gap > 0) ? const Color(0xFF94A3B8) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (rank) {
      case 1:
        label = '🥇';
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case 2:
        label = '🥈';
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        break;
      case 3:
        label = '🥉';
        bg = const Color(0xFFFFF1E6);
        fg = const Color(0xFF9A3412);
        break;
      default:
        label = '#$rank';
        bg = const Color(0xFFF1EBE1);
        fg = const Color(0xFF78350F);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.w900, color: fg),
      ),
    );
  }

  Widget _buildInfoLine(String text) {
    return Text(
      text,
      style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF854D0E)),
    );
  }

  Widget _buildRetryButton() {
    return TextButton.icon(
      onPressed: _load,
      icon: const Icon(Icons.refresh_rounded, color: Color(0xFFB45309)),
      label: Text(
        '重新整理',
        style: GoogleFonts.notoSansTc(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
      ),
    );
  }
}
