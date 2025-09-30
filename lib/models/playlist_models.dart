class Playlist {
  final String id;
  final String avatarId;
  final String name;
  // Allgemeine Zeit (Sekunden) nach Chat-Beginn/Trigger, ab der Inhalte gezeigt werden
  final int showAfterSec;
  // Wiederholungsplan: none | daily | weekly | monthly
  final String repeat;
  // Für weekly: 1=Montag .. 7=Sonntag
  final int? weeklyDay;
  // Für monthly: 1..31
  final int? monthlyDay;
  // Spezielle Datumsangaben YYYY-MM-DD
  final List<String> specialDates;
  final int createdAt;
  final int updatedAt;

  const Playlist({
    required this.id,
    required this.avatarId,
    required this.name,
    required this.showAfterSec,
    this.repeat = 'none',
    this.weeklyDay,
    this.monthlyDay,
    this.specialDates = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: (map['id'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      showAfterSec: (map['showAfterSec'] as num?)?.toInt() ?? 0,
      repeat: (map['repeat'] as String?) ?? 'none',
      weeklyDay: (map['weeklyDay'] as num?)?.toInt(),
      monthlyDay: (map['monthlyDay'] as num?)?.toInt(),
      specialDates:
          ((map['specialDates'] as List?)?.cast<String>()) ?? const [],
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'avatarId': avatarId,
      'name': name,
      'showAfterSec': showAfterSec,
      'repeat': repeat,
      if (weeklyDay != null) 'weeklyDay': weeklyDay,
      if (monthlyDay != null) 'monthlyDay': monthlyDay,
      'specialDates': specialDates,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class PlaylistItem {
  final String id;
  final String playlistId;
  final String avatarId;
  final String mediaId;
  final int order;

  const PlaylistItem({
    required this.id,
    required this.playlistId,
    required this.avatarId,
    required this.mediaId,
    required this.order,
  });

  factory PlaylistItem.fromMap(Map<String, dynamic> map) => PlaylistItem(
    id: (map['id'] as String?) ?? '',
    playlistId: (map['playlistId'] as String?) ?? '',
    avatarId: (map['avatarId'] as String?) ?? '',
    mediaId: (map['mediaId'] as String?) ?? '',
    order: (map['order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'playlistId': playlistId,
    'avatarId': avatarId,
    'mediaId': mediaId,
    'order': order,
  };
}
