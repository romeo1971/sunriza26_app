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

  factory WeeklySchedule.fromMap(Map<String, dynamic> map) {
    // weekday robust parsen und auf 1..7 begrenzen
    int parsedWeekday;
    final rawWeekday = map['weekday'];
    if (rawWeekday is num) {
      parsedWeekday = rawWeekday.toInt();
    } else if (rawWeekday is String) {
      parsedWeekday = int.tryParse(rawWeekday) ?? 1;
    } else {
      parsedWeekday = 1;
    }
    if (parsedWeekday < 1 || parsedWeekday > 7) parsedWeekday = 1;

    // timeSlots robust parsen und auf gültige Indizes (0..5) filtern
    final rawList = map['timeSlots'];
    final List<TimeSlot> slots = [];
    if (rawList is List) {
      for (final v in rawList) {
        int? idx;
        if (v is num) idx = v.toInt();
        if (v is String) idx = int.tryParse(v);
        if (idx != null && idx >= 0 && idx < TimeSlot.values.length) {
          final ts = TimeSlot.values[idx];
          if (!slots.contains(ts)) slots.add(ts);
        }
      }
    }

    return WeeklySchedule(weekday: parsedWeekday, timeSlots: slots);
  }
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

  factory SpecialSchedule.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    int start = parseInt(map['startDate']);
    int end = parseInt(map['endDate']);
    if (start > 0 && end > 0 && end < start) {
      // vertauschte Werte korrigieren
      final tmp = start;
      start = end;
      end = tmp;
    }

    final rawList = map['timeSlots'];
    final List<TimeSlot> slots = [];
    if (rawList is List) {
      for (final v in rawList) {
        int? idx;
        if (v is num) idx = v.toInt();
        if (v is String) idx = int.tryParse(v);
        if (idx != null && idx >= 0 && idx < TimeSlot.values.length) {
          final ts = TimeSlot.values[idx];
          if (!slots.contains(ts)) slots.add(ts);
        }
      }
    }

    return SpecialSchedule(startDate: start, endDate: end, timeSlots: slots);
  }
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
  // Originaler Dateiname des Cover-Bildes
  final String? coverOriginalFileName;
  // Wöchentlicher Scheduler: Wochentag + Zeitfenster
  final List<WeeklySchedule> weeklySchedules;
  // Sondertermine: Datumsspannen + Zeitfenster (überschreiben weekly)
  final List<SpecialSchedule> specialSchedules;
  final int createdAt;
  final int updatedAt;
  // Anzeige-Modus: 'weekly' oder 'special'
  final String? scheduleMode;
  // Zielgruppenauswahl (schlank, optional)
  final Map<String, dynamic>?
  targeting; // z.B. { gender:'female', matchUserDob:true, activeWithinDays:30 }
  // Priorität bei Kollisionen
  final int? priority;
  // Timeline UI: Split-Verhältnis links/rechts (0..1)
  final double? timelineSplitRatio;

  const Playlist({
    required this.id,
    required this.avatarId,
    required this.name,
    required this.showAfterSec,
    this.highlightTag,
    this.coverImageUrl,
    this.coverOriginalFileName,
    this.weeklySchedules = const [],
    this.specialSchedules = const [],
    required this.createdAt,
    required this.updatedAt,
    this.targeting,
    this.priority,
    this.scheduleMode,
    this.timelineSplitRatio,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double? parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    String? parseString(dynamic v) => v is String ? v : null;

    // weeklySchedules robust lesen
    final List<WeeklySchedule> weekly = [];
    final rawWeekly = map['weeklySchedules'];
    if (rawWeekly is List) {
      for (final e in rawWeekly) {
        if (e is Map<String, dynamic>) {
          try {
            weekly.add(WeeklySchedule.fromMap(e));
          } catch (_) {
            // skip invalid entry
          }
        }
      }
    }

    // specialSchedules robust lesen
    final List<SpecialSchedule> specials = [];
    final rawSpecials = map['specialSchedules'];
    if (rawSpecials is List) {
      for (final e in rawSpecials) {
        if (e is Map<String, dynamic>) {
          try {
            specials.add(SpecialSchedule.fromMap(e));
          } catch (_) {
            // skip invalid entry
          }
        }
      }
    }

    // targeting als Map<String, dynamic> absichern
    Map<String, dynamic>? targeting;
    final rawTargeting = map['targeting'];
    if (rawTargeting is Map) {
      targeting = rawTargeting.map((key, value) => MapEntry('$key', value));
    }

    // scheduleMode nur erlaubte Werte
    final rawMode = parseString(map['scheduleMode']);
    final String? scheduleMode = (rawMode == 'weekly' || rawMode == 'special')
        ? rawMode
        : null;

    return Playlist(
      id: parseString(map['id']) ?? '',
      avatarId: parseString(map['avatarId']) ?? '',
      name: parseString(map['name']) ?? '',
      showAfterSec: parseInt(map['showAfterSec']),
      highlightTag: parseString(map['highlightTag']),
      coverImageUrl: parseString(map['coverImageUrl']),
      coverOriginalFileName: parseString(map['coverOriginalFileName']),
      weeklySchedules: weekly,
      specialSchedules: specials,
      createdAt: parseInt(map['createdAt']),
      updatedAt: parseInt(map['updatedAt']),
      targeting: targeting,
      priority: (map['priority'] is num)
          ? (map['priority'] as num).toInt()
          : (map['priority'] is String
                ? int.tryParse(map['priority'] as String)
                : null),
      scheduleMode: scheduleMode,
      timelineSplitRatio: parseDouble(map['timelineSplitRatio']),
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
      if (coverOriginalFileName != null && coverOriginalFileName!.isNotEmpty)
        'coverOriginalFileName': coverOriginalFileName,
      'weeklySchedules': weeklySchedules.map((s) => s.toMap()).toList(),
      'specialSchedules': specialSchedules.map((s) => s.toMap()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (targeting != null) 'targeting': targeting,
      if (priority != null) 'priority': priority,
      if (scheduleMode != null) 'scheduleMode': scheduleMode,
      if (timelineSplitRatio != null) 'timelineSplitRatio': timelineSplitRatio,
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
