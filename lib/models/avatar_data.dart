class AvatarData {
  final String id;
  final String userId;
  final String firstName;
  final String? nickname;
  final String? lastName;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final int? calculatedAge;
  final String? avatarImageUrl;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<String> textFileUrls;
  final List<String> writtenTexts;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  AvatarData({
    required this.id,
    required this.userId,
    required this.firstName,
    this.nickname,
    this.lastName,
    this.birthDate,
    this.deathDate,
    this.calculatedAge,
    this.avatarImageUrl,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.textFileUrls = const [],
    this.writtenTexts = const [],
    this.lastMessage,
    this.lastMessageTime,
    required this.createdAt,
    required this.updatedAt,
  });

  // Factory constructor für Firestore
  factory AvatarData.fromMap(Map<String, dynamic> map) {
    return AvatarData(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      firstName: map['firstName'] ?? '',
      nickname: map['nickname'],
      lastName: map['lastName'],
      birthDate: map['birthDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['birthDate'])
          : null,
      deathDate: map['deathDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['deathDate'])
          : null,
      calculatedAge: map['calculatedAge'],
      avatarImageUrl: map['avatarImageUrl'],
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      videoUrls: List<String>.from(map['videoUrls'] ?? []),
      textFileUrls: List<String>.from(map['textFileUrls'] ?? []),
      writtenTexts: List<String>.from(map['writtenTexts'] ?? []),
      lastMessage: map['lastMessage'],
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'])
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
    );
  }

  // ToMap für Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'firstName': firstName,
      'nickname': nickname,
      'lastName': lastName,
      'birthDate': birthDate?.millisecondsSinceEpoch,
      'deathDate': deathDate?.millisecondsSinceEpoch,
      'calculatedAge': calculatedAge,
      'avatarImageUrl': avatarImageUrl,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'textFileUrls': textFileUrls,
      'writtenTexts': writtenTexts,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  // Copy with method
  AvatarData copyWith({
    String? id,
    String? userId,
    String? firstName,
    String? nickname,
    String? lastName,
    DateTime? birthDate,
    DateTime? deathDate,
    int? calculatedAge,
    String? avatarImageUrl,
    List<String>? imageUrls,
    List<String>? videoUrls,
    List<String>? textFileUrls,
    List<String>? writtenTexts,
    String? lastMessage,
    DateTime? lastMessageTime,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AvatarData(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      nickname: nickname ?? this.nickname,
      lastName: lastName ?? this.lastName,
      birthDate: birthDate ?? this.birthDate,
      deathDate: deathDate ?? this.deathDate,
      calculatedAge: calculatedAge ?? this.calculatedAge,
      avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      textFileUrls: textFileUrls ?? this.textFileUrls,
      writtenTexts: writtenTexts ?? this.writtenTexts,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Display name
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) {
      return nickname!;
    }
    return firstName;
  }

  // Full name
  String get fullName {
    final parts = <String>[];
    if (firstName.isNotEmpty) parts.add(firstName);
    if (lastName != null && lastName!.isNotEmpty) parts.add(lastName!);
    return parts.join(' ');
  }

  // Age calculation
  int? get age {
    if (birthDate == null) return null;

    final endDate = deathDate ?? DateTime.now();
    final age = endDate.year - birthDate!.year;
    final monthDiff = endDate.month - birthDate!.month;

    if (monthDiff < 0 || (monthDiff == 0 && endDate.day < birthDate!.day)) {
      return age - 1;
    }
    return age;
  }

  // Check if avatar has content
  bool get hasContent {
    return imageUrls.isNotEmpty ||
        videoUrls.isNotEmpty ||
        textFileUrls.isNotEmpty ||
        writtenTexts.isNotEmpty;
  }

  // Get total content count
  int get contentCount {
    return imageUrls.length +
        videoUrls.length +
        textFileUrls.length +
        writtenTexts.length;
  }
}
