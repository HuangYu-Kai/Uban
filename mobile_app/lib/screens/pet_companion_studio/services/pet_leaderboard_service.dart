import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';

/// 好友寵物排行榜服務。
///
/// 對應後端 `uban-api/routers/pet.py` 的兩個端點：
/// - `POST /api/pet/state`：上傳本機體重（後端只增不減）；`GET /api/pet/state/{id}`
///   讀伺服器體重、`POST /api/pet/feed` 餵食增量（見 pet_weight_sync.dart 的對帳規則）。
/// - `GET /api/pet/leaderboard/{elder_id}`：取得「自己 + 已接受好友」的完整
///   排行榜（後端已經算好名次與跟上一名的差距，本服務不重算）。
///
/// 錯誤處理慣例沿用 `friend_service.dart`：非成功回應優先取 `detail` 當白話
/// 錯誤訊息；失敗時回傳 null／false，並記在靜態的 `lastLeaderboardError`
/// 欄位讓呼叫端能顯示重試鍵。上傳失敗刻意不拋例外給呼叫端——寵物養成的本機
/// 存檔與動畫不應該因為排行榜同步失敗而被中斷。
class PetLeaderboardService {
  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _errorMessage(
    http.Response response,
    Map<String, dynamic> data, {
    String fallback = '連線失敗，請稍後再試',
  }) {
    final dynamic detail = data['detail'] ?? data['message'];
    return detail != null ? detail.toString() : fallback;
  }

  /// 上傳／更新自己的寵物體重。成功回傳 true。
  ///
  /// 刻意不拋出例外——呼叫端（pet_studio_screen.dart）在餵食、進入畫面等
  /// 時機呼叫本方法，任何失敗都只應該記 log，不能影響既有的寵物養成功能
  /// （本機存檔／動畫／音效一律照常進行）。
  static Future<bool> uploadMyState({
    required String elderId,
    required int weightGrams,
  }) async {
    final r = await syncMyState(elderId: elderId, weightGrams: weightGrams);
    return r.ok;
  }

  /// 同 [uploadMyState]，另外帶回後端指派的小豬品種（`pink`／`black`）。
  /// 品種由系統在小豬第一次建立時隨機指派、開發者可覆寫，App 不能自行切換。
  /// 失敗或後端舊版沒回 `breed` 時 `breed` 為 null（呼叫端沿用本機快取）。
  static Future<({bool ok, String? breed, int? seasonNo, bool stale})>
      syncMyState({
    required String elderId,
    required int weightGrams,
    int? seasonNo,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/pet/state'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'weight_grams': weightGrams,
              if (seasonNo != null) 'season_no': seasonNo,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      final ok = response.statusCode == 200 && data['status'] == 'success';
      String? breed;
      final payload = data['data'];
      if (ok && payload is Map && payload['breed'] is String) {
        breed = payload['breed'] as String;
      }
      final sn = payload is Map ? payload['season_no'] : null;
      final stale = payload is Map && payload['stale_season'] == true;
      return (
        ok: ok,
        breed: breed,
        seasonNo: sn is num ? sn.toInt() : null,
        stale: stale,
      );
    } catch (e) {
      debugPrint('⚠️ [PetLeaderboardService] uploadMyState error: $e');
      return (ok: false, breed: null, seasonNo: null, stale: false);
    }
  }

  /// 讀取伺服器上的寵物體重（`GET /api/pet/state/{elder_id}`）。
  /// `ok` 代表請求成功；`weight` 為 null 代表伺服器尚無此長輩的體重列。
  /// 失敗不拋例外（ok=false），呼叫端保留本機值。
  static Future<({bool ok, int? weight, int? seasonNo})> getServerWeight(
      String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/pet/state/$elderId'))
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final payload = data['data'];
        final w = payload is Map ? payload['weight_grams'] : null;
        final sn = payload is Map ? payload['season_no'] : null;
        return (
          ok: true,
          weight: w is num ? w.toInt() : null,
          seasonNo: sn is num ? sn.toInt() : null,
        );
      }
      return (ok: false, weight: null, seasonNo: null);
    } catch (e) {
      debugPrint('⚠️ [PetLeaderboardService] getServerWeight error: $e');
      return (ok: false, weight: null, seasonNo: null);
    }
  }

  /// 餵食（`POST /api/pet/feed`）：送增量，伺服器原子累加並回傳新體重；
  /// 同一個 [clientEventId] 重送不會重複加。回傳新體重與現行賽季；失敗回傳 null。
  static Future<({int weight, int? seasonNo})?> feedPet({
    required String elderId,
    required int gramsDelta,
    required String clientEventId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/pet/feed'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'grams_delta': gramsDelta,
              'client_event_id': clientEventId,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final payload = data['data'];
        final w = payload is Map ? payload['weight_grams'] : null;
        final sn = payload is Map ? payload['season_no'] : null;
        if (w is! num) return null;
        return (weight: w.toInt(), seasonNo: sn is num ? sn.toInt() : null);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [PetLeaderboardService] feedPet error: $e');
      return null;
    }
  }

  /// 上一次 [getLeaderboard] 失敗的白話原因；成功時重置為 null。
  static String? lastLeaderboardError;

  /// 取得排行榜。成功時回傳後端 `data` 物件（含 `my_elder_id` / `my_rank` /
  /// `total_count` / `entries`），失敗回傳 null。
  static Future<Map<String, dynamic>?> getLeaderboard(String elderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/pet/leaderboard/$elderId'))
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastLeaderboardError = null;
        return data['data'] as Map<String, dynamic>?;
      }
      lastLeaderboardError = _errorMessage(response, data, fallback: '排行榜載入失敗，請稍後再試');
      return null;
    } catch (e) {
      debugPrint('⚠️ [PetLeaderboardService] getLeaderboard error: $e');
      lastLeaderboardError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }
}
