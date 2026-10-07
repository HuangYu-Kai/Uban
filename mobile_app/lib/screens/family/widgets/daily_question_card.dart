import 'dart:async';

import 'package:flutter/material.dart';

import '../../../globals.dart' show splashActive, pendingAcceptedCall;
import '../../../models/elder.dart';
import '../../../services/api/daily_question_api.dart';
import '../../../services/checkin_notification.dart';
import '../../../services/signaling.dart' show Signaling;
import '../../../widgets/ui/ui.dart';
import '../daily_question_screen.dart';
import 'fam_interaction_ui.dart';
import 'fam_ui.dart';

/// 讀取今日題目的簽名（測試可注入；預設走 [DailyQuestionApi.getToday]）。
typedef DailyTodayLoader = Future<DailyQuestionItem?> Function(String elderId);

/// ★ 2026-10-07 每日一問：家屬互動分頁的「每日一問」卡片。
///
/// 顯示今天的題目與長輩是否已回答（含回答摘要、語音 🔊），按鈕「出一題給長輩」「看全部」。
/// 家屬互動分頁在 IndexedStack 內被保活，因此靠父層遞增 [refreshToken]（收到 `daily-answer`
/// Socket 時）重讀，並在返回／出題成功後自行重讀。同時消費
/// [CheckinNotification.pendingDailyTap]：點擊「長輩回答了」通知 → 開啟 [DailyQuestionScreen]
/// 並定位到該題（作法比照首頁打卡卡片，來電／通話中一律放棄）。
class DailyQuestionCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;
  final int refreshToken;

  /// 測試注入點；null 時使用真實 API。
  final DailyTodayLoader? loader;

  /// 測試注入點：給 [DailyQuestionScreen] 的歷史載入器。
  final DailyHistoryLoader? historyLoader;

  /// 測試注入點：出題。
  final DailyAsker? asker;

  const DailyQuestionCard({
    super.key,
    required this.currentElder,
    this.userId,
    this.refreshToken = 0,
    this.loader,
    this.historyLoader,
    this.asker,
  });

  @override
  State<DailyQuestionCard> createState() => _DailyQuestionCardState();
}

class _DailyQuestionCardState extends State<DailyQuestionCard> {
  bool _loading = true;
  bool _error = false;
  DailyQuestionItem? _item;

  String? get _elderId =>
      widget.currentElder?.elderId ?? widget.currentElder?.id.toString();
  String get _elderName => widget.currentElder?.displayName ?? '長輩';

  @override
  void initState() {
    super.initState();
    _load();
    CheckinNotification.pendingDailyTap.addListener(_onPendingTap);
    unawaited(CheckinNotification.consumeDailyLaunchTap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingTap());
  }

  @override
  void didUpdateWidget(covariant DailyQuestionCard old) {
    super.didUpdateWidget(old);
    final oldId = old.currentElder?.elderId ?? old.currentElder?.id.toString();
    if (widget.refreshToken != old.refreshToken) {
      _load(silent: true);
    } else if (oldId != _elderId) {
      _load();
    }
  }

