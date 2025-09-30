class SharedMoment {
  final String id;
  final String userId;
  final String avatarId;
  final String mediaId;
  final String decision; // 'shown' | 'rejected'
  final int decidedAt;

  const SharedMoment({
    required this.id,
    required this.userId,
    required this.avatarId,
    required this.mediaId,
    required this.decision,
    required this.decidedAt,
  });

  factory SharedMoment.fromMap(Map<String, dynamic> map) => SharedMoment(
    id: (map['id'] as String?) ?? '',
    userId: (map['userId'] as String?) ?? '',
    avatarId: (map['avatarId'] as String?) ?? '',
    mediaId: (map['mediaId'] as String?) ?? '',
    decision: (map['decision'] as String?) ?? 'shown',
    decidedAt: (map['decidedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'userId': userId,
    'avatarId': avatarId,
    'mediaId': mediaId,
    'decision': decision,
    'decidedAt': decidedAt,
  };
}

