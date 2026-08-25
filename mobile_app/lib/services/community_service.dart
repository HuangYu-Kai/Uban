import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_post.dart';
import 'api_service.dart';

class CommunityService {
  static const String _storageKeyPrefix = 'elder_community_posts';

  SharedPreferences? _preferences;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  /// 取得社群貼文（優先從後端 API 載入最新資料，並更新本地快取；離線時使用本地快取）
  Future<List<CommunityPost>> getPosts({
    required int userId,
    required String userName,
    int? familyId,
  }) async {
    _ensureInitialized();

    // 1. 優先嘗試從遠端 API 獲取
    try {
      final remoteData = await ApiService.getCommunityPosts(
        familyId: familyId,
        userId: userId,
      );

      if (remoteData.isNotEmpty) {
        final posts = remoteData
            .whereType<Map>()
            .map((post) => CommunityPost.fromJson(
                  post.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList();
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _savePosts(userId, posts);
        return posts;
      }
    } catch (e) {
      debugPrint('⚠️ [CommunityService] Remote fetch failed, fallback to local: $e');
    }

    // 2. 離線或 API 暫時無資料時，讀取本地快取
    final storageKey = _storageKey(userId);
    final storedValue = _preferences!.getString(storageKey);

    if (storedValue != null && storedValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedValue);
        if (decoded is List) {
          final posts = decoded
              .whereType<Map>()
              .map((post) => CommunityPost.fromJson(
                    post.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList();
          posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return posts;
        }
      } catch (_) {}
    }

    // 3. 初次使用且無任何資料時，提供溫馨預設資料
    final seededPosts = _buildWelcomePosts(userName);
    await _savePosts(userId, seededPosts);
    return seededPosts;
  }

  /// 發佈新貼文
  Future<List<CommunityPost>> createPost({
    required int userId,
    required String userName,
    String userRole = 'elder',
    int? familyId,
    required String content,
    required String mood,
    String? stampType,
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    bool remoteSuccess = false;

    // 1. 嘗試同步至遠端
    try {
      final res = await ApiService.createCommunityPost(
        familyId: familyId ?? userId,
        authorId: userId,
        authorName: userName,
        authorRole: userRole,
        content: content,
        mood: mood,
        stampType: stampType,
        imageUrl: imageUrl,
      );
      if (res != null) {
        remoteSuccess = true;
      }
    } catch (e) {
      debugPrint('⚠️ [CommunityService] createPost remote sync error: $e');
    }

    if (remoteSuccess) {
      return await getPosts(userId: userId, userName: userName, familyId: familyId);
    }

    // 2. 離線本地即時更新
    final posts = await getPosts(userId: userId, userName: userName, familyId: familyId);
    final newPost = CommunityPost(
      id: 'post-${now.microsecondsSinceEpoch}',
      familyId: familyId ?? userId,
      authorId: userId,
      authorName: userName,
      authorRole: userRole,
      content: content.trim(),
      mood: mood,
      stampType: stampType,
      imageUrl: imageUrl,
      imagePath: imageUrl,
      createdAt: now,
      likeCount: 0,
      isLiked: false,
      comments: const [],
    );

    // 避免重複新增
    if (!posts.any((p) => p.content == newPost.content && p.createdAt.difference(now).inSeconds.abs() < 5)) {
      posts.insert(0, newPost);
      await _savePosts(userId, posts);
    }

    return posts;
  }

  /// 切換關心/按讚狀態
  Future<List<CommunityPost>> toggleLike({
    required int userId,
    required String userName,
    int? familyId,
    required String postId,
  }) async {
    final intPostId = int.tryParse(postId);
    bool remoteSuccess = false;

    // 1. 嘗試同步至遠端
    if (intPostId != null) {
      try {
        final res = await ApiService.toggleCommunityPostLike(
          postId: intPostId,
          userId: userId,
        );
        if (res != null) {
          remoteSuccess = true;
        }
      } catch (e) {
        debugPrint('⚠️ [CommunityService] toggleLike remote sync error: $e');
      }
    }

    if (remoteSuccess) {
      return await getPosts(userId: userId, userName: userName, familyId: familyId);
    }

    // 2. 離線本地狀態即時響應
    final posts = await getPosts(userId: userId, userName: userName, familyId: familyId);
    final postIndex = posts.indexWhere((post) => post.id == postId);
    if (postIndex == -1) return posts;

    final post = posts[postIndex];
    posts[postIndex] = post.copyWith(
      isLiked: !post.isLiked,
      likeCount: post.isLiked
          ? (post.likeCount - 1).clamp(0, 999999)
          : post.likeCount + 1,
    );
    await _savePosts(userId, posts);
    return posts;
  }

  /// 新增留言
  Future<List<CommunityPost>> addComment({
    required int userId,
    required String userName,
    String userRole = 'elder',
    int? familyId,
    required String postId,
    required String message,
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    final intPostId = int.tryParse(postId);
    bool remoteSuccess = false;

    // 1. 嘗試同步至遠端
    if (intPostId != null) {
      try {
        final res = await ApiService.addCommunityComment(
          postId: intPostId,
          authorId: userId,
          authorName: userName,
          authorRole: userRole,
          message: message,
          imageUrl: imageUrl,
        );
        if (res != null) {
          remoteSuccess = true;
        }
      } catch (e) {
        debugPrint('⚠️ [CommunityService] addComment remote sync error: $e');
      }
    }

    if (remoteSuccess) {
      return await getPosts(userId: userId, userName: userName, familyId: familyId);
    }

    // 2. 離線本地即時更新
    final posts = await getPosts(userId: userId, userName: userName, familyId: familyId);
    final postIndex = posts.indexWhere((post) => post.id == postId);
    if (postIndex == -1) return posts;

    final post = posts[postIndex];
    posts[postIndex] = post.copyWith(
      comments: [
        ...post.comments,
        CommunityComment(
          id: 'comment-${now.microsecondsSinceEpoch}',
          authorName: userName,
          authorRole: userRole,
          message: message.trim(),
          imagePath: imageUrl,
          imageUrl: imageUrl,
          createdAt: now,
        ),
      ],
    );
    await _savePosts(userId, posts);
    return posts;
  }

  Future<void> _savePosts(int userId, List<CommunityPost> posts) async {
    _ensureInitialized();
    await _preferences!.setString(
      _storageKey(userId),
      jsonEncode(posts.map((post) => post.toJson()).toList()),
    );
  }

  List<CommunityPost> _buildWelcomePosts(String userName) {
    final now = DateTime.now();
    return [
      CommunityPost(
        id: 'welcome-family',
        authorName: '小美',
        authorRole: 'family',
        content: '$userName，今天有記得多喝水嗎？晚上再打電話給您！',
        mood: '❤️',
        createdAt: now.subtract(const Duration(minutes: 35)),
        likeCount: 3,
        comments: [
          CommunityComment(
            id: 'welcome-comment',
            authorName: '阿明',
            authorRole: 'family',
            message: '大家都要記得喝水喔！',
            createdAt: now.subtract(const Duration(minutes: 20)),
          ),
        ],
      ),
      CommunityPost(
        id: 'welcome-neighbor',
        authorName: '王阿姨',
        authorRole: 'elder',
        content: '早上去公園散步，桂花開了，聞起來很香。',
        mood: '🌼',
        createdAt: now.subtract(const Duration(hours: 3)),
        likeCount: 5,
      ),
    ];
  }

  String _storageKey(int userId) => '${_storageKeyPrefix}_$userId';

  void _ensureInitialized() {
    if (_preferences == null) {
      throw StateError('CommunityService 尚未初始化');
    }
  }
}
