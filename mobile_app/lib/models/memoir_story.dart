import 'dart:convert';

/// 長輩人生故事膠囊資料模型
class MemoirStory {
  final String id;
  final String elderId;
  final String title;
  final String tag; // 例如：經典回憶、美食記憶、溫馨寄語、奮鬥歲月
  final String preview;
  final String fullStory;
  final String promptQuestion; // 當初小豬或子女引導的提問
  final String? audioAssetOrUrl; // 口述原聲音檔路徑或 URL
  final String? imageAssetOrUrl; // 懷舊老照片或相關插圖
  final List<MemoirFamilyNote> familyNotes; // 子女給長輩的悄悄話／回饋筆記
  final DateTime recordedDate;
  final bool isFavorite;

  const MemoirStory({
    required this.id,
    required this.elderId,
    required this.title,
    required this.tag,
    required this.preview,
    required this.fullStory,
    required this.promptQuestion,
    this.audioAssetOrUrl,
    this.imageAssetOrUrl,
    this.familyNotes = const [],
    required this.recordedDate,
    this.isFavorite = false,
  });

  MemoirStory copyWith({
    String? id,
    String? elderId,
    String? title,
    String? tag,
    String? preview,
    String? fullStory,
    String? promptQuestion,
    String? audioAssetOrUrl,
    String? imageAssetOrUrl,
    List<MemoirFamilyNote>? familyNotes,
    DateTime? recordedDate,
    bool? isFavorite,
  }) {
    return MemoirStory(
      id: id ?? this.id,
      elderId: elderId ?? this.elderId,
      title: title ?? this.title,
      tag: tag ?? this.tag,
      preview: preview ?? this.preview,
      fullStory: fullStory ?? this.fullStory,
      promptQuestion: promptQuestion ?? this.promptQuestion,
      audioAssetOrUrl: audioAssetOrUrl ?? this.audioAssetOrUrl,
      imageAssetOrUrl: imageAssetOrUrl ?? this.imageAssetOrUrl,
      familyNotes: familyNotes ?? this.familyNotes,
      recordedDate: recordedDate ?? this.recordedDate,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  factory MemoirStory.fromJson(Map<String, dynamic> json) {
    var rawNotes = json['family_notes'] ?? json['familyNotes'];
    List<MemoirFamilyNote> parsedNotes = [];
    if (rawNotes is List) {
      parsedNotes = rawNotes
          .map((item) => item is Map<String, dynamic>
              ? MemoirFamilyNote.fromJson(item)
              : MemoirFamilyNote.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } else if (rawNotes is String && rawNotes.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNotes);
        if (decoded is List) {
          parsedNotes = decoded
              .map((item) => MemoirFamilyNote.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      } catch (_) {}
    }

    return MemoirStory(
      id: json['id']?.toString() ?? '',
      elderId: json['elder_id']?.toString() ?? json['elderId']?.toString() ?? '',
      title: json['title']?.toString() ?? '人生回憶故事',
      tag: json['tag']?.toString() ?? '經典回憶',
      preview: json['preview']?.toString() ?? '',
      fullStory: json['full_story']?.toString() ?? json['fullStory']?.toString() ?? '',
      promptQuestion: json['prompt_question']?.toString() ?? json['promptQuestion']?.toString() ?? '',
      audioAssetOrUrl: json['audio_asset_or_url']?.toString() ?? json['audioAssetOrUrl']?.toString(),
      imageAssetOrUrl: json['image_asset_or_url']?.toString() ?? json['imageAssetOrUrl']?.toString(),
      familyNotes: parsedNotes,
      recordedDate: DateTime.tryParse(json['recorded_date']?.toString() ?? json['recordedDate']?.toString() ?? '') ??
          DateTime.now(),
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1 || json['isFavorite'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'elder_id': elderId,
      'title': title,
      'tag': tag,
      'preview': preview,
      'full_story': fullStory,
      'prompt_question': promptQuestion,
      'audio_asset_or_url': audioAssetOrUrl,
      'image_asset_or_url': imageAssetOrUrl,
      'family_notes': familyNotes.map((n) => n.toJson()).toList(),
      'recorded_date': recordedDate.toIso8601String(),
      'is_favorite': isFavorite,
    };
  }
}

/// 子女在故事膠囊中留下的悄悄話筆記
class MemoirFamilyNote {
  final String author;
  final String relation;
  final String note;
  final DateTime createdAt;

  const MemoirFamilyNote({
    required this.author,
    required this.relation,
    required this.note,
    required this.createdAt,
  });

  factory MemoirFamilyNote.fromJson(Map<String, dynamic> json) {
    return MemoirFamilyNote(
      author: json['author']?.toString() ?? '家人',
      relation: json['relation']?.toString() ?? '家屬',
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'author': author,
      'relation': relation,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 子女委託小豬向長輩提問的委託紀錄
class MemoirPromptDelegation {
  final String id;
  final String elderId;
  final String question;
  final String category; // 感官美食、青春歲月、家庭浪漫、人生錦囊
  final String requestedBy;
  final DateTime createdAt;
  final bool isAnswered;

  const MemoirPromptDelegation({
    required this.id,
    required this.elderId,
    required this.question,
    required this.category,
    required this.requestedBy,
    required this.createdAt,
    this.isAnswered = false,
  });

  factory MemoirPromptDelegation.fromJson(Map<String, dynamic> json) {
    return MemoirPromptDelegation(
      id: json['id']?.toString() ?? '',
      elderId: json['elder_id']?.toString() ?? json['elderId']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      category: json['category']?.toString() ?? '經典回憶',
      requestedBy: json['requested_by']?.toString() ?? json['requestedBy']?.toString() ?? '家人',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isAnswered: json['is_answered'] == true || json['is_answered'] == 1 || json['isAnswered'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'elder_id': elderId,
      'question': question,
      'category': category,
      'requested_by': requestedBy,
      'created_at': createdAt.toIso8601String(),
      'is_answered': isAnswered,
    };
  }
}
