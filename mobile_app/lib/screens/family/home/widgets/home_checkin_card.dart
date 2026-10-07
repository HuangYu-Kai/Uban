import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../globals.dart' show splashActive, pendingAcceptedCall;
import '../../../../models/elder.dart';
import '../../../../services/api/checkin_api.dart';
import '../../../../services/api_service.dart';
import '../../../../services/checkin_notification.dart';
import '../../../../services/signaling.dart' show Signaling;
import '../../../../widgets/ui/ui.dart';
import '../../sheets/send_cheer_sheet.dart';
import '../../widgets/fam_ui.dart';
import '../../../../utils/display_text.dart';

/// 家屬首頁「今日打卡」卡：長輩今天的目標／提醒完成進度（含長輩自建目標）。
///
/// 資料來自 `GET /api/reminder/elder/{id}/today-progress`（後端以台灣日期、與長輩端
/// 相同的「今天是否適用」規則計算）。家屬端沒有訂閱 `reminder-sync`（該回呼由長輩端畫面
/// 獨占），因此以「下拉重整（父層遞增 [refreshToken]）＋ 每 60 秒輕量輪詢」維持新鮮。
///
/// ★ 2026-10-07 打卡雙向互動：已完成項目可「鼓勵」（文字／語音，見 [SendCheerSheet]）、
/// 清單面板有近 7 天歷史、漏打卡可「打電話」；並消費 [CheckinNotification.pendingTap]
/// （點擊打卡通知後開啟對應面板）。
class HomeCheckinCard extends StatefulWidget {
  final Elder? currentElder;

  /// 父層下拉重整時遞增，卡片即重讀。
  final int refreshToken;

  /// 家屬 user id（送鼓勵、查已鼓勵用）；null 時退回 prefs 的 `caregiver_id`。
  final int? userId;

  /// 漏打卡時「打電話」的入口，沿用家屬首頁既有的一般視訊通話發起點（不重寫通話邏輯）。
  final VoidCallback? onStartVideoCall;

  const HomeCheckinCard({
    super.key,
    this.currentElder,
    this.refreshToken = 0,
    this.userId,
    this.onStartVideoCall,
  });

  @override
  State<HomeCheckinCard> createState() => _HomeCheckinCardState();
}

