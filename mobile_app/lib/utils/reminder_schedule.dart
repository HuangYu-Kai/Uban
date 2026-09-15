// lib/utils/reminder_schedule.dart
import 'package:intl/intl.dart';

/// ⏰ 提醒排程共用邏輯（唯一事實來源 / Single Source of Truth）
///
/// 為什麼需要這個檔案：
/// App 原本有兩處各自判斷「這筆提醒今天算不算數」——
/// 1. `lib/services/elder_reminder_manager.dart` 的看門狗（每 20 秒比對一次，準時跳出提醒彈窗）
/// 2. 長輩「我的」分頁的今日排程卡片（單純把整天提醒攤平列出）
/// 這兩處若各自維護一份 `repeat_days` / `start_date` / 星期比對邏輯，日後只要改一邊、忘了改
/// 另一邊，就會出現「看門狗準時彈窗提醒吃藥，但畫面上卻沒顯示這筆」（或反過來）的不一致，
/// 讓長輩無所適從。因此把「這筆提醒今天適不適用」抽成這裡的純函式，讓看門狗與 UI
/// 永遠讀同一份判斷結果，不會互相矛盾。
///
/// 本檔案只放「純函式」：不建立 widget、不做任何 I/O（不讀資料庫、不打 API）、
/// 也不維護任何單例狀態，方便單元測試與重複呼叫。
///
/// 提醒事項的資料形狀（`Map<String, dynamic>`）欄位：
/// - `id`：int
/// - `title`：String
/// - `time_str`：String，格式 "HH:mm"
/// - `category`：String，例如 'medication' / 'water' / 'exercise'
/// - `note`：String
/// - `repeat_days`：String
/// - `start_date`：String，格式 "yyyy-MM-dd"
/// - `is_active`：任意型別（可能是 bool 或 int，視資料來源而定）

/// 判斷提醒是否為「非啟用」狀態。
///
/// ★ 這裡刻意採「寬鬆」判斷：只有明確為 `false` 或 `0` 才視為停用，其餘（包含 `null`、
/// 缺欄位、字串等未預期型別）一律視為啟用。
///
/// 這是刻意保留的既有差異，並非疏漏：
/// - 看門狗（`elder_reminder_manager.dart` 原本的寫法）採「白名單」：
///   `is_active == true || is_active == 1` 才觸發，其餘一律視為停用。
/// - 「我的」分頁列表原本的寫法是「黑名單」：`is_active != false` 才顯示，其餘一律視為啟用。
/// 兩者標準不同，若貿然統一成任何一種都會悄悄改變既有行為（可能讓原本會跳的提醒不跳，
/// 或讓原本不顯示的提醒冒出來）。這裡選擇比較寬鬆的黑名單標準，只把「明確關閉」
/// （`false` 或 `0`）視為停用，其餘一律視為啟用，讓 UI 與看門狗都能安全套用。
bool _isInactive(Map<String, dynamic> r) {
  final v = r['is_active'];
  return v == false || v == 0;
}

/// 判斷這筆提醒「今天」是否適用。
///
/// 邏輯逐字取自 `elder_reminder_manager.dart` 的 `_checkSchedule`（原本內聯的
/// `repeat_days` / `start_date` / 星期比對區塊），行為完全相同：
/// - `repeat_days` 為 `'每天'` 或 `'常規'` → 適用
/// - `repeat_days` 為 `'單次'` 或 `'單次提醒'` → 只有當 `start_date` 為空／null，
///   或等於今天日期（"yyyy-MM-dd"）時才適用
/// - `repeat_days` 為 `'週一至週五'` → 只有平日（`now.weekday <= 5`）才適用
/// - `repeat_days` 包含今天星期幾（例如「週一週三週五」包含「週三」）→ 適用
/// - 以上皆不符合 → 適用（★ 這是原始程式碼刻意保留的寬鬆預設值，並非疏漏，此處原樣保留）
///
/// 另外，非啟用的提醒（見 [_isInactive]）一律回傳 false。
bool appliesToday(Map<String, dynamic> r, DateTime now) {
  if (_isInactive(r)) return false;

  final todayStr = DateFormat('yyyy-MM-dd').format(now);
  const weekdayMap = {1: '週一', 2: '週二', 3: '週三', 4: '週四', 5: '週五', 6: '週六', 7: '週日'};
  final currentWeekday = weekdayMap[now.weekday] ?? '';

  final repeatDays = r['repeat_days']?.toString() ?? '每天';
  final startDate = r['start_date']?.toString();

  if (repeatDays == '每天' || repeatDays == '常規') {
    return true;
  } else if (repeatDays == '單次' || repeatDays == '單次提醒') {
    return startDate == null || startDate.isEmpty || startDate == todayStr;
  } else if (repeatDays == '週一至週五') {
    return now.weekday <= 5;
  } else if (repeatDays.contains(currentWeekday)) {
    return true;
  } else {
    // ★ 保留原始看門狗的寬鬆預設：無法辨識的 repeat_days 一律視為適用今天
    return true;
  }
}

