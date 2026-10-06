import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/pet_growth_state.dart';
import 'pet_leaderboard_service.dart';

/// 本機體重與伺服器體重對帳後該做的事。
enum PetWeightAction {
  /// 伺服器還沒有這位長輩的體重，或本機比伺服器重（離線／舊版本餵的）：
  /// 把本機值推上去（後端 `POST /pet/state` 是只增不減，不會洗掉進度）。
  pushLocal,

  /// 伺服器比本機重（換機、重裝、別台裝置餵過）：採用伺服器值。
  adoptServer,

  /// 兩邊相同，什麼都不用做。
  keepLocal,
}

/// 純函式：決定本機（[local]）與伺服器（[server]，null＝尚無資料）對帳動作。
///
/// 賽季優先：伺服器賽季比本機記錄的新（賽季結算已把體重重置）→ 無條件採用
/// 伺服器值，即使本機較重。本機賽季未知（null，舊版升級或首次）→ 視為同賽季，
/// 套用一般「取較重者」規則。
PetWeightAction decideWeightAction({
  required int local,
  int? server,
  int? localSeason,
  int? serverSeason,
}) {
  if (server == null) return PetWeightAction.pushLocal;
  if (isNewerSeason(local: localSeason, server: serverSeason)) {
    return PetWeightAction.adoptServer;
  }
  if (local > server) return PetWeightAction.pushLocal;
  if (local < server) return PetWeightAction.adoptServer;
  return PetWeightAction.keepLocal;
}

/// 伺服器賽季是否比本機記錄的新（任一為 null＝無法判定，回 false）。
bool isNewerSeason({int? local, int? server}) =>
    local != null && server != null && server > local;

/// 純函式：餵食後伺服器回傳 [server] 時，本機該保留的體重。
/// 取較大者——本機若因離線餵食而領先，不可被伺服器的較小值倒退（領先的部分
/// 會在下次對帳時以 `POST /pet/state` 推上去）。
int mergeFedWeight({required int local, required int server}) =>
    math.max(local, server);

/// 對帳結果。
class PetWeightReconcileResult {
  /// 是否成功連上伺服器（讀取成功；若需要推送，推送也成功）。
  final bool ok;

  /// 非 null 代表伺服器體重較大，呼叫端應採用並寫回本機存檔。
  final int? adoptedWeight;

  /// 是否把本機體重推上了伺服器（排行榜因此可能變動）。
  final bool pushed;

  /// 採用伺服器體重時是否為「賽季更新」造成——此時必須無條件採用（即使本機較重）。
  final bool forceAdopt;

  /// 後端指派的小豬品種（GET /pet/state 或推送回應；舊版後端不回則為 null）。
  final String? breed;

  const PetWeightReconcileResult({
    required this.ok,
    this.adoptedWeight,
    this.pushed = false,
    this.forceAdopt = false,
    this.breed,
  });
}

/// 餵食結果。
class PetFeedResult {
  final bool ok;

  /// 伺服器回傳的新體重（失敗為 null）。
  final int? serverWeight;

  /// 餵食回應的賽季比本機記錄的新：伺服器體重已是新賽季的重置後值，
  /// 呼叫端必須無條件採用（即使本機較重）。
  final bool seasonReset;

  /// 餵食回應帶回的品種（後端換季／管理員覆寫時會變；舊版後端為 null）。
  final String? breed;

  const PetFeedResult(
      {required this.ok,
      this.serverWeight,
      this.seasonReset = false,
      this.breed});
}

/// 寵物體重與伺服器同步（伺服器為權威，本機為離線快取）。
///
/// 規則：
/// - 進場／重新整理時先 `GET /pet/state/{id}` 再對帳，絕不在不知道伺服器值
///   的情況下盲目上傳本機預設值（過去會把換機後的真實體重洗成 1.25kg）。
/// - 餵食改送增量（`POST /pet/feed`，帶 client_event_id 冪等）。
/// - 所有失敗都不拋例外，回傳 ok=false，呼叫端保留本機值。
class PetWeightSync {
  static final math.Random _rng = math.Random();

  /// 產生餵食事件 id（時間戳＋隨機數，遠小於後端 64 字元上限）。
  static String newEventId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 30)}';

  /// 對帳。[readLocal] 在拿到伺服器值之後才讀取（期間本機可能已被餵食改動）；
  /// [canWrite] 回傳 false（例如有餵食請求還在飛）時不採用／不推送，避免
  /// 「本機樂觀值被推上去、隨後餵食增量又加一次」造成重複計算。
  static Future<PetWeightReconcileResult> reconcile({
    required String elderId,
    required int Function() readLocal,
    bool Function()? canWrite,
  }) async {
    try {
      final fetched = await PetLeaderboardService.getServerWeight(elderId);
      if (!fetched.ok) return const PetWeightReconcileResult(ok: false);
      final serverBreed = fetched.breed;
      if (canWrite != null && !canWrite()) {
        return PetWeightReconcileResult(ok: true, breed: serverBreed);
      }
      final local = readLocal();
      final localSeason = await PetStorageService.loadSeasonNo();
      final serverSeason = fetched.seasonNo;
      final action = decideWeightAction(
        local: local,
        server: fetched.weight,
        localSeason: localSeason,
        serverSeason: serverSeason,
      );
      // 本機賽季記錄追上伺服器（未知→採用；較舊→更新）。
      if (serverSeason != null && serverSeason != localSeason) {
        await PetStorageService.saveSeasonNo(serverSeason);
      }
      switch (action) {
        case PetWeightAction.keepLocal:
          return PetWeightReconcileResult(ok: true, breed: serverBreed);
        case PetWeightAction.adoptServer:
          return PetWeightReconcileResult(
            ok: true,
            adoptedWeight: fetched.weight,
            forceAdopt: isNewerSeason(local: localSeason, server: serverSeason),
            breed: serverBreed,
          );
        case PetWeightAction.pushLocal:
          final r = await PetLeaderboardService.syncMyState(
            elderId: elderId,
            weightGrams: local,
            // 伺服器沒有體重列時，本機視為屬於現行賽季；其餘帶本機記錄的賽季，
            // 讓後端能擋掉上一季的舊體重。
            seasonNo: fetched.weight == null ? serverSeason : localSeason,
          );
          return PetWeightReconcileResult(
              ok: r.ok, pushed: r.ok && !r.stale, breed: r.breed ?? serverBreed);
      }
    } catch (e) {
      debugPrint('⚠️ [PetWeightSync] reconcile error: $e');
      return const PetWeightReconcileResult(ok: false);
    }
  }

  /// 餵食（增量，冪等）。
  static Future<PetFeedResult> feed({
    required String elderId,
    required int gramsDelta,
    String? clientEventId,
  }) async {
    try {
      final localSeason = await PetStorageService.loadSeasonNo();
      final w = await PetLeaderboardService.feedPet(
        elderId: elderId,
        gramsDelta: gramsDelta,
        clientEventId: clientEventId ?? newEventId(),
      );
      if (w == null) return const PetFeedResult(ok: false);
      final sn = w.seasonNo;
      if (sn != null && sn != localSeason) {
        await PetStorageService.saveSeasonNo(sn);
      }
      return PetFeedResult(
        ok: true,
        serverWeight: w.weight,
        seasonReset: isNewerSeason(local: localSeason, server: sn),
        breed: w.breed,
      );
    } catch (e) {
      debugPrint('⚠️ [PetWeightSync] feed error: $e');
      return const PetFeedResult(ok: false);
    }
  }
}
