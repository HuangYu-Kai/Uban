import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/elder.dart';
import '../../../services/api/step_challenge_api.dart';
import '../../../services/family_step_sync.dart';
import '../../../theme/app_theme.dart';
import '../daily_question_screen.dart' show resolveFamilyId;
import '../sheets/step_goal_sheet.dart';
import '../sheets/step_week_sheet.dart';
import 'fam_ui.dart';

/// 讀取挑戰狀態的簽名（測試可注入；預設走 [StepChallengeApi.get]）。
typedef StepChallengeLoader = Future<StepChallenge?> Function(
    int familyId, String elderId);

/// 設定目標的簽名（測試可注入；預設走 [StepChallengeApi.setGoal]）。
typedef StepChallengeGoalSetter = Future<bool> Function(
    int familyId, String elderId, int goal);

/// 步數計算開關狀態。
enum StepCountingState { unknown, off, on, denied }

/// ★ 2026-10-07 家庭步數挑戰：家屬互動分頁的「全家一起走」卡片。
///
/// 顯示本週全家進度條、成員步數（前 4 名＋…）、我今天的步數、調整目標、
/// 開始計算步數（使用者主動同意才申請 ACTIVITY_RECOGNITION）、上週結果；
/// 點卡片看 7 日長條圖。互動分頁被 IndexedStack 保活，靠父層遞增 [refreshToken]
/// （收到 `step-challenge` Socket 時）重讀。
class FamilyStepChallengeCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;
  final int refreshToken;

  /// 測試注入點。
  final StepChallengeLoader? loader;
  final StepChallengeGoalSetter? goalSetter;
  final Future<StepCountingState> Function()? countingStateReader;
  final Future<FamilyStepOptIn> Function(int? familyId)? optInRunner;
  final ValueNotifier<int?>? todaySteps;

  const FamilyStepChallengeCard({
    super.key,
    required this.currentElder,
    this.userId,
    this.refreshToken = 0,
    this.loader,
    this.goalSetter,
    this.countingStateReader,
    this.optInRunner,
    this.todaySteps,
  });

  @override
  State<FamilyStepChallengeCard> createState() =>
      _FamilyStepChallengeCardState();
}

class _FamilyStepChallengeCardState extends State<FamilyStepChallengeCard> {
  bool _loading = true;
  bool _error = false;
  bool _notBound = false;
  StepChallenge? _data;
  int? _familyId;
  StepCountingState _counting = StepCountingState.unknown;
  bool _optInBusy = false;
  bool _reloadedForSteps = false;

  ValueNotifier<int?> get _steps =>
      widget.todaySteps ?? FamilyStepSync.instance.todaySteps;

  String? get _elderId =>
      widget.currentElder?.elderId ?? widget.currentElder?.id.toString();

  @override
  void initState() {
    super.initState();
    _steps.addListener(_onStepsChanged);
    _load();
    _readCounting();
  }

  @override
  void dispose() {
    _steps.removeListener(_onStepsChanged);
    super.dispose();
  }

