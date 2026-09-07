import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// 家屬「朋友圈」社群服務（第五項需求：家屬好友系統，家屬端一半）。
///
/// 對應後端 `uban-api/routers/family_friend.py` 的十一個端點，設計思路與
/// 長輩版 `friend_service.dart` 一致，但識別鍵是家屬自己的 `family_id`
/// （＝ SharedPreferences 既有的 `caregiver_id`，呼叫端已經有，不需要像
/// 長輩那樣另外呼叫一支 API 反查——這是與 [FriendService] 最大的差異）。
///
/// 好友代碼是後端惰性產生的 4 碼數字 `family_code`，概念上對應長輩的
/// `elder_id`，但刻意不重用長輩任何一張表——好友關係／貼文／留言／按讚
/// 全部走獨立的 `family_friend_*` 系列資料表，與長輩朋友圈（`friend_*`）
/// 及家庭圈（`community_posts`）三邊資料互不相通，避免任何一邊查詢寫錯
/// 表就外洩到另一邊。
///
/// 錯誤處理慣例沿用 `friend_service.dart`：非成功回應優先取 `detail` 當
/// 白話錯誤訊息；每個「清單型」端點另外用一個靜態 `lastXxxError` 欄位記錄
/// 「這次失敗的原因」，讓呼叫端能區分「目前沒有資料」與「這次真的失敗了、
/// 要顯示重試鍵」——兩者用同一個空 list 表示的話，UI 就無法分辨。
class FamilyFriendService {
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
      // 對應 family_friend.py::_check_search_rate_limit（20 次/分鐘）。這裡
      // 直接寫死白話文案，不倚賴後端 detail 字串（後端目前回「搜尋太頻繁」，
      // 與這裡文案不必逐字相同）——就算後端文案之後改了，家屬也不會看到
      // 裸的 429 錯誤碼或前後不一致的措辭。
      return '查詢太頻繁，請稍後再試';
    }
    final dynamic detail = data['detail'] ?? data['message'];
    return detail != null ? detail.toString() : fallback;
  }

  // ============================================================
  // 好友代碼
  // ============================================================

  /// 上一次 [getMyCode] 失敗的白話原因；成功時重置為 null。
  static String? lastMyCodeError;

  /// 取得（必要時後端會惰性產生）自己的 4 碼好友代碼。
  static Future<String?> getMyCode(int familyId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/my-code')
          .replace(queryParameters: {'family_id': familyId.toString()});
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastMyCodeError = null;
        final code = data['data']?['family_code'];
        return code?.toString();
      }
      lastMyCodeError = _errorMessage(response, data, fallback: '無法取得好友代碼');
      return null;
    } catch (e) {
      debugPrint('⚠️ [FamilyFriendService] getMyCode error: $e');
      lastMyCodeError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }

  // ============================================================
  // 搜尋 / 邀請 / 名單
  // ============================================================

  /// 上一次 [searchFamily] 失敗的白話原因（含 429 限流／404 查無此人／
  /// 連線失敗）。成功時重置為 null。
  static String? lastSearchError;

  static Future<Map<String, dynamic>?> searchFamily({
    required String familyCode,
    required int requesterFamilyId,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/search').replace(
        queryParameters: {
          'family_code': familyCode,
          'requester_family_id': requesterFamilyId.toString(),
        },
      );
      final response = await http.get(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastSearchError = null;
        return data['data'] as Map<String, dynamic>?;
      }
      lastSearchError = _errorMessage(response, data, fallback: '找不到這位家屬');
      return null;
    } catch (e) {
      debugPrint('⚠️ [FamilyFriendService] searchFamily error: $e');
      lastSearchError = '無法連線到後端，請確認網路狀態';
      return null;
    }
  }

  /// 上一次 [sendFriendRequest] 失敗的白話原因（含 400「不能加自己」／
  /// 404「目標不存在」／409「已經是好友」或「邀請已送出」）。成功時重置為
  /// null。
  static String? lastRequestError;

  static Future<bool> sendFriendRequest({
    required int fromFamilyId,
    required int toFamilyId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/family-friend/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from_family_id': fromFamilyId,
              'to_family_id': toFamilyId,
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
      debugPrint('⚠️ [FamilyFriendService] sendFriendRequest error: $e');
      lastRequestError = '無法連線到後端，請確認網路狀態';
      return false;
    }
  }

  /// 上一次 [getIncomingRequests] 失敗的白話原因；成功（含「目前沒有邀請」
  /// 的合法空清單）時重置為 null。
  static String? lastRequestsError;

  static Future<List<dynamic>> getIncomingRequests(int familyId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/requests')
          .replace(queryParameters: {'family_id': familyId.toString()});
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
      debugPrint('⚠️ [FamilyFriendService] getIncomingRequests error: $e');
      lastRequestsError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  /// 上一次 [respondToRequest] 失敗的白話原因（404＝邀請不存在／不是收件者
  /// ／已處理，一律用同一句話呈現，不細分——細分等於洩漏 request_id 是否
  /// 存在）。成功時重置為 null。
  static String? lastRespondError;

  static Future<bool> respondToRequest({
    required int familyId,
    required int requestId,
    required bool accept,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/family-friend/respond'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'request_id': requestId,
              'accept': accept,
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastRespondError = null;
        return true;
      }
      lastRespondError =
          _errorMessage(response, data, fallback: '此邀請已處理或不存在，請重新整理');
      return false;
    } catch (e) {
      debugPrint('⚠️ [FamilyFriendService] respondToRequest error: $e');
      lastRespondError = '無法連線到後端，請確認網路狀態';
      return false;
    }
  }

  /// 上一次 [getFriendList] 失敗的白話原因；成功（含「目前沒有好友」的合法
  /// 空清單）時重置為 null。
  static String? lastFriendListError;

  static Future<List<dynamic>> getFriendList(int familyId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/list')
          .replace(queryParameters: {'family_id': familyId.toString()});
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
      debugPrint('⚠️ [FamilyFriendService] getFriendList error: $e');
      lastFriendListError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  /// 上一次 [removeFriend] 失敗的白話原因（404＝不是好友關係）。成功時
  /// 重置為 null。
  static String? lastRemoveFriendError;

  static Future<bool> removeFriend({
    required int familyId,
    required int friendFamilyId,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/friend').replace(
        queryParameters: {
          'family_id': familyId.toString(),
          'friend_family_id': friendFamilyId.toString(),
        },
      );
      final response = await http.delete(uri).timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['status'] == 'success') {
        lastRemoveFriendError = null;
        return true;
      }
      lastRemoveFriendError = _errorMessage(response, data, fallback: '解除好友失敗，請稍後再試');
      return false;
    } catch (e) {
      debugPrint('⚠️ [FamilyFriendService] removeFriend error: $e');
      lastRemoveFriendError = '無法連線到後端，請確認網路狀態';
      return false;
    }
  }

  // ============================================================
  // 朋友圈動態
  // ============================================================

  /// 上一次 [getFeed] 失敗的白話原因；成功（含「目前沒有動態」的合法空
  /// 清單）時重置為 null。
  static String? lastFeedError;

  static Future<List<dynamic>> getFeed({
    required int familyId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/family-friend/feed').replace(
        queryParameters: {
          'family_id': familyId.toString(),
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
      debugPrint('⚠️ [FamilyFriendService] getFeed error: $e');
      lastFeedError = '無法連線到後端，請確認網路狀態';
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createPost({
    required int authorFamilyId,
    required String content,
    String? imageUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/family-friend/post'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'author_family_id': authorFamilyId,
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
      debugPrint('⚠️ [FamilyFriendService] createPost error: $e');
      return null;
    }
  }

  /// 成功時回傳最新的 like_count；失敗回傳 null。按讚在後端刻意不是
  /// toggle（見 family_friend.py::like_friend_post），重複呼叫冪等，不會
  /// 重複計數也沒有「取消讚」。
  static Future<int?> likePost({
    required int postId,
    required int familyId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/family-friend/post/$postId/like'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'family_id': familyId}),
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
      debugPrint('⚠️ [FamilyFriendService] likePost error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> commentOnPost({
    required int postId,
    required int authorFamilyId,
    required String content,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/family-friend/post/$postId/comment'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'author_family_id': authorFamilyId,
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
      debugPrint('⚠️ [FamilyFriendService] commentOnPost error: $e');
      return null;
    }
  }
}
