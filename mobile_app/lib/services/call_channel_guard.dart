// ★ 2026-11-07：通話「通道」守門（純函式，無任何 Flutter／plugin 相依，可單元測試）。
//
// 長輩的「通訊機（comm）」與「監控機（monitor／CCTV）」是互相隔離的兩條通道：
// - 通話所在房間 `comm_elder_<id>` → 只屬於通訊機；
// - 通話所在房間 `monitor_elder_<id>` → 只屬於監控機（家屬「監看」按鈕走這條）。
// 後端已依房間通道過濾目標裝置；這裡是前端的縱深防禦（Socket／FCM／CallKit 還原路徑共用），
// 避免殘留資料或舊版後端把通訊機的來電送進監控機（監控機會自動接聽，家屬因此看到監視畫面），
// 或把監控喚醒送進通訊機（通訊機會被自動接聽的緊急通話拉進通話房）。

const String kMonitorRoomPrefix = 'monitor_elder_';

/// 房號是否為監控房。
bool isMonitorRoomId(String? roomId) =>
    (roomId ?? '').trim().startsWith(kMonitorRoomPrefix);

/// 本機（長輩端）是否應該忽略這通來電／緊急通話。
///
/// [isMonitorDevice]：本機是否為監控機（`saved_is_cctv == true` 或 Signaling 的 deviceMode == 'monitor'）。
/// 房號為空（無法判斷）時一律不忽略，維持舊行為；呼叫端只在「本機是長輩端」時才套用。
bool shouldIgnoreCallForDeviceChannel({
  required bool isMonitorDevice,
  required String? roomId,
}) {
  final String room = (roomId ?? '').trim();
  if (room.isEmpty) return false;
  final bool monitorRoom = isMonitorRoomId(room);
  return isMonitorDevice != monitorRoom;
}

/// 解析來電 payload 的發起方角色。
///
/// `emergency-call` 只會由家屬端發起（長輩對長輩好友沒有緊急通話入口）。後端舊版的緊急通話
/// FCM 沒有 `role` 欄位，前端若退回 prefs 的 user_role／saved_role 判斷（會漂移）就可能把
/// 長輩機判成非長輩，彈出一般「家人來電」UI。因此 `emergency-call` 缺角色時視為 'family'。
/// 其他類型維持原樣（缺角色回傳原值，交由 prefs 退路處理）。
String? resolveCallSenderRole({required String? type, required dynamic roleRaw}) {
  final String role = (roleRaw ?? '').toString().trim();
  if (role.isNotEmpty) return role;
  if (type == 'emergency-call') return 'family';
  return roleRaw?.toString();
}