/// 嘗試把 "HH:mm" 字串解析成「今天」對應的 [DateTime]。
/// 解析失敗（缺欄位、格式錯誤）一律回傳 null，呼叫端應忽略該筆。
DateTime? _parseTimeToday(Map<String, dynamic> r, DateTime now) {
  final raw = r['time_str']?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// 找出目前最需要處理的下一筆提醒。
///
/// 條件：今天適用（[appliesToday]）、尚未完成（不在 [completedIds] 內）、
/// `time_str` 可正確解析。在符合條件的提醒中：
/// - 優先回傳「時間尚未到達」中最早的一筆（也就是接下來最快要做的事）。
/// - ★ 若全部都已經過了時間（長輩比較晚才打開 App），則回傳「已過期」中最早的一筆，
///   而不是回傳 null——這是刻意的設計選擇：讓遲到的長輩仍然看得到自己還欠著哪一筆，
///   而不是誤以為今天的事都做完了。
/// 若完全沒有未完成的提醒，回傳 null。
/// `time_str` 缺失或無法解析的提醒會被忽略（不會被選為 nextDue）。
Map<String, dynamic>? nextDue(
  List<Map<String, dynamic>> reminders,
  Set<int> completedIds,
  DateTime now,
) {
  final candidates = <MapEntry<Map<String, dynamic>, DateTime>>[];

  for (final r in reminders) {
    if (!appliesToday(r, now)) continue;
    final id = int.tryParse(r['id']?.toString() ?? '');
    if (id != null && completedIds.contains(id)) continue;
    final time = _parseTimeToday(r, now);
    if (time == null) continue;
    candidates.add(MapEntry(r, time));
  }

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) => a.value.compareTo(b.value));

  for (final entry in candidates) {
    if (!entry.value.isBefore(now)) {
      return entry.key;
    }
  }

  // 全部都已過期：回傳最早的一筆（最早欠著的那一筆）
  return candidates.first.key;
}

/// 依狀態分組後的提醒清單，供 UI 分段呈現使用。
class ReminderGroups {
  final List<Map<String, dynamic>> dueNow;
  final List<Map<String, dynamic>> later;
  final List<Map<String, dynamic>> done;

  const ReminderGroups({
    required this.dueNow,
    required this.later,
    required this.done,
  });
}

/// 將今天適用的提醒分成「現在該做」「稍後」「已完成」三組。
///
/// - `done`：今天適用，且 id 在 [completedIds] 內。
/// - `dueNow`：尚未完成，且時間已到（或已過期）或在接下來 60 分鐘內。
/// - `later`：尚未完成，且距離現在超過 60 分鐘。
/// 各組皆依 `time_str` 由早到晚排序。`time_str` 缺失或無法解析的提醒視為排在最後，
/// 但仍會被放進對應分組（不會被整組忽略，避免長輩漏看資料不完整的提醒）。
ReminderGroups groupByStatus(
  List<Map<String, dynamic>> reminders,
  Set<int> completedIds,
  DateTime now,
) {
  final done = <Map<String, dynamic>>[];
  final dueNow = <Map<String, dynamic>>[];
  final later = <Map<String, dynamic>>[];

  const dueWindow = Duration(minutes: 60);

  for (final r in reminders) {
    if (!appliesToday(r, now)) continue;
    final id = int.tryParse(r['id']?.toString() ?? '');
    final isDone = id != null && completedIds.contains(id);

    if (isDone) {
      done.add(r);
      continue;
    }

    final time = _parseTimeToday(r, now);
    if (time == null) {
      // 時間無法解析：保守歸類為「現在該做」，避免長輩漏看
      dueNow.add(r);
      continue;
    }

    final diff = time.difference(now);
    if (!diff.isNegative && diff > dueWindow) {
      later.add(r);
    } else {
      dueNow.add(r);
    }
  }

  int byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['time_str']?.toString() ?? '';
    final tb = b['time_str']?.toString() ?? '';
    return ta.compareTo(tb);
  }

  dueNow.sort(byTime);
  later.sort(byTime);
  done.sort(byTime);

  return ReminderGroups(dueNow: dueNow, later: later, done: done);
}
