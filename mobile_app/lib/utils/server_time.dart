/// 後端時間字串 → 本地時間。
///
/// 後端資料庫一律存 UTC（`uban-api/database.py` 連線時 `SET time_zone='+00:00'`），
/// 但 `activity_log.timestamp`、`emergency_alerts.detected_at` 等欄位回傳時**沒有帶 `Z`**
/// （例如 `2026-10-07T01:38:43`）。過去前端直接切字串取 `HH:mm`，台灣 09:38 的打卡
/// 就顯示成 01:38，日期也會在台灣早上 8 點前算成前一天。
///
/// 沒帶時區的值一律視為 UTC；已帶 `Z` 或 `+08:00` 的照原樣解析。純函式。
class ServerTime {
  ServerTime._();

  static final RegExp _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// 解析失敗或空值回傳 null。
  static DateTime? parse(Object? raw) {
    if (raw == null) return null;
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(' ', 'T');
    if (!_hasZone.hasMatch(s)) s = '${s}Z';
    return DateTime.tryParse(s)?.toLocal();
  }

  /// 本地日期 `yyyy-MM-dd`。
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 本地時間 `HH:mm`。
  static String clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
