import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/step_challenge_api.dart';

// ★ 2026-10-07 家庭步數挑戰：家屬自己的每日步數計算＋上傳。
//
// 裝置的 TYPE_STEP_COUNTER 是「開機以來」的累積值，不是今天的步數，所以要靠
// 每日基準（baseline）換算。基準／進位存在「裝置偏好」（SharedPreferences，不屬於
// SessionManager 的 session key，登出不會清，G58/G59）。
// 本服務絕不阻塞啟動、不碰通話／FCM 邏輯；所有錯誤只 debugPrint。

/// 每日換算狀態（對應 SharedPreferences 的鍵＋最後一次算出的今日步數）。
class StepBaselineState {
  /// 基準所屬的台灣日期 `YYYY-MM-DD`。
  final String date;

  /// 基準時的硬體累積值；重開機後歸 0。
  final int baseline;

  /// 已確定、但不在目前硬體累積值內的步數（重開機前累積的部分）。
  final int carry;

  /// 最近一次算出的「今日步數」（供隔日上傳昨日最終值、重開機進位）。
  final int lastToday;

  const StepBaselineState({
    required this.date,
    required this.baseline,
    required this.carry,
    required this.lastToday,
  });

  @override
  bool operator ==(Object other) =>
      other is StepBaselineState &&
      other.date == date &&
      other.baseline == baseline &&
      other.carry == carry &&
      other.lastToday == lastToday;

  @override
  int get hashCode => Object.hash(date, baseline, carry, lastToday);

  @override
  String toString() =>
      'StepBaselineState($date, baseline=$baseline, carry=$carry, last=$lastToday)';
}

/// [computeFamilySteps] 的結果。
class StepCalcResult {
  final StepBaselineState state;

  /// 今日步數（絕對值）。
  final int today;

  /// 跨日時要補傳的「昨天最終值」；沒有就是 null。
  final String? yesterdayDate;
  final int? yesterdaySteps;

  const StepCalcResult({
    required this.state,
    required this.today,
    this.yesterdayDate,
    this.yesterdaySteps,
  });
}

/// 台灣日期（UTC+8）字串。
String twDateString([DateTime? now]) {
  final tw = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${tw.year}-${two(tw.month)}-${two(tw.day)}';
}

