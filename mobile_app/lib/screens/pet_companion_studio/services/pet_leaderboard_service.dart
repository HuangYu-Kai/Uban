import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/api_service.dart';

/// 好友寵物排行榜服務。
///
/// 對應後端 `uban-api/routers/pet.py` 的兩個端點：
/// - `POST /api/pet/state`：上傳／更新自己的寵物體重（UPSERT）。
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
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/pet/state'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'weight_grams': weightGrams,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      return response.statusCode == 200 && data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ [PetLeaderboardService] uploadMyState error: $e');
      return false;
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
