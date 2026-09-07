import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// 長輩「朋友圈」社群服務（第四十一輪 item 3）。
///
/// 對應後端 `uban-api/routers/friend.py` 的十個端點。與「家庭圈」
/// （community_service.dart / elder_community_screen.dart）是刻意分開的另一套
/// 系統——好友關係與朋友圈貼文互不相通，共用的只有『長輩』這個身分與既有的
/// 4 位數 `elder_id`。
///
/// 刻意不比照 CommunityService 做 SharedPreferences 離線快取：好友清單與動態
/// 失敗時，UI 顯示空狀態＋重試鍵即可，不需要在本機保存一份朋友圈的副本
/// （團隊要求「不要把離線快取做得比家庭圈複雜」）。
///
/// 錯誤處理慣例沿用 `api_service.dart` 既有寫法（見 `resolveMonitorSetup` /
/// `triggerTestFall`）：FastAPI 的 HTTPException 一律以 `{"detail": "..."}`
/// 回傳，非成功回應優先取 `detail` 當白話錯誤訊息；每個「清單型」端點另外用一個
/// 靜態 `lastXxxError` 欄位記錄「這次失敗的原因」，讓呼叫端能區分「目前沒有資料」
/// 與「這次真的失敗了、要顯示重試鍵」——兩者用同一個空 list 表示的話，UI 就無法分辨。
class FriendService {
  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 非成功回應時的白話錯誤訊息。
  static String _errorMessage(
    http.Response response,
    Map<String, dynamic> data, {
    String fallback = '連線失敗，請稍後再試',
  }) {
    if (response.statusCode == 429) {
      // 對應 friend.py::_check_search_rate_limit（20 次/分鐘）。這裡直接寫死
      // 白話文案，不倚賴後端 detail 字串——就算後端文案之後改了，長輩也不會
      // 看到裸的 429 錯誤碼。
      return '查詢太頻繁，請稍後再試';
    }
    final dynamic detail = data['detail'] ?? data['message'];
    return detail != null ? detail.toString() : fallback;
  }

  // ============================================================
  // 我的 elder_id
  // ============================================================

