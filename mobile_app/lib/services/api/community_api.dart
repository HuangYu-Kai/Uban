import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// 家庭溫馨社群貼文、點讚、留言與圖片上傳 API
class CommunityApi {
  /// 取得家庭社群貼文列表
  static Future<List<dynamic>> getCommunityPosts({
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
      return [];
    } catch (e) {
      debugPrint('⚠️ getCommunityPosts error: $e');
      return [];
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
