import 'package:flutter_application_1/services/community_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CommunityService', () {
    late CommunityService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = CommunityService();
      await service.initialize();
    });

    test('首次開啟會建立歡迎貼文', () async {
      final posts = await service.getPosts(userId: 7, userName: '阿福');

      expect(posts, hasLength(2));
      expect(posts.first.content, contains('阿福'));
    });

    test('可以新增並保存貼文', () async {
      await service.createPost(
        userId: 7,
        userName: '阿福',
        content: '今天去公園散步。',
        mood: '😊',
      );

      final posts = await service.getPosts(userId: 7, userName: '阿福');
      expect(posts.first.authorName, '阿福');
      expect(posts.first.content, '今天去公園散步。');
    });

    test('按讚與留言會正確更新', () async {
      var posts = await service.getPosts(userId: 7, userName: '阿福');
      final post = posts.first;

      posts = await service.toggleLike(
        userId: 7,
        userName: '阿福',
        postId: post.id,
      );
      expect(posts.first.isLiked, isTrue);
      expect(posts.first.likeCount, post.likeCount + 1);

      posts = await service.addComment(
        userId: 7,
        userName: '阿福',
        postId: post.id,
        message: '謝謝關心！',
      );
      expect(posts.first.comments.last.message, '謝謝關心！');
    });
  });
}
