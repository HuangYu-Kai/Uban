import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/community_post.dart';

void main() {
  Map<String, dynamic> base(Map<String, dynamic> extra) => {
        'id': '1',
        'content': 'hi',
        ...extra,
      };

  test('liked_by 缺少時為空清單', () {
    expect(CommunityPost.fromJson(base({})).likedBy, isEmpty);
  });

  test('liked_by 只保留非空字串', () {
    final post = CommunityPost.fromJson(base({
      'liked_by': ['小明', '', 3, null, '阿嬤'],
    }));
    expect(post.likedBy, ['小明', '阿嬤']);
  });

  test('liked_by 非 List 時為空清單', () {
    expect(CommunityPost.fromJson(base({'liked_by': 'x'})).likedBy, isEmpty);
  });

  test('toJson / copyWith 帶出 liked_by', () {
    final post = CommunityPost.fromJson(base({'liked_by': ['A']}));
    expect(post.toJson()['liked_by'], ['A']);
    expect(post.copyWith(likedBy: ['A', 'B']).likedBy, ['A', 'B']);
  });
}
