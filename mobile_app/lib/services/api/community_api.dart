import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 家庭溫馨社群貼文、點讚、留言與圖片上傳 API
class CommunityApi {
  /// 取得家庭社群貼文列表。
  ///
  /// ★ 2026-09-22 第五十一輪：回傳型別改為可為 null——**null＝這次呼叫失敗**
  /// （離線、逾時、伺服器錯誤或回傳非 success），**空清單＝真的一則貼文都沒有**。
  /// 舊版兩種情況都回 `[]`，於是 `CommunityService.getPosts` 的「遠端成功即為
  /// 單一真相」會把離線誤判成「後端說沒有貼文」，拿空清單覆蓋本機快取——長輩
  /// 在沒網路時發的貼文下一次載入就會消失，`lastFetchWasOffline` 也永遠是
  /// false（離線提示從來不會出現）。
  static Future<List<dynamic>?> getCommunityPosts({
    int? familyId,
    int? userId,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      if (familyId != null) queryParams['family_id'] = familyId.toString();
      if (userId != null) queryParams['user_id'] = userId.toString();

      final uri = Uri.parse('${ApiClient.baseUrl}/community/posts').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] is List) {
        return data['data'];
      }
      debugPrint('⚠️ getCommunityPosts: 後端回應非 success，視為呼叫失敗');
      return null;
    } catch (e) {
      debugPrint('⚠️ getCommunityPosts error: $e');
      return null;
    }
  }

  /// 發佈社群近況貼文
  static Future<Map<String, dynamic>?> createCommunityPost({
    required int familyId,
    required int authorId,
    required String authorName,
    String authorRole = 'elder',
    required String content,
    String mood = '😊',
    String? stampType,
    String? imageUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/community/posts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'family_id': familyId,
              'author_id': authorId,
              'author_name': authorName,
              'author_role': authorRole,
              'content': content,
              'mood': mood,
              if (stampType != null) 'stamp_type': stampType,
              if (imageUrl != null) 'image_url': imageUrl,
            }),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ createCommunityPost error: $e');
      return null;
    }
  }

  /// 切換貼文「關心 ❤️」狀態
  static Future<Map<String, dynamic>?> toggleCommunityPostLike({
    required int postId,
    required int userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/community/posts/$postId/like'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ toggleCommunityPostLike error: $e');
      return null;
    }
  }

  /// 新增貼文留言
  static Future<Map<String, dynamic>?> addCommunityComment({
    required int postId,
    required int authorId,
    required String authorName,
    String authorRole = 'elder',
    required String message,
    String? imageUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiClient.baseUrl}/community/posts/$postId/comments'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'author_id': authorId,
              'author_name': authorName,
              'author_role': authorRole,
              'message': message,
              if (imageUrl != null) 'image_url': imageUrl,
            }),
          )
          .timeout(ApiClient.timeout);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success') {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ addCommunityComment error: $e');
      return null;
    }
  }

  /// 上傳社群圖片（Multipart Form-Data）
  static Future<String?> uploadCommunityImage(File imageFile) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/community/upload');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final streamedResponse = await request.send().timeout(ApiClient.timeout);
      final response = await http.Response.fromStream(streamedResponse);
      final data = ApiClient.safeDecode(response);
      if (data['status'] == 'success' && data['data'] != null && data['data']['url'] != null) {
        final relativeUrl = data['data']['url'] as String;
        if (relativeUrl.startsWith('http')) {
          return relativeUrl;
        }
        return '${ApiClient.serverRootUrl}$relativeUrl';
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ uploadCommunityImage error: $e');
      return null;
    }
  }
}
