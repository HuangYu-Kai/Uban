class CommunityComment {
  final String id;
  final String authorName;
  final String message;
  final String? imagePath;
  final DateTime createdAt;

  const CommunityComment({
    required this.id,
    required this.authorName,
    required this.message,
    this.imagePath,
    required this.createdAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: json['id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '朋友',
      message: json['message']?.toString() ?? '',
      imagePath: json['image_path']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_name': authorName,
      'message': message,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class CommunityPost {
  final String id;
  final String authorName;
  final String content;
  final String mood;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;
  final List<CommunityComment> comments;

  const CommunityPost({
    required this.id,
    required this.authorName,
    required this.content,
    required this.mood,
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
    this.comments = const [],
  });

  CommunityPost copyWith({
    int? likeCount,
    bool? isLiked,
    List<CommunityComment>? comments,
  }) {
    return CommunityPost(
      id: id,
      authorName: authorName,
      content: content,
      mood: mood,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      comments: comments ?? this.comments,
    );
  }

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'];
    return CommunityPost(
      id: json['id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '朋友',
      content: json['content']?.toString() ?? '',
      mood: json['mood']?.toString() ?? '😊',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      likeCount: json['like_count'] is int
          ? json['like_count'] as int
          : int.tryParse(json['like_count']?.toString() ?? '') ?? 0,
      isLiked: json['is_liked'] == true,
      comments: rawComments is List
          ? rawComments
              .whereType<Map>()
              .map((comment) => CommunityComment.fromJson(
                    comment.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  ))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_name': authorName,
      'content': content,
      'mood': mood,
      'created_at': createdAt.toIso8601String(),
      'like_count': likeCount,
      'is_liked': isLiked,
      'comments': comments.map((comment) => comment.toJson()).toList(),
    };
  }
}
