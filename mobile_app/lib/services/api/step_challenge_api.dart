import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ★ 2026-10-07 家庭步數挑戰：資料模型 + API 層（長輩端讀取、家屬端讀取／設定）。

/// 可選的每週目標步數（後端白名單，家屬端設定用）。
const List<int> kStepChallengeGoals = [20000, 35000, 50000, 70000, 100000];

int _toInt(dynamic v) {
  if (v is num) return v.round();
  return int.tryParse((v ?? '').toString()) ?? 0;
}

String? _nz(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty || s == 'null' ? null : s;
}

String _withComma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 步數轉「3.2 萬」「8,500」（不含「步」）。≥1 萬用萬（整數不帶 .0，如 5 萬）。
String formatStepsNum(int steps) {
  if (steps < 10000) return _withComma(steps < 0 ? 0 : steps);
  final s = (steps / 10000).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s} 萬';
}

/// 步數轉「3.2 萬步」「8,500 步」。
String formatStepsWan(int steps) => '${formatStepsNum(steps)} 步'
    .replaceFirst('萬 步', '萬步');

/// 進度百分比字串（0..1 夾限，無條件捨去到整數）：'64%'。
String formatProgressPercent(double progress) {
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  return '${(p * 100).floor()}%';
}

class StepChallengeMember {
  final String role; // 'elder' | 'family'
  final String id;
  final String name;
  final int steps;
  const StepChallengeMember(
      {required this.role,
      required this.id,
      required this.name,
      required this.steps});
  bool get isElder => role == 'elder';

  static StepChallengeMember? tryParse(dynamic m) {
    if (m is! Map) return null;
    return StepChallengeMember(
      role: _nz(m['role']) ?? 'family',
      id: _nz(m['id']) ?? '',
      name: _nz(m['name']) ?? '家人',
      steps: _toInt(m['steps']),
    );
  }
}

class StepChallengeDaily {
  final String date;
  final int steps;
  const StepChallengeDaily({required this.date, required this.steps});

  static StepChallengeDaily? tryParse(dynamic m) {
    if (m is! Map) return null;
    final d = _nz(m['date']);
    if (d == null) return null;
    return StepChallengeDaily(date: d, steps: _toInt(m['steps']));
  }

  /// 'YYYY-MM-DD' → 'M/D'；格式不合原樣回傳。
  String get shortDate {
    final p = date.split('-');
    if (p.length != 3) return date;
    return '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]}';
  }
}

class StepChallengeLastWeek {
  final int goalSteps;
  final int totalSteps;
  final bool achieved;
  const StepChallengeLastWeek(
      {required this.goalSteps,
      required this.totalSteps,
      required this.achieved});
}

class StepChallenge {
  final String? weekStart;
  final String? weekEnd;
  final int goalSteps;
  final int totalSteps;
  final double progress; // 0..1
  final bool achieved;
  final String? achievedAt;
  final List<StepChallengeMember> members;
  final List<StepChallengeDaily> daily;
  final StepChallengeLastWeek? lastWeek;

  const StepChallenge({
    this.weekStart,
    this.weekEnd,
    required this.goalSteps,
    required this.totalSteps,
    required this.progress,
    required this.achieved,
    this.achievedAt,
    this.members = const [],
    this.daily = const [],
    this.lastWeek,
  });

  /// 長輩本人步數（members 中 role=elder 加總）。
  int get elderSteps =>
      members.where((m) => m.isElder).fold(0, (s, m) => s + m.steps);

  /// 家人合計步數。
  int get familySteps =>
      members.where((m) => !m.isElder).fold(0, (s, m) => s + m.steps);

  /// 標題：「全家一起走：本週 3.2 萬 / 5 萬步」。
  String get titleText =>
      '全家一起走：本週 ${formatStepsNum(totalSteps)} / ${formatStepsWan(goalSteps)}';

  /// 一行摘要：「您走了 1.2 萬步，家人走了 2 萬步」。
  String get summaryText =>
      '您走了 ${formatStepsWan(elderSteps)}，家人走了 ${formatStepsWan(familySteps)}';

  /// 格式不合（非 Map、沒有目標）回傳 null。
  static StepChallenge? tryParse(dynamic m) {
    if (m is! Map) return null;
    final goal = _toInt(m['goal_steps']);
    if (goal <= 0) return null;
    final total = _toInt(m['total_steps']);
    var prog = m['progress'] is num
        ? (m['progress'] as num).toDouble()
        : double.tryParse((m['progress'] ?? '').toString()) ?? total / goal;
    if (prog.isNaN) prog = 0;
    final lw = m['last_week'];
    final members = <StepChallengeMember>[];
    if (m['members'] is List) {
      for (final e in m['members'] as List) {
        final x = StepChallengeMember.tryParse(e);
        if (x != null) members.add(x);
      }
    }
    final daily = <StepChallengeDaily>[];
    if (m['daily'] is List) {
      for (final e in m['daily'] as List) {
        final x = StepChallengeDaily.tryParse(e);
        if (x != null) daily.add(x);
      }
    }
    return StepChallenge(
      weekStart: _nz(m['week_start']),
      weekEnd: _nz(m['week_end']),
      goalSteps: goal,
      totalSteps: total,
      progress: prog.clamp(0.0, 1.0),
      achieved: m['achieved'] == true || m['achieved'] == 1,
      achievedAt: _nz(m['achieved_at']),
      members: members,
      daily: daily,
      lastWeek: lw is Map && _toInt(lw['goal_steps']) > 0
          ? StepChallengeLastWeek(
              goalSteps: _toInt(lw['goal_steps']),
              totalSteps: _toInt(lw['total_steps']),
              achieved: lw['achieved'] == true || lw['achieved'] == 1)
          : null,
    );
  }
}

class StepChallengeApi {
  /// 長輩端目前的挑戰狀態；null = 讀取失敗／尚未讀到（長輩端整塊隱藏）。
  static final ValueNotifier<StepChallenge?> elderState =
      ValueNotifier<StepChallenge?>(null);

  /// App 內刷新訊號：Socket `step-challenge` 到達時遞增，小豬分頁監聽後重讀。
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  /// GET /step_challenge。失敗回傳 null（不拋例外）。
  static Future<StepChallenge?> get(Object elderId, {Object? familyId}) async {
    try {
      final fam = familyId != null ? '&family_id=$familyId' : '';
      final res = await ApiClient.get('/step_challenge?elder_id=$elderId$fam');
      if (res == null || res['status'] != 'success') return null;
      return StepChallenge.tryParse(res['data']);
    } catch (e) {
      debugPrint('⚠️ StepChallengeApi.get error: $e');
      return null;
    }
  }

  /// 長輩端：讀取並更新 [elderState]；失敗時清成 null（隱藏）。
  static Future<void> refreshElder(Object elderId) async {
    elderState.value = await get(elderId);
  }

  /// 家屬端：設定每週目標。成功回傳 true。
  static Future<bool> setGoal(Object familyId, Object elderId, int goal) async {
    try {
      final res = await ApiClient.post('/step_challenge/goal',
          {'family_id': familyId, 'elder_id': elderId, 'goal_steps': goal});
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ StepChallengeApi.setGoal error: $e');
      return false;
    }
  }

  /// 家屬端：上傳自己的當日步數（date 格式 YYYY-MM-DD）。成功回傳 true。
  static Future<bool> uploadFamilySteps(
      Object familyId, String date, int steps) async {
    try {
      final res = await ApiClient.post('/step_challenge/family_steps',
          {'family_id': familyId, 'date': date, 'steps': steps});
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ StepChallengeApi.uploadFamilySteps error: $e');
      return false;
    }
  }
}
