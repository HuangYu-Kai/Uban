class CommunityComment {
  final String id;
  final String authorName;
  final String authorRole;
  final String message;
  final String? imagePath;
  final String? imageUrl;
  final String? audioUrl;
  final DateTime createdAt;

  const CommunityComment({
    required this.id,
    required this.authorName,
    this.authorRole = 'elder',
    required this.message,
    this.imagePath,
    this.imageUrl,
    this.audioUrl,
    required this.createdAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final rawImageUrl = json['image_url']?.toString();
    final rawImagePath = json['image_path']?.toString();
    return CommunityComment(
      id: json['id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '朋友',
      authorRole: json['author_role']?.toString() ?? 'elder',
      message: json['message']?.toString() ?? '',
      imagePath: rawImagePath ?? rawImageUrl,
      imageUrl: rawImageUrl ?? rawImagePath,
      audioUrl: json['audio_url']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_name': authorName,
      'author_role': authorRole,
      'message': message,
      'image_path': imagePath,
      'image_url': imageUrl ?? imagePath,
      'audio_url': audioUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class CommunityPost {
  final String id;
  final int? familyId;
  final int? authorId;
  final String authorName;
  final String authorRole;
  final String content;
  final String mood;
  final String? stampType; // 心情印章：walk, tea, sun, flower, food, energy
  final String? imageUrl;
  final String? imagePath;
  final String? audioUrl;
  final String? audioPath;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;
  final List<CommunityComment> comments;

  const CommunityPost({
    required this.id,
    this.familyId,
    this.authorId,
    required this.authorName,
    this.authorRole = 'elder',
    required this.content,
    required this.mood,
    this.stampType,
    this.imageUrl,
    this.imagePath,
    this.audioUrl,
    this.audioPath,
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
    this.comments = const [],
  });

  CommunityPost copyWith({
    int? familyId,
    int? authorId,
    String? authorName,
    String? authorRole,
    String? content,
    String? mood,
    String? stampType,
    String? imageUrl,
    String? imagePath,
    String? audioUrl,
    String? audioPath,
    DateTime? createdAt,
    int? likeCount,
    bool? isLiked,
    List<CommunityComment>? comments,
  }) {
    return CommunityPost(
      id: id,
      familyId: familyId ?? this.familyId,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorRole: authorRole ?? this.authorRole,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      stampType: stampType ?? this.stampType,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePath: imagePath ?? this.imagePath,
      audioUrl: audioUrl ?? this.audioUrl,
      audioPath: audioPath ?? this.audioPath,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      comments: comments ?? this.comments,
    );
  }

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'];
    final rawImageUrl = json['image_url']?.toString();
    final rawImagePath = json['image_path']?.toString();
    return CommunityPost(
      id: json['id']?.toString() ?? '',
      familyId: json['family_id'] is int
          ? json['family_id'] as int
          : int.tryParse(json['family_id']?.toString() ?? ''),
      authorId: json['author_id'] is int
          ? json['author_id'] as int
          : int.tryParse(json['author_id']?.toString() ?? ''),
      authorName: json['author_name']?.toString() ?? '朋友',
      authorRole: json['author_role']?.toString() ?? 'elder',
      content: json['content']?.toString() ?? '',
      mood: json['mood']?.toString() ?? '😊',
      stampType: json['stamp_type']?.toString(),
      imageUrl: rawImageUrl ?? rawImagePath,
      imagePath: rawImagePath ?? rawImageUrl,
      audioUrl: json['audio_url']?.toString(),
      audioPath: json['audio_path']?.toString(),
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
      'family_id': familyId,
      'author_id': authorId,
      'author_name': authorName,
      'author_role': authorRole,
      'content': content,
      'mood': mood,
      'stamp_type': stampType,
      'image_url': imageUrl ?? imagePath,
      'image_path': imagePath ?? imageUrl,
      'audio_url': audioUrl,
      'audio_path': audioPath,
      'created_at': createdAt.toIso8601String(),
      'like_count': likeCount,
      'is_liked': isLiked,
      'comments': comments.map((comment) => comment.toJson()).toList(),
    };
  }
}
