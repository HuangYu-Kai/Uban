import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_post.dart';
import 'api_service.dart';

class CommunityService {
  static const String _storageKeyPrefix = 'elder_community_posts';

  SharedPreferences? _preferences;

  /// 上一次 [getPosts] 是否因為遠端呼叫本身失敗（離線／逾時／伺服器錯誤）
  /// 而退守本機快取——`false` 代表最近一次已成功連上後端，回傳的 posts
  /// （即使是空清單）是後端目前的真實狀態；`true` 代表目前顯示的是舊快取，
  /// 不保證與後端同步。呼叫端可用這個旗標分辨「離線顯示舊資料」與
  /// 「後端已確認目前真的沒有貼文」——兩者 posts 都可能是空清單，但前者
  /// 應該提示「離線中」，後者才是「還沒有人發文」。
  ///
  /// 尚未呼叫過 [getPosts] 時為 `false`（尚無理由懷疑離線）。
  bool lastFetchWasOffline = false;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  /// 取得社群貼文（優先從後端 API 載入最新資料，並更新本地快取；離線時使用本地快取）
  ///
  /// ★ 第五十輪任務 C 修正：舊版只有在 `remoteData.isNotEmpty` 時才存快取
  /// 並回傳——後端合法回傳空陣列（例如長輩只綁一個家人，雙方都還沒發過文）
  /// 時，程式會落回本機快取，快取也沒有時又落回 `_buildWelcomePosts()`
  /// 寫死的兩則假貼文（「小美」／「王阿姨」）。這兩則一旦被寫進
  /// SharedPreferences，之後只要後端回空，假資料就永遠頂替真實狀態顯示
  /// ——這正是使用者回報「長輩只連結一個家人，社群介面卻沒把後端沒連結
  /// 長輩的前端測試文章刪除」的根因：文章根本不在後端，是前端自己在本機
  /// 快取裡造出來的，且那兩則貼文的 `authorRole`（一則 `family`、一則像
  /// 鄰居朋友）混在同一個 feed，也正是「測試文章沒有做到家人與朋友分開」
  /// 的實際樣貌。
  ///
  /// 現在改成「遠端成功即為單一真相」：只要這次呼叫成功回應（不論是否為
  /// 空清單），一律覆蓋本機快取並直接回傳；只有遠端呼叫本身失敗時才退守
  /// 快取，且快取也沒有時回傳空清單，不再用寫死內容墊檔
  /// （`_buildWelcomePosts()` 已整段移除）。
  Future<List<CommunityPost>> getPosts({
    required int userId,
    required String userName,
    int? familyId,
  }) async {
    _ensureInitialized();

    // 1. 優先嘗試從遠端 API 獲取——成功即單一真相，空清單也要覆蓋快取。
    try {
      final remoteData = await ApiService.getCommunityPosts(
        familyId: familyId,
        userId: userId,
      );

      final posts = remoteData
          .whereType<Map>()
          .map((post) => CommunityPost.fromJson(
                post.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _savePosts(userId, posts);
      lastFetchWasOffline = false;
      return posts;
    } catch (e) {
      debugPrint('⚠️ [CommunityService] Remote fetch failed, fallback to local: $e');
    }

    // 2. 遠端呼叫本身失敗（離線／逾時／伺服器錯誤）才退守本地快取。
    lastFetchWasOffline = true;
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

    // 3. 離線且本機也沒有任何快取：回傳空清單，不再提供寫死的假預設資料。
    return [];
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

  String _storageKey(int userId) => '${_storageKeyPrefix}_$userId';

  void _ensureInitialized() {
    if (_preferences == null) {
      throw StateError('CommunityService 尚未初始化');
    }
  }
}
