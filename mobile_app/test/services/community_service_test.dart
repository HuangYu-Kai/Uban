import 'dart:io';

import 'package:flutter_application_1/services/community_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ★ 2026-09-22 第五十一輪：讓本套件真的「離線」。
///
/// 這三個測試原本會直接打正式站（每次 15~30 秒逾時，正式站不通時整組失敗）。
/// 用 [HttpOverrides] 讓所有 HTTP 連線當場拋 [SocketException]，
/// `CommunityService` 就會立刻走它的離線分支，測試變成快速且與網路無關。
class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('測試環境刻意離線');
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = _OfflineHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  group('CommunityService', () {
    late CommunityService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = CommunityService();
      await service.initialize();
    });

    // ★ 第五十輪任務 C：`_buildWelcomePosts()`（寫死的「小美」／「王阿姨」兩則
    //   假貼文）已整段移除——離線且本機沒有快取時必須回空清單，不可以再拿
    //   寫死內容墊檔。本測試就是在守這條規則，別改回 `hasLength(2)`。
    test('離線且沒有快取時回空清單，不再產生寫死的假貼文', () async {
      final posts = await service.getPosts(userId: 701, userName: '阿福');

      expect(posts, isEmpty);
    });

    test('可以新增並保存貼文', () async {
      await service.createPost(
        userId: 702,
        userName: '阿福',
        content: '今天去公園散步。',
        mood: '😊',
      );

      final posts = await service.getPosts(userId: 702, userName: '阿福');
      expect(posts.first.authorName, '阿福');
      expect(posts.first.content, '今天去公園散步。');
    });

    test('按讚與留言會正確更新', () async {
      // 沒有假貼文可借用了，要先自己發一則。
      var posts = await service.createPost(
        userId: 703,
        userName: '阿福',
        content: '今天量血壓一切正常。',
        mood: '😊',
      );
      final post = posts.first;

      posts = await service.toggleLike(
        userId: 703,
        userName: '阿福',
        postId: post.id,
      );
      expect(posts.first.isLiked, isTrue);
      expect(posts.first.likeCount, post.likeCount + 1);

      posts = await service.addComment(
        userId: 703,
        userName: '阿福',
        postId: post.id,
        message: '謝謝關心！',
      );
      expect(posts.first.comments.last.message, '謝謝關心！');
    });
  });
}
