import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// 家屬首頁「最新警示」滑掉紀錄（後端 `/api/family_alert_dismissal`）。
///
/// 原本只存手機本機，清資料／重裝／換手機就消失；現在每位家屬一份存在後端。
/// 只收 `alert:<id>`／`log:<id>` 兩種穩定鍵（見 [isPersistableKey]）。
class FamilyAlertDismissalApi {
  static final RegExp _keyRe = RegExp(r'^(alert|log):\d{1,18}$');

  /// 能存到後端的鍵：後端資料表的整數 PK，重新抓取時不會變。
  static bool isPersistableKey(String key) => _keyRe.hasMatch(key);

  /// 讀取該家屬最近 30 天滑掉的鍵。失敗**丟出例外**（呼叫端退回只用本機）。
  static Future<List<String>> fetchKeys(int familyId) async {
    final res = await ApiClient.get('/family_alert_dismissal/$familyId');
    if (res != null && res['status'] == 'success' && res['data'] is Map) {
      final keys = (res['data'] as Map)['keys'];
      if (keys is List) return [for (final k in keys) k.toString()];
    }
    throw Exception('fetchKeys: unexpected response');
  }

  /// 記錄一則滑掉的警示。冪等；失敗回 false、不丟例外。
  static Future<bool> dismiss(int familyId, String itemKey) async {
    try {
      final res = await ApiClient.post(
          '/family_alert_dismissal/$familyId', {'item_key': itemKey});
      return res != null && res['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ FamilyAlertDismissalApi.dismiss error: $e');
      return false;
    }
  }

  /// 純函式：本機與後端的鍵合併。
  /// - [toAddLocally]：後端有、本機沒有（別台裝置滑掉的）→ 寫進本機。
  /// - [toUpload]：本機有、後端沒有（離線時滑掉、或功能上線前的舊紀錄）→ 補送後端，最多 [maxUpload] 筆。
  static ({Set<String> toAddLocally, List<String> toUpload}) reconcile(
    Iterable<String> local,
    Iterable<String> server, {
    int maxUpload = 50,
  }) {
    final serverSet = {for (final k in server) if (isPersistableKey(k)) k};
    final localSet = {for (final k in local) if (isPersistableKey(k)) k};
    return (
      toAddLocally: serverSet.difference(localSet),
      toUpload: localSet.difference(serverSet).take(maxUpload).toList(),
    );
  }
}
