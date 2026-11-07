// ★ 2026-11-07 殭屍連線（Z1）：Signaling.ensureLive() 的純判斷（純函式，無任何 Flutter／
// plugin 相依，可單元測試）。
//
// 背景：長輩端 `socket.connected == true`，但後端 rooms_manager 已沒有這個 sid（例如後端部署
// 重啟），此時 join／call-request 等 emit 全部無效，且客戶端沒有任何 disconnect 紀錄。
// 客戶端送 `conn-check` 並等 ack：
//   - ack 回 joined=true  → 連線健康；
//   - ack 回 joined=false → 連線活著但不在房內，只重送 join；
//   - 逾時無 ack          → 連線已失效（舊後端沒有本事件時也是這個結果，所以要有冷卻）。
// 這裡只放「依輸入決定該做什麼」的規則；實際 emit／重建仍在 signaling.dart。

/// conn-check 等 ack 的逾時：超過視為連線失效。
const Duration kConnCheckAckTimeout = Duration(milliseconds: 2500);

/// 重建 socket 後等待「連上」的上限。
const Duration kConnCheckRebuildWait = Duration(seconds: 5);

/// 兩次「失效重建」之間的最短間隔：避免舊後端（沒有 conn-check、永遠逾時）造成無限重建。
const Duration kConnCheckRebuildCooldown = Duration(seconds: 60);

/// 前景定期檢查的週期。
const Duration kConnCheckPeriodicInterval = Duration(seconds: 30);

/// 對 conn-check 回應的歸類。
enum ConnCheckVerdict {
  /// 有回應且 joined == true。
  joined,

  /// 有回應但 joined != true（連線活著，不在房內）。
  notJoined,

  /// 逾時或回應為 null／例外（視為連線失效）。
  noResponse,
}

/// 收到 conn-check 之後該做什麼。
enum ConnCheckAction {
  /// 連線健康，什麼都不用做。
  none,

  /// 只重送 join。
  rejoin,

  /// 通話中偵測到失效：只寫 log，不重建（避免媒體已通卻換 socket 造成 sid 不符）。
  logOnlyInCall,

  /// 拆掉舊 socket 並依當前欄位重建。
  rebuild,

  /// 該重建，但距上次重建不足冷卻時間：只寫 log。
  skipRebuildCooldown,
}

/// 把 ack 的原始值歸類。
///
/// [ack] 為 null（逾時）或 Exception 視為 [ConnCheckVerdict.noResponse]；
/// 任何其他值代表伺服器確實回了話：Map／List 內取 `joined == true`，
/// 其餘（含空 Map、無參數 ack）一律當成「活著但不在房內」。
ConnCheckVerdict parseConnCheckAck(dynamic ack) {
  if (ack == null || ack is Exception || ack is Error) {
    return ConnCheckVerdict.noResponse;
  }
  dynamic body = ack;
  if (body is List) {
    body = body.isEmpty ? null : body.first;
  }
  if (body is Map && body['joined'] == true) {
    return ConnCheckVerdict.joined;
  }
  return ConnCheckVerdict.notJoined;
}

/// 依「ack 結果 + 是否通話中 + 距上次重建秒數」決定動作。
///
/// [secondsSinceLastRebuild] 為 null 代表從未因失效重建過。
ConnCheckAction decideConnCheckAction({
  required ConnCheckVerdict verdict,
  required bool inCall,
  required int? secondsSinceLastRebuild,
}) {
  switch (verdict) {
    case ConnCheckVerdict.joined:
      return ConnCheckAction.none;
    case ConnCheckVerdict.notJoined:
      return ConnCheckAction.rejoin;
    case ConnCheckVerdict.noResponse:
      if (inCall) return ConnCheckAction.logOnlyInCall;
      if (secondsSinceLastRebuild != null &&
          secondsSinceLastRebuild < kConnCheckRebuildCooldown.inSeconds) {
        return ConnCheckAction.skipRebuildCooldown;
      }
      return ConnCheckAction.rebuild;
  }
}

/// 前景定期檢查要不要跑：僅在前景、不在通話中、socket 看起來已連線時。
bool shouldRunPeriodicConnCheck({
  required bool isForeground,
  required bool inCall,
  required bool socketConnected,
}) =>
    isForeground && !inCall && socketConnected;

/// 「先 emit、背景驗證」的訊息（busy／cancel／end-call／emergency-call）是否要重送一次。
///
/// 重建世代 [generationAtEmit] 是 emit 當下的值，[generationNow] 是驗證結束後的值；
/// 兩者不同代表 emit 發生在被換掉（或正在被換掉）的舊連線上，且新連線已連上才重送。
bool shouldResendAfterRebuild({
  required int generationAtEmit,
  required int generationNow,
  required bool socketConnected,
}) =>
    generationNow != generationAtEmit && socketConnected;

/// 扣掉已花掉的時間後，還剩多少時間可以給 ensureLive（供 sendCallAccept 不超過 maxWait）。
/// 剩餘不足 [minUseful] 就回 [Duration.zero]，呼叫端應略過檢查直接送。
Duration remainingBudget({
  required Duration total,
  required Duration elapsed,
  Duration minUseful = const Duration(milliseconds: 300),
}) {
  final Duration left = total - elapsed;
  return left < minUseful ? Duration.zero : left;
}
