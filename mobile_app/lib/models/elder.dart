/// 👴👵 長輩資料模型
class Elder {
  final int id;
  final String name;
  final String? gender;
  final int? age;
  final String? avatarUrl;
  final String? phone;
  final String? location;
  final String? appellation; // 稱呼方式
  final DateTime? pairedAt; // 配對時間
  
  Elder({
    required this.id,
    required this.name,
    this.gender,
    this.age,
    this.avatarUrl,
    this.phone,
    this.location,
    this.appellation,
    this.pairedAt,
  });
  
  /// 從 API 回傳的 JSON 創建 Elder 物件
  factory Elder.fromJson(Map<String, dynamic> json) {
    return Elder(
      id: json['id'] ?? json['user_id'] ?? 0,
      name: json['name'] ?? json['user_name'] ?? '長輩',
      gender: json['gender'],
      age: json['age'],
      avatarUrl: json['avatar_url'],
      phone: json['phone'],
      location: json['location'],
      appellation: json['appellation'],
      pairedAt: json['paired_at'] != null 
        ? DateTime.tryParse(json['paired_at']) 
        : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gender': gender,
      'age': age,
      'avatar_url': avatarUrl,
      'phone': phone,
      'location': location,
      'appellation': appellation,
      'paired_at': pairedAt?.toIso8601String(),
    };
  }
  
  /// 顯示名稱（優先使用稱呼，否則使用名字）
  String get displayName => appellation ?? name;
  
  /// 性別 Emoji
  String get genderEmoji {
    if (gender == null) return '👤';
    if (gender!.contains('女') || gender!.toLowerCase().contains('f')) return '👵';
    if (gender!.contains('男') || gender!.toLowerCase().contains('m')) return '👴';
    return '👤';
  }
  
  Elder copyWith({
    int? id,
    String? name,
    String? gender,
    int? age,
    String? avatarUrl,
    String? phone,
    String? location,
    String? appellation,
    DateTime? pairedAt,
  }) {
    return Elder(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      appellation: appellation ?? this.appellation,
      pairedAt: pairedAt ?? this.pairedAt,
    );
  }
}
