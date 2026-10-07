import '../../../../utils/server_time.dart';

/// 首頁「近況分析」卡片用的純函式：把後端回傳的逐日／逐筆資料整理成「最近 N 天」
/// 的固定長條，並產生摘要文字。不碰網路、不碰 Flutter，方便單元測試。
///
/// 重點：**沒有資料的日子是 null，不是 0**——步數 null 代表沒有回報，不能當成「走 0 步」。

/// 某一天的數值；[value] 為 null 代表當天沒有資料。
class DayValue {
  final DateTime date; // 當地日期（時分秒為 0）
  final int? value;
  const DayValue(this.date, this.value);
}

class AnalysisBuckets {
  AnalysisBuckets._();

  /// 以 [today] 為最後一天、往前共 [n] 天的當地日期（舊 → 新）。
  static List<DateTime> lastDays(DateTime today, {int n = 7}) {
    final base = DateTime(today.year, today.month, today.day);
    return [
      for (var i = n - 1; i >= 0; i--) DateTime(base.year, base.month, base.day - i),
    ];
  }

  /// 後端 `date` 欄位（`yyyy-MM-dd` 或帶時間）→ 日期鍵；解析不了回 null。
  static String? _keyOfDateField(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.length < 10) return null;
    final head = s.substring(0, 10);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(head) ? head : null;
  }

  /// 逐日資料（步數、外出次數）→ 7 天長條。
  /// [rows] 每筆需有 `date` 與 [field]；同一天出現多筆時取最後一筆；缺的日子為 null。
  static List<DayValue> bucketDaily(
    List<dynamic> rows,
    String field,
    DateTime today, {
    int n = 7,
  }) {
    final byKey = <String, int?>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final key = _keyOfDateField(r['date']);
      if (key == null) continue;
      final v = r[field];
      byKey[key] = v is num ? v.toInt() : null;
    }
    return [
      for (final d in lastDays(today, n: n)) DayValue(d, byKey[ServerTime.dateKey(d)]),
    ];
  }

  /// 情緒事件（每筆有 `timestamp`）→ 每天事件數。沒有事件的日子是 0
  /// （事件型資料沒有「缺資料」的區分）；範圍外與時間無法解析的事件略過。
  static List<DayValue> bucketEvents(
    List<dynamic> events,
    DateTime today, {
    int n = 7,
  }) {
    final counts = <String, int>{};
    for (final e in events) {
      if (e is! Map) continue;
      final t = ServerTime.parse(e['timestamp']);
      if (t == null) continue;
      final k = ServerTime.dateKey(t);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [
      for (final d in lastDays(today, n: n)) DayValue(d, counts[ServerTime.dateKey(d)] ?? 0),
    ];
  }

  static String _md(DateTime d) => '${d.month}/${d.day}';

  static String _thousands(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// 步數摘要：「7 天平均 3,250 步，最多 6/3 5,120 步」。全無資料回 null。
  /// 平均只算有回報的日子。
  static String? stepsSummary(List<DayValue> days) {
    final have = days.where((d) => d.value != null).toList();
    if (have.isEmpty) return null;
    final sum = have.fold<int>(0, (a, d) => a + d.value!);
    final avg = (sum / have.length).round();
    var best = have.first;
    for (final d in have) {
      if (d.value! > best.value!) best = d;
    }
    final head = have.length == days.length
        ? '${days.length} 天平均'
        : '有資料的 ${have.length} 天平均';
    return '$head ${_thousands(avg)} 步，最多 ${_md(best.date)} ${_thousands(best.value!)} 步';
  }

  /// 外出摘要：「這 7 天外出 4 天，共 6 次」。[hasHome] 為 false 時後端沒有次數，
  /// 改以「有定位資料」的天數說明，不編造次數。全無資料回 null。
  static String? outingSummary(List<DayValue> days, {required bool hasHome}) {
    if (!hasHome) {
      return '還沒設定「家」，算不出外出次數；進入詳細頁可以設定';
    }
    final have = days.where((d) => d.value != null).toList();
    if (have.isEmpty) return null;
    final outDays = have.where((d) => d.value! > 0).length;
    final total = have.fold<int>(0, (a, d) => a + d.value!);
    return '這 ${days.length} 天外出 $outDays 天，共 $total 次';
  }

  /// 情緒與故事摘要。
  static String emotionSummary(List<DayValue> days, int storyCount) {
    final total = days.fold<int>(0, (a, d) => a + (d.value ?? 0));
    return '這 ${days.length} 天有 $total 次需要關心的情緒；已珍藏 $storyCount 篇人生故事';
  }
}