  /// 取得目前登入長輩自己的 4 位數 `elder_id`。
  ///
  /// ⚠️ 不可用 `userId.toString().padLeft(4, '0')` 臆測——`elder_profile.user_id`
  /// 與 `elder_profile.elder_id` 是資料庫中兩個獨立欄位（`elder_id varchar(4)
  /// PRI`，`user_id int MUL`），數值不保證相同。`elder_profile_tab.dart` 既有的
  /// `_showFamilyPairingDialog` 用 padLeft 巧合式推算是舊碼、且用途是配對碼
  /// （不要求與 elder_id 一致），本服務一律呼叫既有的
  /// `GET /api/user/profile/{userId}`（`ApiService.getElderProfile`）取得
  /// 權威的 `elder_id` 欄位。找不到時回傳 null，呼叫端應顯示白話錯誤並提供重試。
  static Future<String?> resolveMyElderId(int userId) async {
    try {
      final result = await ApiService.getElderProfile(userId);
      if (result['status'] == 'success') {
        final data = result['data'];
        if (data is Map && data['elder_id'] != null) {
          final id = data['elder_id'].toString();
          if (id.isNotEmpty) return id;
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [FriendService] resolveMyElderId error: $e');
      return null;
    }
  }

  // ============================================================
  // 搜尋 / 邀請 / 名單
  // ============================================================

  /// 上一次 [searchElder] 失敗的白話原因（含 429 限流／404 查無此人／連線失敗）。
  /// 成功時重置為 null。
  static String? lastSearchError;

  static Future<Map<String, dynamic>?> searchElder({
    required String elderId,
    required String requesterElderId,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/friend/search').replace(
        queryParameters: {
          'elder_id': elderId,
          'requester_elder_id': requesterElderId,
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastSearchError = null;
        return data['data'] as Map<String, dynamic>?;
      }
      lastSearchError = _errorMessage(response, data, fallback: '找不到這位長輩');
      return null;
    } catch (e) {
      debugPrint('⚠️ [FriendService] searchElder error: $e');
      lastSearchError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }

  /// 上一次 [sendFriendRequest] 失敗的白話原因（含 409「已經是好友」／
  /// 409「邀請已送出，等待對方回應」）。成功時重置為 null。
  static String? lastRequestError;

  static Future<bool> sendFriendRequest({
    required String fromElderId,
    required String toElderId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/friend/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from_elder_id': fromElderId,
              'to_elder_id': toElderId,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastRequestError = null;
        return true;
      }
      lastRequestError = _errorMessage(response, data, fallback: '送出邀請失敗，請稍後再試');
      return false;
    } catch (e) {
      debugPrint('⚠️ [FriendService] sendFriendRequest error: $e');
      lastRequestError = '無法連線到後端，請確認網路狀態';
      return false;
    }
  }

  /// 上一次 [getIncomingRequests] 失敗的白話原因；成功（含「目前沒有邀請」的
  /// 合法空清單）時重置為 null。
  static String? lastRequestsError;

  static Future<List<dynamic>> getIncomingRequests(String elderId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/friend/requests')
          .replace(queryParameters: {'elder_id': elderId});
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 &&
          data['status'] == 'success' &&
          data['data'] is List) {
        lastRequestsError = null;
        return data['data'] as List<dynamic>;
      }
      lastRequestsError = _errorMessage(response, data, fallback: '好友邀請載入失敗');
      return [];
    } catch (e) {
      debugPrint('⚠️ [FriendService] getIncomingRequests error: $e');
      lastRequestsError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  static Future<bool> respondToRequest({
    required String elderId,
    required int requestId,
    required bool accept,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/friend/respond'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elder_id': elderId,
              'request_id': requestId,
              'accept': accept,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      return response.statusCode == 200 && data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ [FriendService] respondToRequest error: $e');
      return false;
    }
  }

  /// 上一次 [getFriendList] 失敗的白話原因；成功（含「目前沒有好友」的合法
  /// 空清單）時重置為 null。
  static String? lastFriendListError;

  static Future<List<dynamic>> getFriendList(String elderId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/friend/list')
          .replace(queryParameters: {'elder_id': elderId});
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 &&
          data['status'] == 'success' &&
          data['data'] is List) {
        lastFriendListError = null;
        return data['data'] as List<dynamic>;
      }
      lastFriendListError = _errorMessage(response, data, fallback: '好友清單載入失敗');
      return [];
    } catch (e) {
      debugPrint('⚠️ [FriendService] getFriendList error: $e');
      lastFriendListError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  static Future<bool> removeFriend({
    required String elderId,
    required String friendElderId,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/friend/friend').replace(
        queryParameters: {
          'elder_id': elderId,
          'friend_elder_id': friendElderId,
        },
      );
      final response = await http.delete(uri).timeout(_timeout);
      final data = _decode(response);
      return response.statusCode == 200 && data['status'] == 'success';
    } catch (e) {
      debugPrint('⚠️ [FriendService] removeFriend error: $e');
      return false;
    }
  }

  // ============================================================
  // 朋友圈動態
  // ============================================================

  /// 上一次 [getFeed] 失敗的白話原因；成功（含「目前沒有動態」的合法空清單）
  /// 時重置為 null。
  static String? lastFeedError;

  static Future<List<dynamic>> getFeed({
    required String elderId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/friend/feed').replace(
        queryParameters: {
          'elder_id': elderId,
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 &&
          data['status'] == 'success' &&
          data['data'] is List) {
        lastFeedError = null;
        return data['data'] as List<dynamic>;
      }
      lastFeedError = _errorMessage(response, data, fallback: '動態載入失敗，請稍後再試');
      return [];
    } catch (e) {
      debugPrint('⚠️ [FriendService] getFeed error: $e');
      lastFeedError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createPost({
    required String authorElderId,
    required String content,
    String? imageUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/friend/post'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'author_elder_id': authorElderId,
              'content': content,
              if (imageUrl != null) 'image_url': imageUrl,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        return data['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [FriendService] createPost error: $e');
      return null;
    }
  }

  /// 成功時回傳最新的 like_count；失敗回傳 null。
  static Future<int?> likePost({
    required int postId,
    required String elderId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/friend/post/$postId/like'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'elder_id': elderId}),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        final likeCount = data['data']?['like_count'];
        if (likeCount is int) return likeCount;
        return int.tryParse('$likeCount');
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [FriendService] likePost error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> commentOnPost({
    required int postId,
    required String authorElderId,
    required String content,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/friend/post/$postId/comment'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'author_elder_id': authorElderId,
              'content': content,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        return data['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [FriendService] commentOnPost error: $e');
      return null;
    }
  }
}
