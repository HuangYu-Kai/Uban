// ★ 2026-10-07 交接 C/D（長輩端）D1：步數上傳增量的純邏輯（可單元測試）。
//
// 問題：`_lastUploadedSteps` 過去只存在記憶體，App 重開後從 0 起算，但今日累計
// 步數會從 SharedPreferences 還原，第一次上傳就把整天步數再送一次。
// 解法：把「已上傳步數」連同日期存進 SharedPreferences，跨日歸零。

/// 本機偏好設定的鍵名（裝置層級）。
const String kLastUploadedStepsKey = 'elder_last_uploaded_steps';
const String kLastUploadedStepsDateKey = 'elder_last_uploaded_steps_date';

/// 還原「已上傳步數」：只有日期與今天相同才沿用，否則（跨日／從未存過）歸零。
int restoreUploadedSteps({
  required int? storedSteps,
  required String? storedDate,
  required String today,
}) {
  if (storedDate != today) return 0;
  final s = storedSteps ?? 0;
  return s < 0 ? 0 : s;
}

/// 本次應上傳的增量；融合步數沒超過已上傳值（含回退）時為 0。
int stepUploadDelta({required int fusedSteps, required int lastUploaded}) {
  final d = fusedSteps - lastUploaded;
  return d > 0 ? d : 0;
}