  /// 第一次算出我的步數後，靜默重讀一次（伺服器合計才會包含我剛上傳的）。
  void _onStepsChanged() {
    if (mounted) setState(() {});
    if (_reloadedForSteps || _steps.value == null) return;
    _reloadedForSteps = true;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) unawaited(_load(silent: true));
    });
  }

  @override
  void didUpdateWidget(covariant FamilyStepChallengeCard old) {
    super.didUpdateWidget(old);
    final oldId = old.currentElder?.elderId ?? old.currentElder?.id.toString();
    if (widget.refreshToken != old.refreshToken) {
      _load(silent: true);
    } else if (oldId != _elderId) {
      _data = null;
      _load();
    }
  }

  Future<void> _readCounting() async {
    StepCountingState s;
    try {
      if (widget.countingStateReader != null) {
        s = await widget.countingStateReader!();
      } else {
        final sync = FamilyStepSync.instance;
        if (!await sync.hasConsent()) {
          s = StepCountingState.off;
        } else {
          s = await sync.isPermissionGranted()
              ? StepCountingState.on
              : StepCountingState.denied;
        }
      }
    } catch (_) {
      s = StepCountingState.off;
    }
    if (mounted) setState(() => _counting = s);
  }

  Future<void> _load({bool silent = false}) async {
    final id = _elderId;
    if (id == null) return;
    if (!silent && mounted) setState(() => _loading = true);
    StepChallenge? r;
    var bound = true;
    try {
      final fid = _familyId ??= await resolveFamilyId(widget.userId);
      if (fid == null) {
        bound = false;
      } else {
        r = widget.loader != null
            ? await widget.loader!(fid, id)
            : await StepChallengeApi.get(id, familyId: fid);
      }
    } catch (_) {
      r = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r != null) {
        _data = r;
        _error = false;
        _notBound = false;
      } else if (!bound) {
        _data = null;
        _notBound = true;
        _error = false;
      } else if (_data == null) {
        // 靜默重讀失敗時保留舊資料。
        _error = true;
      }
    });
  }

  Future<void> _optIn() async {
    if (_optInBusy) return;
    setState(() => _optInBusy = true);
    FamilyStepOptIn r;
    try {
      final fid = _familyId ?? await resolveFamilyId(widget.userId);
      r = widget.optInRunner != null
          ? await widget.optInRunner!(fid)
          : await FamilyStepSync.instance.optIn(familyId: fid);
    } catch (_) {
      r = FamilyStepOptIn.unavailable;
    }
    if (!mounted) return;
    setState(() {
      _optInBusy = false;
      _counting = r == FamilyStepOptIn.granted
          ? StepCountingState.on
          : StepCountingState.denied;
    });
  }

  Future<void> _openGoal() async {
    final d = _data;
    final fid = _familyId ?? await resolveFamilyId(widget.userId);
    final id = _elderId;
    if (d == null || fid == null || id == null || !mounted) return;
    final goal = await StepGoalSheet.show(
      context,
      currentGoal: d.goalSteps,
      setter: (g) => widget.goalSetter != null
          ? widget.goalSetter!(fid, id, g)
          : StepChallengeApi.setGoal(fid, id, g),
    );
    if (goal != null && mounted) unawaited(_load(silent: true));
  }

  Future<void> _openWeek() async {
    final d = _data;
    if (d == null) return;
    await StepWeekSheet.show(context, daily: d.daily);
  }

  Widget _memberRow(UbanColors c, StepChallengeMember m) {
    // 姓名長度不可控：Expanded＋ellipsis，步數靠右固定（規則 14）。
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              m.isElder ? '${m.name}（長輩）' : m.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text, 13.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(formatStepsWan(m.steps),
              maxLines: 1, style: famText(c.text2, 13.5, tabular: true)),
        ],
      ),
    );
  }

  Widget _optInButton(String label) => FamButton(
        key: const ValueKey('step_card_optin'),
        label: label,
        kind: FamButtonKind.tonal,
        height: 42,
        loading: _optInBusy,
        onPressed: _optInBusy ? null : _optIn,
      );

  Widget _stepsToday(UbanColors c) {
    switch (_counting) {
      case StepCountingState.unknown:
        return const SizedBox.shrink();
      case StepCountingState.off:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('讓全家一起算進您的步數，一起把小豬養胖',
                style: famText(c.text2, 13.5, height: 1.45)),
            const SizedBox(height: 8),
            _optInButton('開始計算我的步數'),
          ],
        );
      case StepCountingState.denied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '還沒有取得計步權限，您可以到手機設定允許「身體活動」，或稍後再試一次',
              key: const ValueKey('step_card_denied'),
              style: famText(c.text2, 13.5, height: 1.45),
            ),
            const SizedBox(height: 8),
            _optInButton('再試一次'),
          ],
        );
      case StepCountingState.on:
        final v = _steps.value;
        return Text(
          v == null ? '我今天：計算中…' : '我今天走了 ${formatStepsWan(v)}',
          key: const ValueKey('step_card_mine'),
          style: famText(c.brandStrong, 14, weight: FontWeight.w800),
        );
    }
  }

  Widget _body(UbanColors c) {
    final d = _data;
    if (_loading && d == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    if (d == null) {
      return Text(
        _notBound
            ? '還沒有可以一起走的家人，配對成功後就能開始囉'
            : (_error ? '暫時讀不到全家的步數，稍後再試一次' : '全家一起走準備中'),
        key: const ValueKey('step_card_empty'),
        style: famText(c.text2, 14, height: 1.5),
      );
    }
    final members = [...d.members]..sort((a, b) => b.steps.compareTo(a.steps));
    final shown = members.take(4).toList();
    final lw = d.lastWeek;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${formatStepsNum(d.totalSteps)} / ${formatStepsWan(d.goalSteps)}'
          ' · ${formatProgressPercent(d.progress)}',
          key: const ValueKey('step_card_progress_text'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text, 16, weight: FontWeight.w800, height: 1.35),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            key: const ValueKey('step_card_bar'),
            value: d.progress.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: c.surface2,
            valueColor: AlwaysStoppedAnimation<Color>(c.brandFill),
          ),
        ),
        if (d.achieved) ...[
          const SizedBox(height: 8),
          Text('本週達標了！🎉',
              key: const ValueKey('step_card_achieved'),
              style: famText(c.brandStrong, 14, weight: FontWeight.w800)),
        ],
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final m in shown) _memberRow(c, m),
          if (members.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('…',
                  key: const ValueKey('step_card_more'),
                  style: famText(c.text3, 14)),
            ),
        ],
        if (lw != null) ...[
          const SizedBox(height: 10),
          Text(
            lw.achieved
                ? '上週：全家走了 ${formatStepsWan(lw.totalSteps)}，達標了 🎉'
                : '上週：全家走了 ${formatStepsWan(lw.totalSteps)}'
                    '（目標 ${formatStepsWan(lw.goalSteps)}）',
            key: const ValueKey('step_card_lastweek'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: famText(c.text3, 13, height: 1.4),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final hasData = _data != null;
    return FamCard(
      onTap: hasData ? _openWeek : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FamSecHead(
            title: '全家一起走',
            trailing: hasData
                ? Text('每天明細',
                    style: famText(c.text3, 12.5, weight: FontWeight.w600))
                : null,
          ),
          const SizedBox(height: 10),
          _body(c),
          if (hasData) ...[
            const SizedBox(height: 12),
            _stepsToday(c),
            const SizedBox(height: 10),
            FamButton(
              key: const ValueKey('step_card_goal'),
              label: '調整目標',
              kind: FamButtonKind.outline,
              height: 42,
              onPressed: _openGoal,
            ),
          ],
        ],
      ),
    );
  }
}
