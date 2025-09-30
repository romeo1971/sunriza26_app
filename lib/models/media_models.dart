enum AvatarMediaType { image, video }

class AvatarMedia {
  final String id;
  final String avatarId;
  final AvatarMediaType type;
  final String url;
  final String? thumbUrl;
  final int createdAt;
  final int? durationMs;
  final double?
  aspectRatio; // width / height (z.B. 9/16 für Portrait, 16/9 für Landscape)
  final List<String>? tags; // KI-generierte Tags für Bilderkennung

  const AvatarMedia({
    required this.id,
    required this.avatarId,
    required this.type,
    required this.url,
    this.thumbUrl,
    required this.createdAt,
    this.durationMs,
    this.aspectRatio,
    this.tags,
  });

  bool get isPortrait => aspectRatio != null && aspectRatio! < 1.0;
  bool get isLandscape => aspectRatio != null && aspectRatio! > 1.0;

  factory AvatarMedia.fromMap(Map<String, dynamic> map) {
    return AvatarMedia(
      id: (map['id'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      type: ((map['type'] as String?) ?? 'image') == 'video'
          ? AvatarMediaType.video
          : AvatarMediaType.image,
      url: (map['url'] as String?) ?? '',
      thumbUrl: map['thumbUrl'] as String?,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble(),
      tags: (map['tags'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'avatarId': avatarId,
    'type': type == AvatarMediaType.video ? 'video' : 'image',
    'url': url,
    'thumbUrl': thumbUrl,
    'createdAt': createdAt,
    'durationMs': durationMs,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (tags != null) 'tags': tags,
  };
}
