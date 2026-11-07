// ★ 2026-11-07：「已取消／已結束／已拒接的 callId」跨 isolate 持久記錄（短 TTL）。
//
// 為什麼需要：`Signaling._invalidCallIds` 是記憶體 Set，主 isolate、FCM 背景 isolate、
// 冷啟動後的新 isolate 各有一份、彼此看不到。結果：
//   - 發起端取消後，背景 isolate 才抵達的（延遲）來電 FCM 仍然會響；
//   - 被叫端按「拒絕」時發起端其實早取消了，各路徑不知道這通已經結束；
//   - 冷啟動讀到 pendingRingCallData／pendingLocalRingCall 又重彈一個早已取消的來電畫面。
// 這裡把 callId 寫進 SharedPreferences（單一 JSON 字串，TTL 5 分鐘，遠大於 60 秒來電有效期，
// 上限 50 筆），讓所有路徑都能同步查詢。
//
// 純函式（parse／add／contains）無任何 Flutter 相依，可單元測試；
// 存取 prefs 的 [CancelledCallStore] 全部包 try/catch，任何失敗一律「當作沒有記錄」，
// 絕不阻斷來電、拒接、取消流程（寧可多響也不能吞掉來電）。

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 鍵：JSON 物件 `{callId: epochMs}`。
const String kCancelledCallIdsKey = 'cancelledCallIds';

/// 記憶期限（毫秒）。必須大於來電有效期 [kCallValidityMs]（60s），
/// 才能擋住「取消後才抵達的延遲來電」；5 分鐘與後端 `_CANCELLED_CALL_TTL_SEC` 對齊。
const int kCancelledCallTtlMs = 5 * 60 * 1000;

/// 最多保留幾筆（超過時丟最舊的）。
const int kCancelledCallMax = 50;

/// 解析 prefs 字串並同時剔除過期項。壞資料一律回空 Map。
Map<String, int> parseCancelledCalls(String? raw, int nowMs) {
  if (raw == null || raw.isEmpty) return <String, int>{};
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, int>{};
    final Map<String, int> out = <String, int>{};
    decoded.forEach((k, v) {
      final int? ts = v is int ? v : int.tryParse('$v');
      if (k is String && k.isNotEmpty && ts != null && nowMs - ts <= kCancelledCallTtlMs) {
        out[k] = ts;
      }
    });
    return out;
  } catch (_) {
    return <String, int>{};
  }
}

/// 回傳加入 [callId] 後的新 Map（不改動傳入的 Map）；空 callId 原樣回傳。
Map<String, int> addCancelledCall(Map<String, int> current, String? callId, int nowMs) {
  final String id = (callId ?? '').trim();
  final Map<String, int> next = Map<String, int>.from(current);
  if (id.isEmpty) return next;
  next[id] = nowMs;
  if (next.length > kCancelledCallMax) {
    final List<MapEntry<String, int>> sorted = next.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in sorted.take(next.length - kCancelledCallMax)) {
      next.remove(e.key);
    }
  }
  return next;
}

/// [callId] 是否在已取消清單內（含 TTL 判斷）。空 callId 一律 false。
bool isCallIdCancelled(Map<String, int> current, String? callId, int nowMs) {
  final String id = (callId ?? '').trim();
  if (id.isEmpty) return false;
  final int? ts = current[id];
  return ts != null && nowMs - ts <= kCancelledCallTtlMs;
}

String encodeCancelledCalls(Map<String, int> map) => jsonEncode(map);

/// 拒接結果文案（純函式，供拒接回饋通知使用）。
///
/// 發起端已取消／掛斷（[alreadyEnded]）時，「拒絕」本來就不需要通知任何人，
/// 對使用者而言是成功（來電畫面已關），不能顯示「拒接時發生問題，請確認網路」。
({String title, String body}) declineFeedbackText({
  required bool alreadyEnded,
  required bool success,
}) {
  if (alreadyEnded) {
    return (title: '來電已結束', body: '對方已先取消這通來電');
  }
  if (success) {
    return (title: '已拒接來電', body: '已通知對方您無法接聽');
  }
  return (title: '拒接時發生問題', body: '請確認網路連線後再試一次');
}

/// 是否還需要送出拒接給伺服器：已知發起端取消／掛斷就不必送（省一次網路請求與可能的錯誤）。
bool shouldSendDeclineToServer({required bool alreadyEnded}) => !alreadyEnded;

class CancelledCallStore {
  CancelledCallStore._();

  /// 記錄 [callId] 已取消／結束／拒接。失敗只印 log。
  static Future<void> mark(String? callId) async {
    if (kIsWeb) return;
    final String id = (callId ?? '').trim();
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 背景 isolate 與主 isolate 各有 prefs 快取：寫入前先 reload，避免互相覆蓋對方剛寫的項目。
      try {
        await prefs.reload();
      } catch (_) {}
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, int> current =
          parseCancelledCalls(prefs.getString(kCancelledCallIdsKey), now);
      await prefs.setString(
          kCancelledCallIdsKey, encodeCancelledCalls(addCancelledCall(current, id, now)));
    } catch (e) {
      debugPrint('⚠️ [CancelledCallStore] mark 失敗（忽略）: $e');
    }
  }

  /// 查詢 [callId] 是否已取消。查詢失敗回 false（寧可多響）。
  static Future<bool> isCancelled(String? callId, {bool reload = true}) async {
    if (kIsWeb) return false;
    final String id = (callId ?? '').trim();
    if (id.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reload) {
        try {
          await prefs.reload();
        } catch (_) {}
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      return isCallIdCancelled(
          parseCancelledCalls(prefs.getString(kCancelledCallIdsKey), now), id, now);
    } catch (e) {
      debugPrint('⚠️ [CancelledCallStore] isCancelled 失敗（視為未取消）: $e');
      return false;
    }
  }

  /// 讀出目前所有未過期的已取消 callId（供 Signaling 啟動時灌進記憶體 Set）。
  static Future<Set<String>> allCancelled() async {
    if (kIsWeb) return <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      final int now = DateTime.now().millisecondsSinceEpoch;
      return parseCancelledCalls(prefs.getString(kCancelledCallIdsKey), now).keys.toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
