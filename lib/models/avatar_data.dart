import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String? city;
  final String? postalCode;
  final String? country;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<String> textFileUrls;
  final List<String> audioUrls;
  final List<String> writtenTexts;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? training;
  final String? greetingText;
  final String? role;
  final bool? isPublic; // Öffentlich sichtbar im Explore-Feed
  final bool? firstNamePublic; // Vorname öffentlich
  final bool? nicknamePublic; // Nickname öffentlich
  final bool? lastNamePublic; // Nachname öffentlich
  final Map<String, dynamic>? dynamics; // Dynamics (idle.mp4, chunks, etc.)
  final Map<String, dynamic>? liveAvatar; // BitHuman Live Avatar (agentId, etc.)
  final String? slug; // Öffentliche Avatar-URL (schreibgeschützt nach Vergabe)

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
    this.city,
    this.postalCode,
    this.country,
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.textFileUrls = const [],
    this.audioUrls = const [],
    this.writtenTexts = const [],
    this.lastMessage,
    this.lastMessageTime,
    required this.createdAt,
    required this.updatedAt,
    this.training,
    this.greetingText,
    this.role,
    this.isPublic,
    this.firstNamePublic,
    this.nicknamePublic,
    this.lastNamePublic,
    this.dynamics,
    this.liveAvatar,
    this.slug,
  });

  // Factory constructor für Firestore
  static DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory AvatarData.fromMap(Map<String, dynamic> map) {
    return AvatarData(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      firstName: map['firstName'] ?? '',
      nickname: map['nickname'],
      lastName: map['lastName'],
      birthDate: map['birthDate'] != null ? _toDate(map['birthDate']) : null,
      deathDate: map['deathDate'] != null ? _toDate(map['deathDate']) : null,
      calculatedAge: map['calculatedAge'],
      avatarImageUrl: map['avatarImageUrl'],
      city: map['city'],
      postalCode: map['postalCode'],
      country: map['country'],
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      videoUrls: List<String>.from(map['videoUrls'] ?? []),
      textFileUrls: List<String>.from(map['textFileUrls'] ?? []),
      audioUrls: List<String>.from(map['audioUrls'] ?? []),
      writtenTexts: List<String>.from(map['writtenTexts'] ?? []),
      lastMessage: map['lastMessage'],
      lastMessageTime: map['lastMessageTime'] != null
          ? _toDate(map['lastMessageTime'])
          : null,
      createdAt: _toDate(map['createdAt']),
      updatedAt: _toDate(map['updatedAt']),
      training: map['training'],
      greetingText: map['greetingText'],
      role: map['role'],
      isPublic: map['isPublic'],
      firstNamePublic: map['firstNamePublic'],
      nicknamePublic: map['nicknamePublic'],
      lastNamePublic: map['lastNamePublic'],
      dynamics: map['dynamics'],
      liveAvatar: map['liveAvatar'],
      slug: map['slug'],
    );
  }

  // ToMap für Firestore
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'userId': userId,
      'firstName': firstName,
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'textFileUrls': textFileUrls,
      'audioUrls': audioUrls,
      'writtenTexts': writtenTexts,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };

    if (nickname != null) map['nickname'] = nickname;
    if (lastName != null) map['lastName'] = lastName;
    if (birthDate != null) {
      map['birthDate'] = birthDate!.millisecondsSinceEpoch;
    }
    if (deathDate != null) {
      map['deathDate'] = deathDate!.millisecondsSinceEpoch;
    }
    if (calculatedAge != null) map['calculatedAge'] = calculatedAge;
    if (avatarImageUrl != null) map['avatarImageUrl'] = avatarImageUrl;
    if (lastMessage != null) map['lastMessage'] = lastMessage;
    if (lastMessageTime != null) {
      map['lastMessageTime'] = lastMessageTime!.millisecondsSinceEpoch;
    }
    if (training != null) map['training'] = training;
    if (greetingText != null && greetingText!.isNotEmpty) {
      map['greetingText'] = greetingText;
    }
    if (city != null && city!.isNotEmpty) map['city'] = city;
    if (postalCode != null && postalCode!.isNotEmpty) {
      map['postalCode'] = postalCode;
    }
    if (country != null && country!.isNotEmpty) map['country'] = country;
    if (role != null && role!.isNotEmpty) map['role'] = role;
    if (isPublic != null) map['isPublic'] = isPublic;
    if (firstNamePublic != null) map['firstNamePublic'] = firstNamePublic;
    if (nicknamePublic != null) map['nicknamePublic'] = nicknamePublic;
    if (lastNamePublic != null) map['lastNamePublic'] = lastNamePublic;
    if (dynamics != null) map['dynamics'] = dynamics;
    if (liveAvatar != null) map['liveAvatar'] = liveAvatar;
    if (slug != null && slug!.isNotEmpty) map['slug'] = slug;

    return map;
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
    String? city,
    String? postalCode,
    String? country,
    List<String>? imageUrls,
    List<String>? videoUrls,
    List<String>? textFileUrls,
    List<String>? writtenTexts,
    List<String>? audioUrls,
    String? lastMessage,
    DateTime? lastMessageTime,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? training,
    String? greetingText,
    String? role,
    bool? isPublic,
    bool? firstNamePublic,
    bool? nicknamePublic,
    bool? lastNamePublic,
    Map<String, dynamic>? dynamics,
    Map<String, dynamic>? liveAvatar,
    bool clearAvatarImageUrl = false,
    String? slug,
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
      avatarImageUrl: clearAvatarImageUrl
          ? null
          : (avatarImageUrl ?? this.avatarImageUrl),
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrls: videoUrls ?? this.videoUrls,
      textFileUrls: textFileUrls ?? this.textFileUrls,
      writtenTexts: writtenTexts ?? this.writtenTexts,
      audioUrls: audioUrls ?? this.audioUrls,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      training: training ?? this.training,
      greetingText: greetingText ?? this.greetingText,
      role: role ?? this.role,
      isPublic: isPublic ?? this.isPublic,
      firstNamePublic: firstNamePublic ?? this.firstNamePublic,
      nicknamePublic: nicknamePublic ?? this.nicknamePublic,
      lastNamePublic: lastNamePublic ?? this.lastNamePublic,
      dynamics: dynamics ?? this.dynamics,
      liveAvatar: liveAvatar ?? this.liveAvatar,
      slug: slug ?? this.slug,
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

  String get searchableRegion {
    final List<String> parts = [];
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (postalCode != null && postalCode!.isNotEmpty) parts.add(postalCode!);
    if (country != null && country!.isNotEmpty) parts.add(country!);
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
        audioUrls.isNotEmpty ||
        writtenTexts.isNotEmpty;
  }

  // Get total content count
  int get contentCount {
    return imageUrls.length +
        videoUrls.length +
        textFileUrls.length +
        audioUrls.length +
        writtenTexts.length;
  }
}
