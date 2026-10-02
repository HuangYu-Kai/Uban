/// 依 `GET /api/user/profile/{userId}`（`ApiService.getElderProfile`）的回應，
/// 判斷「年齡／居住地」是否**確定**尚未填寫。
///
/// ★ 第五十三輪 onboard53b：從 `login_screen.dart`（家屬端）與
/// `elder_pairing_display_screen.dart`（長輩端）各自的內嵌判斷邏輯抽成共用
/// 函式——兩端「必填」的定義必須完全一致，分開維護遲早會出現「一邊擋、
/// 一邊沒擋」的落差，抽出來後也才能直接寫單元測試驗證，不必透過完整的
/// 畫面／導航／HTTP mock。
///
/// 🚨 fail-open，不是 fail-closed：只有 `apiResult['status'] == 'success'`
/// 且 `data` 是 `Map`、且三個欄位確定至少有一個是 `null`／空字串時，才回傳
/// `true`（判定為「確定缺資料，要強制補填」）。以下情況一律回傳 `false`
/// （視為「已完整」，不強制、直接放行）：
/// - [apiResult] 本身是 `null`（呼叫端 catch 到例外後傳進來的情況）
/// - `status` 不是 `'success'`（逾時、離線、伺服器錯誤、找不到使用者…）
/// - `data` 不存在或不是 `Map`
///
/// 理由：長輩／家屬連不上網路時被鎖在補填畫面外面、進不了 App，是比
/// 「資料晚一點補」嚴重得多的問題。呼叫端（如 `ApiService.getElderProfile`）
/// 內部已經 try/catch 過，逾時或例外都回傳 `{'status': 'error', ...}` 而不是
/// 丟例外；呼叫端仍應自行包一層 try/catch 作為多一層保險，例外時傳 `null`
/// 進來即可維持 fail-open。
bool isProfileConfirmedIncomplete(Map<String, dynamic>? apiResult) {
  if (apiResult == null) return false;
  if (apiResult['status'] != 'success') return false;

  final data = apiResult['data'];
  if (data is! Map) return false;

  final ageVal = data['age'];
  final cityVal = data['residence_city'];
  final districtVal = data['residence_district'];

  return ageVal == null ||
      cityVal == null ||
      (cityVal is String && cityVal.isEmpty) ||
      districtVal == null ||
      (districtVal is String && districtVal.isEmpty);
}