/// 前一天的日期字串（純字串運算，不受時區影響）。
String previousDateString(String date) {
  final p = date.split('-');
  final d = DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
      .subtract(const Duration(days: 1));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 純函式：由「上次狀態＋今天日期＋目前硬體累積值」算出今日步數與新狀態。
///
/// - 第一次（[prev] 為 null）：基準＝目前值，今天從安裝後開始算。
/// - 跨日：基準＝目前值、進位 0；若上次狀態正好是「昨天」就回傳昨日最終值供補傳。
/// - 同日、目前值 < 上次看到的硬體值：視為重開機，進位＝上次今日步數、基準歸 0。
/// - 其餘：今日 = 進位 + (目前值 − 基準)。
StepCalcResult computeFamilySteps({
  required StepBaselineState? prev,
  required String todayDate,
  required int counter,
}) {
  final c = counter < 0 ? 0 : counter;
  if (prev == null) {
    return StepCalcResult(
      state: StepBaselineState(
          date: todayDate, baseline: c, carry: 0, lastToday: 0),
      today: 0,
    );
  }
  if (prev.date != todayDate) {
    final canBackfill =
        prev.date == previousDateString(todayDate) && prev.lastToday > 0;
    return StepCalcResult(
      state: StepBaselineState(
          date: todayDate, baseline: c, carry: 0, lastToday: 0),
      today: 0,
      yesterdayDate: canBackfill ? prev.date : null,
      yesterdaySteps: canBackfill ? prev.lastToday : null,
    );
  }
  var baseline = prev.baseline;
  var carry = prev.carry;
  // 上次看到的硬體值＝基準＋（今日步數−進位）；硬體計數單調遞增，低於它就是重開機
  // （只比基準會漏掉「重開機後基準已是 0」的第二次重開機）。
  final lastSeenCounter = baseline + (prev.lastToday - carry);
  if (c < lastSeenCounter) {
    // 重開機：硬體計數歸零，把已走的步數收進進位。
    carry = prev.lastToday;
    baseline = 0;
  }
  var today = carry + (c - baseline);
  if (today < 0) today = 0;
  return StepCalcResult(
    state: StepBaselineState(
        date: todayDate, baseline: baseline, carry: carry, lastToday: today),
    today: today,
  );
}

/// 純函式：是否該上傳（變化 ≥50 步，或距上次上傳 ≥15 分鐘且有增加；換日有步數就傳）。
bool shouldUploadSteps({
  required int steps,
  required String date,
  String? lastUploadedDate,
  int? lastUploadedSteps,
  DateTime? lastUploadedAt,
  DateTime? now,
}) {
  if (lastUploadedDate != date || lastUploadedSteps == null) {
    return steps > 0;
  }
  final delta = steps - lastUploadedSteps;
  if (delta >= 50) return true;
  if (delta > 0 && lastUploadedAt != null) {
    final age = (now ?? DateTime.now()).difference(lastUploadedAt);
    if (age >= const Duration(minutes: 15)) return true;
  }
  return false;
}

/// 開始計算步數的結果。
enum FamilyStepOptIn { granted, denied, permanentlyDenied, unavailable }

typedef FamilyStepUploader = Future<bool> Function(
    int familyId, String date, int steps);
typedef FamilyStepCounterReader = Future<int?> Function();

class FamilyStepSync {
  FamilyStepSync._();
  static final FamilyStepSync instance = FamilyStepSync._();

  static const String kBaselineDate = 'family_step_baseline_date';
  static const String kBaselineCounter = 'family_step_baseline_counter';
  static const String kTodayCarry = 'family_step_today_carry';
  static const String kLastToday = 'family_step_last_today';
  static const String kConsent = 'family_step_consent';
  static const String kUploadDate = 'family_step_upload_date';
  static const String kUploadSteps = 'family_step_upload_steps';
  static const String kUploadAt = 'family_step_upload_at_ms';
  static const String kPendingDate = 'family_step_pending_date';
  static const String kPendingSteps = 'family_step_pending_steps';

  static const Duration interval = Duration(minutes: 5);

  /// 測試注入點。
  @visibleForTesting
  FamilyStepUploader? uploaderOverride;
  @visibleForTesting
  FamilyStepCounterReader? counterOverride;

  Timer? _timer;
  int? _familyId;
  bool _busy = false;

  /// 最近一次算出的今日步數（卡片顯示用）；null 表示還沒有。
  final ValueNotifier<int?> todaySteps = ValueNotifier<int?>(null);

  Future<bool> hasConsent() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(kConsent) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 目前系統權限是否已允許（不會跳出詢問）。
  Future<bool> isPermissionGranted() async {
    try {
      return await Permission.activityRecognition.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 使用者按下「開始計算我的步數」才呼叫：此時才申請 ACTIVITY_RECOGNITION。
  Future<FamilyStepOptIn> optIn({int? familyId}) async {
    try {
      final st = await Permission.activityRecognition.request();
      if (st.isGranted) {
        final p = await SharedPreferences.getInstance();
        await p.setBool(kConsent, true);
        unawaited(start(familyId: familyId));
        return FamilyStepOptIn.granted;
      }
      return st.isPermanentlyDenied
          ? FamilyStepOptIn.permanentlyDenied
          : FamilyStepOptIn.denied;
    } catch (e) {
      debugPrint('⚠️ [FamilyStepSync] 申請步數權限失敗: $e');
      return FamilyStepOptIn.unavailable;
    }
  }

  /// App 啟動／回前景時呼叫；沒同意或沒權限就什麼都不做。立即同步一次並啟動 5 分鐘計時。
  Future<void> start({int? familyId}) async {
    try {
      if (familyId != null) _familyId = familyId;
      if (!await hasConsent()) return;
      if (counterOverride == null && !await isPermissionGranted()) return;
      _timer ??= Timer.periodic(interval, (_) => unawaited(syncNow()));
      unawaited(syncNow());
    } catch (e) {
      debugPrint('⚠️ [FamilyStepSync] start 失敗: $e');
    }
  }

  /// 進背景時停止計時（回前景再 [start]）。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<int?> _readCounter() async {
    if (counterOverride != null) return counterOverride!();
    try {
      final e = await Pedometer.stepCountStream.first
          .timeout(const Duration(seconds: 10));
      return e.steps;
    } catch (e) {
      debugPrint('⚠️ [FamilyStepSync] 讀取計步器失敗: $e');
      return null;
    }
  }

  Future<bool> _upload(int familyId, String date, int steps) async {
    if (uploaderOverride != null) {
      return uploaderOverride!(familyId, date, steps);
    }
    return StepChallengeApi.uploadFamilySteps(familyId, date, steps);
  }

  /// 讀硬體值 → 換算今日步數 → 依節流上傳。回傳今日步數（失敗 null）。
  Future<int?> syncNow({DateTime? now}) async {
    if (_busy) return null;
    _busy = true;
    try {
      final counter = await _readCounter();
      if (counter == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final today = twDateString(now);

      final bd = prefs.getString(kBaselineDate);
      final prev = bd == null
          ? null
          : StepBaselineState(
              date: bd,
              baseline: prefs.getInt(kBaselineCounter) ?? 0,
              carry: prefs.getInt(kTodayCarry) ?? 0,
              lastToday: prefs.getInt(kLastToday) ?? 0,
            );
      final r =
          computeFamilySteps(prev: prev, todayDate: today, counter: counter);

      await prefs.setString(kBaselineDate, r.state.date);
      await prefs.setInt(kBaselineCounter, r.state.baseline);
      await prefs.setInt(kTodayCarry, r.state.carry);
      await prefs.setInt(kLastToday, r.state.lastToday);
      todaySteps.value = r.today;

      final fid = _familyId;
      if (fid == null) return r.today;

      // 跨日：昨天最終值先記成待補傳（失敗下次再試），伺服器只收今天或昨天。
      if (r.yesterdayDate != null && r.yesterdaySteps != null) {
        await prefs.setString(kPendingDate, r.yesterdayDate!);
        await prefs.setInt(kPendingSteps, r.yesterdaySteps!);
      }
      final pd = prefs.getString(kPendingDate);
      final ps = prefs.getInt(kPendingSteps);
      if (pd != null && ps != null) {
        if (pd == today || pd == previousDateString(today)) {
          if (await _upload(fid, pd, ps)) {
            await prefs.remove(kPendingDate);
            await prefs.remove(kPendingSteps);
          }
        } else {
          // 超過可補傳的日期，放棄。
          await prefs.remove(kPendingDate);
          await prefs.remove(kPendingSteps);
        }
      }

      final lastAtMs = prefs.getInt(kUploadAt);
      final should = shouldUploadSteps(
        steps: r.today,
        date: today,
        lastUploadedDate: prefs.getString(kUploadDate),
        lastUploadedSteps: prefs.getInt(kUploadSteps),
        lastUploadedAt: lastAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastAtMs),
        now: now,
      );
      if (should && await _upload(fid, today, r.today)) {
        await prefs.setString(kUploadDate, today);
        await prefs.setInt(kUploadSteps, r.today);
        await prefs.setInt(
            kUploadAt, (now ?? DateTime.now()).millisecondsSinceEpoch);
      }
      return r.today;
    } catch (e) {
      debugPrint('⚠️ [FamilyStepSync] 同步失敗: $e');
      return null;
    } finally {
      _busy = false;
    }
  }
}