class _HomeCheckinCardState extends State<HomeCheckinCard> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _data;
  Timer? _timer;

  /// 今天已送過鼓勵的 reminder id（供「鼓勵／已鼓勵」狀態；讀取失敗時維持原值）。
  final ValueNotifier<Set<int>> _sent = ValueNotifier<Set<int>>(<int>{});

  String? get _elderId =>
      widget.currentElder?.elderId ?? widget.currentElder?.id.toString();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
    // 通知點擊：暖啟動由 CheckinNotification 設值；冷啟動這裡消費 launch details。
    CheckinNotification.pendingTap.addListener(_onPendingTap);
    unawaited(CheckinNotification.consumeLaunchTap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingTap());
  }

  @override
  void didUpdateWidget(covariant HomeCheckinCard old) {
    super.didUpdateWidget(old);
    if (old.currentElder?.elderId != widget.currentElder?.elderId ||
        old.currentElder?.id != widget.currentElder?.id ||
        old.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    CheckinNotification.pendingTap.removeListener(_onPendingTap);
    _sent.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final id = _elderId;
    if (id == null) {
      if (mounted) setState(() { _loading = false; _error = false; _data = null; });
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final d = await ApiService.getTodayProgress(id);
      if (!mounted) return;
      setState(() { _data = d; _loading = false; _error = false; });
      unawaited(_loadSent());
    } catch (_) {
      if (!mounted) return;
      // 輪詢失敗且已有資料時保留舊資料，不閃錯誤。
      setState(() { _loading = false; _error = _data == null; });
    }
  }

  List<Map<String, dynamic>> get _items => [
        for (final e in (_data?['items'] as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];

  /// 台灣日期 yyyy-MM-dd：優先用後端 today-progress 回的 `date`，否則自行換算（UTC+8）。
  String get _today {
    final d = _data?['date']?.toString();
    if (d != null && d.length == 10) return d;
    final t = DateTime.now().toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  Future<int?> _familyId() async {
    final fromWidget = widget.userId;
    if (fromWidget != null && fromWidget > 0) return fromWidget;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('caregiver_id');
      return (id != null && id > 0) ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSent() async {
    final id = _elderId;
    final fid = await _familyId();
    if (id == null || fid == null || !mounted) return;
    final ids = await CheckinApi.getSentReminderIds(
        familyId: fid, elderId: id, localDate: _today);
    if (ids != null && mounted) _sent.value = ids;
  }

  /// 開啟「送鼓勵」面板；成功後標記已鼓勵並提示。
  Future<void> _cheer({
    required int reminderId,
    required String title,
    String? localDate,
  }) async {
    final id = _elderId;
    final fid = await _familyId();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (id == null || fid == null) {
      messenger.showSnackBar(const SnackBar(content: Text('請重新登入後再試一次')));
      return;
    }
    final ok = await SendCheerSheet.show(
      context,
      elderName: widget.currentElder?.name ?? '長輩',
      itemTitle: stripEmoji(title),
      familyId: fid,
      elderId: id,
      reminderId: reminderId,
      localDate: localDate ?? _today,
    );
    if (ok) {
      if (mounted) _sent.value = {..._sent.value, reminderId};
      messenger.showSnackBar(const SnackBar(content: Text('已送出，長輩那邊會聽到')));
    }
  }

  void _openAll({String? missedTitle, String? missedTimeStr}) {
    final items = _items;
    final id = _elderId;
    final history = id == null
        ? Future<List<Map<String, dynamic>>?>.value(null)
        : CheckinApi.getHistory(elderId: id, familyId: widget.userId, days: 7);
    final name = widget.currentElder?.name ?? '長輩';
    showUbanSheet<void>(
      context,
      (ctx) => CheckinListSheet(
        items: items,
        sent: _sent,
        history: history,
        elderName: name,
        missedTitle: missedTitle,
        missedTimeStr: missedTimeStr,
        onCheer: (item) {
          final rid = (item['id'] as num?)?.toInt();
          if (rid == null) return;
          _cheer(reminderId: rid, title: item['title'].toString());
        },
        onCall: widget.onStartVideoCall == null
            ? null
            : () {
                Navigator.of(ctx).pop();
                widget.onStartVideoCall!();
              },
      ),
    );
  }

  // ───────── 通知點擊 → 開啟對應面板 ─────────

  bool _tapRunning = false;

  void _onPendingTap() {
    if (CheckinNotification.pendingTap.value == null || _tapRunning) return;
    _tapRunning = true;
    unawaited(_runPendingTap().whenComplete(() => _tapRunning = false));
  }

  bool _isThisElder(String tapElderId) {
    final e = widget.currentElder;
    if (e == null) return false;
    return tapElderId == e.elderId || tapElderId == e.id.toString();
  }

  /// 等到「Splash 結束、長輩與資料就緒」再導覽（上限約 20 秒）；來電／通話中一律放棄，
  /// 不疊在來電畫面前（比照安心提醒的點擊導航，護欄 G13）。
  Future<void> _runPendingTap() async {
    for (var i = 0; i < 40; i++) {
      final tap = CheckinNotification.pendingTap.value;
      if (tap == null || !mounted) return;
      if (pendingAcceptedCall.value != null || Signaling().isInCall) {
        CheckinNotification.pendingTap.value = null;
        return;
      }
      final ready = !splashActive &&
          widget.currentElder != null &&
          !(_loading && _data == null);
      if (ready) {
        CheckinNotification.pendingTap.value = null;
        if (!_isThisElder(tap.elderId)) return;
        // 若首頁上方蓋著別的畫面，先退回首頁（通話中已在上面排除）。
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) {
          Navigator.of(context).popUntil((r) => r == route);
        }
        if (tap.isMissed) {
          final match = _items.where((e) => e['id'] == tap.reminderId).toList();
          _openAll(
            missedTitle: tap.title,
            missedTimeStr:
                match.isEmpty ? null : match.first['time_str']?.toString(),
          );
        } else if (tap.reminderId != null &&
            !_sent.value.contains(tap.reminderId)) {
          await _cheer(
            reminderId: tap.reminderId!,
            title: tap.title,
            localDate: tap.localDate.isEmpty ? null : tap.localDate,
          );
        } else {
          _openAll();
        }
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    CheckinNotification.pendingTap.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final elderName = widget.currentElder?.name ?? '長輩';

    Widget body;
    if (_loading && _data == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brandFill),
          ),
        ),
      );
    } else if (_error) {
      body = Row(
        children: [
          Expanded(child: Text('暫時讀不到打卡進度', style: famText(c.text3, 14))),
          FamButton(
            label: '重試', kind: FamButtonKind.ghost, height: 40, expand: false,
            onPressed: _load,
          ),
        ],
      );
    } else {
      final items = _items;
      if (items.isEmpty) {
        body = Text('今天沒有安排的事項', style: famText(c.text3, 14));
      } else {
        final done = (_data?['done'] as num?)?.toInt() ?? 0;
        final total = (_data?['total'] as num?)?.toInt() ?? items.length;
        final pending = items.where((i) => i['completed'] != true).toList();
        final completed = items.where((i) => i['completed'] == true).toList();
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UbanProgressRing(done: done, total: total),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isEmpty)
                    Text('今天都完成了', style: famText(c.text, 16, weight: FontWeight.w800))
                  else ...[
                    Text('下一件', style: famText(c.text3, 12.5)),
                    Text(
                      '${pending.first['time_str']}　${stripEmoji(pending.first['title'].toString())}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 15.5, weight: FontWeight.w800, height: 1.3),
                    ),
                  ],
                  if (completed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final i in completed.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 15, color: c.brandStrong),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                stripEmoji(i['title'].toString()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: famText(c.text2, 13),
                              ),
                            ),
                            const SizedBox(width: 6),
                            CheckinCheerButton(
                              sent: _sent,
                              reminderId: (i['id'] as num?)?.toInt(),
                              onTap: () => _cheer(
                                reminderId: (i['id'] as num).toInt(),
                                title: i['title'].toString(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      }
    }

    return FamCard(
      onTap: (_data != null && _items.isNotEmpty) ? () => _openAll() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(
            title: '今日打卡',
            trailing: Text(elderName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: famText(c.text3, 13)),
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

/// 「鼓勵／已鼓勵」小按鈕（已鼓勵時為不可點的灰字）。
class CheckinCheerButton extends StatelessWidget {
  final ValueNotifier<Set<int>> sent;
  final int? reminderId;
  final VoidCallback onTap;
  const CheckinCheerButton({
    super.key,
    required this.sent,
    required this.reminderId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    if (reminderId == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Set<int>>(
      valueListenable: sent,
      builder: (_, ids, __) {
        final done = ids.contains(reminderId);
        return Material(
          color: done ? c.surface2 : c.brandContainer,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            key: ValueKey(done ? 'cheered_$reminderId' : 'cheer_$reminderId'),
            borderRadius: BorderRadius.circular(999),
            onTap: done ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                done ? '已鼓勵' : '鼓勵',
                maxLines: 1,
                style: famText(done ? c.text3 : c.brandStrong, 12.5,
                    weight: FontWeight.w700),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CheckinListSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ValueNotifier<Set<int>> sent;
  final Future<List<Map<String, dynamic>>?> history;
  final String elderName;
  final String? missedTitle;
  final String? missedTimeStr;
  final void Function(Map<String, dynamic> item) onCheer;
  final VoidCallback? onCall;

  const CheckinListSheet({
    super.key,
    required this.items,
    required this.sent,
    required this.history,
    required this.elderName,
    required this.onCheer,
    this.onCall,
    this.missedTitle,
    this.missedTimeStr,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final done = items.where((i) => i['completed'] == true).length;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FamSecHead(
            title: '今日打卡',
            trailing: FamChip(label: '$done／${items.length}', tone: FamTone.brand),
          ),
          const SizedBox(height: 8),
          if (missedTitle != null && missedTitle!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.warmContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // 長輩姓名／事項名稱長度不可控，必須可收縮（規則 14）。
                  Expanded(
                    child: Text(
                      '$elderName還沒完成「${stripEmoji(missedTitle!)}」'
                      '${missedTimeStr == null ? '' : '（原定 $missedTimeStr）'}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 14, weight: FontWeight.w700, height: 1.35),
                    ),
                  ),
                  if (onCall != null) ...[
                    const SizedBox(width: 8),
                    FamButton(
                      key: const ValueKey('missed_call'),
                      label: '打電話',
                      height: 40,
                      expand: false,
                      onPressed: onCall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          CheckinHistorySection(history: history),
          const SizedBox(height: 4),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    i['completed'] == true
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: i['completed'] == true ? c.brandStrong : c.text3,
                  ),
                  const SizedBox(width: 10),
                  Text(i['time_str'].toString(),
                      style: famText(c.text2, 14, weight: FontWeight.w700, tabular: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stripEmoji(i['title'].toString()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(
                        i['completed'] == true ? c.text3 : c.text, 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (i['created_by_role'] == 'elder') ...[
                    const SizedBox(width: 8),
                    const FamChip(label: '長輩自訂', tone: FamTone.info),
                  ],
                  if (i['completed'] == true) ...[
                    const SizedBox(width: 8),
                    CheckinCheerButton(
                      sent: sent,
                      reminderId: (i['id'] as num?)?.toInt(),
                      onTap: () => onCheer(i),
                    ),
                  ] else if (onCall != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: ValueKey('call_${i['id']}'),
                      tooltip: '打電話',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.call_rounded, size: 20, color: c.brandStrong),
                      onPressed: onCall,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 近 7 天歷史區塊：載入中不佔位、失敗／無資料時整段隱藏。
class CheckinHistorySection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>?> history;
  const CheckinHistorySection({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return FutureBuilder<List<Map<String, dynamic>>?>(
      future: history,
      builder: (_, snap) {
        final days = snap.data;
        if (days == null || days.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('近 7 天', style: famText(c.text3, 12.5, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              CheckinHistoryStrip(days: days),
            ],
          ),
        );
      },
    );
  }
}

/// 7 天小直條：星期＋當天完成／總數。全完成＝品牌色、部分＝暖色、全沒做＝警示色、當天無事項＝灰。
class CheckinHistoryStrip extends StatelessWidget {
  /// `[{date: 'yyyy-MM-dd', done: int, total: int}]`，舊→新。
  final List<Map<String, dynamic>> days;
  const CheckinHistoryStrip({super.key, required this.days});

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final shown = days.length > 7 ? days.sublist(days.length - 7) : days;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var idx = 0; idx < shown.length; idx++)
          Expanded(child: _col(c, shown[idx], idx == shown.length - 1)),
      ],
    );
  }

  Widget _col(UbanColors c, Map<String, dynamic> d, bool isLast) {
    final done = (d['done'] as num?)?.toInt() ?? 0;
    final total = (d['total'] as num?)?.toInt() ?? 0;
    final parsed = DateTime.tryParse(d['date']?.toString() ?? '');
    final label = parsed == null ? '' : _weekdays[parsed.weekday - 1];

    final Color bg;
    final Color fg;
    if (total == 0) {
      bg = c.surface2;
      fg = c.text3;
    } else if (done >= total) {
      bg = c.brandContainer;
      fg = c.brandStrong;
    } else if (done == 0) {
      bg = c.dangerContainer;
      fg = c.danger;
    } else {
      bg = c.warmContainer;
      fg = c.warm;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isLast ? '今' : label,
              maxLines: 1,
              style: famText(isLast ? c.text : c.text3, 12,
                  weight: isLast ? FontWeight.w800 : FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            key: ValueKey('hist_${d['date']}'),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                total == 0 ? '–' : '$done/$total',
                maxLines: 1,
                style: famText(fg, 12.5, weight: FontWeight.w800, tabular: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
