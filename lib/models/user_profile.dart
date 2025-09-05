class UserProfile {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isOnboarded;
  final int createdAt;
  final int updatedAt;

  UserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.isOnboarded = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String,
      email: map['email'] as String?,
      displayName: map['displayName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      isOnboarded: (map['isOnboarded'] as bool?) ?? false,
      createdAt: (map['createdAt'] as num).toInt(),
      updatedAt: (map['updatedAt'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'isOnboarded': isOnboarded,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    bool? isOnboarded,
    int? createdAt,
    int? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