  @override
  void dispose() {
    CheckinNotification.pendingDailyTap.removeListener(_onPendingTap);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final id = _elderId;
    if (id == null) return;
    if (!silent && mounted) setState(() => _loading = true);
    DailyQuestionItem? item;
    try {
      item = widget.loader != null
          ? await widget.loader!(id)
          : await DailyQuestionApi.getToday(elderId: id);
    } catch (_) {
      item = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 靜默重讀失敗時保留舊資料，不要把畫面變成錯誤。
      if (item != null) {
        _item = item;
        _error = false;
      } else if (_item == null) {
        _error = true;
      }
    });
  }

  // ───────── 通知點擊 → 開啟每日一問 ─────────

  bool _tapRunning = false;

  void _onPendingTap() {
    if (CheckinNotification.pendingDailyTap.value == null || _tapRunning) return;
    _tapRunning = true;
    unawaited(_runPendingTap().whenComplete(() => _tapRunning = false));
  }

  bool _isThisElder(String tapElderId) {
    final e = widget.currentElder;
    if (e == null) return false;
    return tapElderId == e.elderId || tapElderId == e.id.toString();
  }

  /// 等到「Splash 結束、長輩就緒」再導覽（上限約 20 秒）；來電／通話中一律放棄，
  /// 不疊在來電畫面前（比照打卡通知的點擊導航，護欄 G13）。
  Future<void> _runPendingTap() async {
    for (var i = 0; i < 40; i++) {
      final tap = CheckinNotification.pendingDailyTap.value;
      if (tap == null || !mounted) return;
      if (pendingAcceptedCall.value != null || Signaling().isInCall) {
        CheckinNotification.pendingDailyTap.value = null;
        return;
      }
      if (!splashActive && widget.currentElder != null) {
        CheckinNotification.pendingDailyTap.value = null;
        if (!_isThisElder(tap.elderId)) return;
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) {
          Navigator.of(context).popUntil((r) => r == route);
        }
        await _openAll(questionId: tap.questionId);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    CheckinNotification.pendingDailyTap.value = null;
  }

  // ───────── 動作 ─────────

  Future<void> _openAll({int? questionId}) async {
    final id = _elderId;
    if (id == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DailyQuestionScreen(
        elderId: id,
        elderName: _elderName,
        familyId: widget.userId,
        initialQuestionId: questionId,
        historyLoader: widget.historyLoader,
        asker: widget.asker,
      ),
    ));
    if (mounted) unawaited(_load(silent: true));
  }

  Future<DailyAskResult> _ask({required String question, String? category}) async {
    if (widget.asker != null) {
      return widget.asker!(question: question, category: category);
    }
    final fid = await resolveFamilyId(widget.userId);
    final id = _elderId;
    if (fid == null || id == null) {
      return const DailyAskResult(false, '請重新登入後再試一次');
    }
    return DailyQuestionApi.ask(
        familyId: fid, elderId: id, question: question, category: category);
  }

  Future<void> _openAsk() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await showAskDailyQuestionDialog(context,
        elderName: _elderName, ask: _ask);
    if (r == null || !r.ok || !mounted) return;
    messenger.showSnackBar(famSnackBar(context, r.message, success: true));
    unawaited(_load(silent: true));
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final item = _item;
    final answered = item?.answered == true;

    final Widget status;
    if (_loading && item == null) {
      status = const SizedBox.shrink();
    } else if (item == null) {
      status = const SizedBox.shrink();
    } else {
      status = FamChip(
        label: answered ? '已回答' : '未回答',
        tone: answered ? FamTone.brand : FamTone.warm,
      );
    }

    Widget body;
    if (_loading && item == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    } else if (item == null) {
      body = Text(
        _error ? '暫時讀不到今天的小問題，稍後再試一次' : '今天還沒有小問題',
        style: famText(c.text2, 14, height: 1.5),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.question,
            key: const ValueKey('dq_card_question'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text, 16, weight: FontWeight.w800, height: 1.45),
          ),
          if (answered) ...[
            const SizedBox(height: 8),
            // 回答摘要＋語音圖示：文字可收縮（規則 14）。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.answerSnippet.isEmpty ? '（已回答）' : item.answerSnippet,
                    key: const ValueKey('dq_card_answer'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: famText(c.brandStrong, 14, height: 1.5),
                  ),
                ),
                if (item.hasAudio) ...[
                  const SizedBox(width: 6),
                  Text('🔊', key: const ValueKey('dq_card_audio'),
                      style: famText(c.brandStrong, 16)),
                ],
              ],
            ),
          ],
        ],
      );
    }

    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(title: '每日一問', trailing: status),
          const SizedBox(height: 10),
          body,
          const SizedBox(height: 12),
          // 窄螢幕／大字級下兩顆按鈕可換行（Wrap），不用 Row（規則 14）。
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FamButton(
                key: const ValueKey('dq_card_ask'),
                label: '出一題給長輩',
                height: 40,
                expand: false,
                onPressed: _openAsk,
              ),
              FamButton(
                key: const ValueKey('dq_card_all'),
                label: '看全部',
                kind: FamButtonKind.outline,
                height: 40,
                expand: false,
                onPressed: () => _openAll(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
