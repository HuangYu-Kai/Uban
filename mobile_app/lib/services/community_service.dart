import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_post.dart';

class CommunityService {
  static const String _storageKeyPrefix = 'elder_community_posts';

  SharedPreferences? _preferences;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  Future<List<CommunityPost>> getPosts({
    required int userId,
    required String userName,
  }) async {
    _ensureInitialized();
    final storageKey = _storageKey(userId);
    final storedValue = _preferences!.getString(storageKey);

    if (storedValue == null || storedValue.isEmpty) {
      final seededPosts = _buildWelcomePosts(userName);
      await _savePosts(userId, seededPosts);
      return seededPosts;
    }

    try {
      final decoded = jsonDecode(storedValue);
      if (decoded is! List) return [];
      final posts = decoded
          .whereType<Map>()
          .map((post) => CommunityPost.fromJson(
                post.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList();
      posts
          .sort((first, second) => second.createdAt.compareTo(first.createdAt));
      return posts;
    } catch (_) {
      return [];
    }
  }

  Future<List<CommunityPost>> createPost({
    required int userId,
    required String userName,
    required String content,
    required String mood,
  }) async {
    final posts = await getPosts(userId: userId, userName: userName);
    final now = DateTime.now();
    posts.insert(
      0,
      CommunityPost(
        id: 'post-${now.microsecondsSinceEpoch}',
        authorName: userName,
        content: content.trim(),
        mood: mood,
        createdAt: now,
      ),
    );
    await _savePosts(userId, posts);
    return posts;
  }

  Future<List<CommunityPost>> toggleLike({
    required int userId,
    required String userName,
    required String postId,
  }) async {
    final posts = await getPosts(userId: userId, userName: userName);
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

  Future<List<CommunityPost>> addComment({
    required int userId,
    required String userName,
    required String postId,
    required String message,
    String? imagePath,
  }) async {
    final posts = await getPosts(userId: userId, userName: userName);
    final postIndex = posts.indexWhere((post) => post.id == postId);
    if (postIndex == -1) return posts;

    final post = posts[postIndex];
    final now = DateTime.now();
    posts[postIndex] = post.copyWith(
      comments: [
        ...post.comments,
        CommunityComment(
          id: 'comment-${now.microsecondsSinceEpoch}',
          authorName: userName,
          message: message.trim(),
          imagePath: imagePath,
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
        content: '$userName，今天有記得多喝水嗎？晚上再打電話給您！',
        mood: '❤️',
        createdAt: now.subtract(const Duration(minutes: 35)),
        likeCount: 3,
        comments: [
          CommunityComment(
            id: 'welcome-comment',
            authorName: '阿明',
            message: '大家都要記得喝水喔！',
            createdAt: now.subtract(const Duration(minutes: 20)),
          ),
        ],
      ),
      CommunityPost(
        id: 'welcome-neighbor',
        authorName: '王阿姨',
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
