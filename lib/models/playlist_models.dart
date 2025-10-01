// Zeitfenster-Enum: 0-5 für die 6 Zeitfenster
enum TimeSlot {
  earlyMorning, // 3-6
  morning, // 6-11
  noon, // 11-14
  afternoon, // 14-18
  evening, // 18-23
  night, // 23-3
}

// Schedule-Eintrag: Wochentag + Zeitfenster
class WeeklySchedule {
  final int weekday; // 1=Mo, 2=Di, ..., 7=So
  final List<TimeSlot> timeSlots;

  const WeeklySchedule({required this.weekday, required this.timeSlots});

  Map<String, dynamic> toMap() => {
    'weekday': weekday,
    'timeSlots': timeSlots.map((t) => t.index).toList(),
  };

  factory WeeklySchedule.fromMap(Map<String, dynamic> map) => WeeklySchedule(
    weekday: (map['weekday'] as num?)?.toInt() ?? 1,
    timeSlots: ((map['timeSlots'] as List?)?.cast<num>() ?? [])
        .map((i) => TimeSlot.values[i.toInt()])
        .toList(),
  );
}

// Sondertermin: Datumsspanne + Zeitfenster
class SpecialSchedule {
  final int startDate; // Milliseconds since epoch
  final int endDate; // Milliseconds since epoch
  final List<TimeSlot> timeSlots;

  const SpecialSchedule({
    required this.startDate,
    required this.endDate,
    required this.timeSlots,
  });

  Map<String, dynamic> toMap() => {
    'startDate': startDate,
    'endDate': endDate,
    'timeSlots': timeSlots.map((t) => t.index).toList(),
  };

  factory SpecialSchedule.fromMap(Map<String, dynamic> map) => SpecialSchedule(
    startDate: (map['startDate'] as num?)?.toInt() ?? 0,
    endDate: (map['endDate'] as num?)?.toInt() ?? 0,
    timeSlots: ((map['timeSlots'] as List?)?.cast<num>() ?? [])
        .map((i) => TimeSlot.values[i.toInt()])
        .toList(),
  );
}

class Playlist {
  final String id;
  final String avatarId;
  final String name;
  // Allgemeine Zeit (Sekunden) nach Chat-Beginn/Trigger, ab der Inhalte gezeigt werden
  final int showAfterSec;
  // Highlight-Tag für besondere Anlässe (z.B. "Geburtstag", "Weihnachten", "Ostern")
  final String? highlightTag;
  // Cover-Bild URL (9:16 Format)
  final String? coverImageUrl;
  // Wöchentlicher Zeitplan: Wochentag + Zeitfenster
  final List<WeeklySchedule> weeklySchedules;
  // Sondertermine: Datumsspannen + Zeitfenster (überschreiben weekly)
  final List<SpecialSchedule> specialSchedules;
  final int createdAt;
  final int updatedAt;

  const Playlist({
    required this.id,
    required this.avatarId,
    required this.name,
    required this.showAfterSec,
    this.highlightTag,
    this.coverImageUrl,
    this.weeklySchedules = const [],
    this.specialSchedules = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: (map['id'] as String?) ?? '',
      avatarId: (map['avatarId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      showAfterSec: (map['showAfterSec'] as num?)?.toInt() ?? 0,
      highlightTag: map['highlightTag'] as String?,
      coverImageUrl: map['coverImageUrl'] as String?,
      weeklySchedules:
          ((map['weeklySchedules'] as List?)?.cast<Map<String, dynamic>>() ??
                  [])
              .map((m) => WeeklySchedule.fromMap(m))
              .toList(),
      specialSchedules:
          ((map['specialSchedules'] as List?)?.cast<Map<String, dynamic>>() ??
                  [])
              .map((m) => SpecialSchedule.fromMap(m))
              .toList(),
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
      if (highlightTag != null && highlightTag!.isNotEmpty)
        'highlightTag': highlightTag,
      if (coverImageUrl != null && coverImageUrl!.isNotEmpty)
        'coverImageUrl': coverImageUrl,
      'weeklySchedules': weeklySchedules.map((s) => s.toMap()).toList(),
      'specialSchedules': specialSchedules.map((s) => s.toMap()).toList(),
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
