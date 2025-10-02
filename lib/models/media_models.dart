enum AvatarMediaType { image, video, audio }

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
    final typeStr = (map['type'] as String?) ?? 'image';
    final AvatarMediaType mediaType;
    switch (typeStr) {
      case 'video':
        mediaType = AvatarMediaType.video;
        break;
      case 'audio':
        mediaType = AvatarMediaType.audio;
        break;
      default:
        mediaType = AvatarMediaType.image;
    }

    return AvatarMedia(
      id: (map['id'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      type: mediaType,
      url: (map['url'] as String?) ?? '',
      thumbUrl: map['thumbUrl'] as String?,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble(),
      tags: (map['tags'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toMap() {
    String typeStr;
    switch (type) {
      case AvatarMediaType.video:
        typeStr = 'video';
        break;
      case AvatarMediaType.audio:
        typeStr = 'audio';
        break;
      case AvatarMediaType.image:
        typeStr = 'image';
    }

    return {
      'id': id,
      'avatarId': avatarId,
      'type': typeStr,
      'url': url,
      'thumbUrl': thumbUrl,
      'createdAt': createdAt,
      'durationMs': durationMs,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (tags != null) 'tags': tags,
    };
  }
}
