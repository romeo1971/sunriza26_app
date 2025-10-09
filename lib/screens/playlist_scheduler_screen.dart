import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import '../models/playlist_models.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_dropdown.dart';
import 'playlist_timeline_screen.dart';
import 'package:intl/intl.dart';
// removed provider/language_service dependency from this screen

class PlaylistSchedulerScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistSchedulerScreen({super.key, required this.playlist});

  @override
  State<PlaylistSchedulerScreen> createState() =>
      _PlaylistSchedulerScreenState();
}

class _PlaylistSchedulerScreenState extends State<PlaylistSchedulerScreen> {
  late TextEditingController _name;
  late TextEditingController _highlightTag;
  final _svc = PlaylistService();
  final _mediaSvc = MediaService();
  List<PlaylistItem> _items = [];
  Map<String, AvatarMedia> _mediaMap = {};
  bool _saving = false; // verhindert doppelte Saves/Races beim Navigieren

  // Cover Image State (nur Anzeige)
  String? _coverImageUrl;
  String? _coverOriginalFileName;

  // Dirty State (für Save-Button Anzeige)
  bool _isDirty = false;

  // Weekly Schedule State: Map<Weekday, Set<TimeSlot>>
  final Map<int, Set<TimeSlot>> _weeklySchedule = {};

  // Special Schedules State
  List<SpecialSchedule> _specialSchedules = [];

  // UI State: aktuell gewählter Wochentag für Zeitfenster-Auswahl
  int? _selectedWeekday;
  // UI State: Sondertermine – ausgewählter Wochentag
  int? _selectedSpecialWeekday;

  // UI State: Wöchentlicher Scheduler aufgeklappt?
  bool _weeklyScheduleExpanded = true;

  // UI State: Ist "Eigener Tag" ausgewählt?
  bool _isCustomTag = false;

  // UI State: Playlist-Typ (weekly oder special)
  String _playlistType = 'weekly'; // 'weekly' oder 'special'

  // UI State: Sondertermin Erstellung
  String _specialAnlass = '';
  DateTime? _specialStartDate;
  DateTime? _specialEndDate;
  final Map<DateTime, Set<TimeSlot>> _specialDaySlots = {};

  // Normalisiert Sondertermine auf "pro Kalendertag ein Eintrag",
  // dedupliziert TimeSlots und sortiert sie stabil (0..5).
  List<SpecialSchedule> _normalizeSpecials(List<SpecialSchedule> input) {
    if (input.isEmpty) return const <SpecialSchedule>[];
    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    final Map<DateTime, Set<TimeSlot>> dayToSlots = {};
    for (final sp in input) {
      DateTime s;
      DateTime e;
      try {
        s = DateTime.fromMillisecondsSinceEpoch(sp.startDate);
        e = DateTime.fromMillisecondsSinceEpoch(sp.endDate);
      } catch (_) {
        continue;
      }
      if (e.isBefore(s)) {
        final tmp = s;
        s = e;
        e = tmp;
      }
      DateTime c = DateTime(s.year, s.month, s.day);
      final last = DateTime(e.year, e.month, e.day);
      while (!c.isAfter(last)) {
        final key = DateTime(c.year, c.month, c.day);
        dayToSlots.putIfAbsent(key, () => <TimeSlot>{});
        dayToSlots[key]!.addAll(sp.timeSlots);
        c = c.add(const Duration(days: 1));
      }
    }
    final out = <SpecialSchedule>[];
    final keys = dayToSlots.keys.toList()..sort();
    for (final day in keys) {
      final slots = dayToSlots[day]!.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      out.add(
        SpecialSchedule(
          startDate: DateTime(
            day.year,
            day.month,
            day.day,
          ).millisecondsSinceEpoch,
          endDate: endOfDay(day).millisecondsSinceEpoch,
          timeSlots: slots,
        ),
      );
    }
    return out;
  }

  // Berechnet Ostersonntag für ein bestimmtes Jahr (Gauss-Algorithmus)
  static DateTime _calculateEaster(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  Widget _buildTargetingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Zielgruppe (optional)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Alle'),
              selected: _tgGender == 'any',
              onSelected: (_) => setState(() {
                _tgGender = 'any';
                _isDirty = true;
              }),
            ),
            ChoiceChip(
              label: const Text('Männlich'),
              selected: _tgGender == 'male',
              onSelected: (_) => setState(() {
                _tgGender = 'male';
                _isDirty = true;
              }),
            ),
            ChoiceChip(
              label: const Text('Weiblich'),
              selected: _tgGender == 'female',
              onSelected: (_) => setState(() {
                _tgGender = 'female';
                _isDirty = true;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Geburtstag des Users (DOB) berücksichtigen'),
          value: _tgMatchDob,
          onChanged: (v) => setState(() {
            _tgMatchDob = v;
            _isDirty = true;
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                label: 'Aktiv in X Tagen',
                controller: _tgActiveDays,
                keyboardType: TextInputType.number,
                hintText: 'z. B. 30',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                label: 'Neu registriert in X Tagen',
                controller: _tgNewUserDays,
                keyboardType: TextInputType.number,
                hintText: 'z. B. 7',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomTextField(
          label: 'Priorität (höher gewinnt)',
          controller: _tgPriority,
          keyboardType: TextInputType.number,
          hintText: 'z. B. 10',
        ),
      ],
    );
  }

  // Berechnet Muttertag für ein Land und Jahr
  static DateTime _calculateMothersDay(int year, String country) {
    switch (country.toLowerCase()) {
      case 'de':
      case 'at':
      case 'ch':
      case 'us':
      case 'ca':
      case 'au':
        // 2. Sonntag im Mai
        int sundayCount = 0;
        for (int day = 1; day <= 31; day++) {
          final date = DateTime(year, 5, day);
          if (date.weekday == DateTime.sunday) {
            sundayCount++;
            if (sundayCount == 2) return date;
          }
        }
        return DateTime(year, 5, 8); // Fallback
      case 'gb':
        // UK: 4. Sonntag in der Fastenzeit (3 Wochen vor Ostern)
        final easter = _calculateEaster(year);
        return easter.subtract(const Duration(days: 21));
      default:
        return DateTime(year, 5, 8); // Fallback: 2. Sonntag im Mai
    }
  }

  // Berechnet Vatertag für ein Land und Jahr
  static DateTime _calculateFathersDay(int year, String country) {
    switch (country.toLowerCase()) {
      case 'de':
        // Deutschland: Christi Himmelfahrt (39 Tage nach Ostern)
        final easter = _calculateEaster(year);
        return easter.add(const Duration(days: 39));
      case 'at':
      case 'ch':
      case 'us':
      case 'ca':
      case 'au':
        // 3. Sonntag im Juni
        int sundayCount = 0;
        for (int day = 1; day <= 30; day++) {
          final date = DateTime(year, 6, day);
          if (date.weekday == DateTime.sunday) {
            sundayCount++;
            if (sundayCount == 3) return date;
          }
        }
        return DateTime(year, 6, 15); // Fallback
      default:
        return DateTime(year, 6, 15); // Fallback: 3. Sonntag im Juni
    }
  }

  // Gibt das formatierte Datum für einen Tag zurück
  String _getDateForTag(String tagName, String userCountry) {
    final now = DateTime.now();
    final year = now.year;

    switch (tagName) {
      case 'Ostern':
        final easter = _calculateEaster(year);
        return '${easter.day}.${easter.month}.';
      case 'Muttertag':
        final mothersDay = _calculateMothersDay(year, userCountry);
        return '${mothersDay.day}.${mothersDay.month}.';
      case 'Vatertag':
        final fathersDay = _calculateFathersDay(year, userCountry);
        return '${fathersDay.day}.${fathersDay.month}.';
      default:
        return '';
    }
  }

  // Vordefinierte Highlight-Tags mit festen Daten
  static const Map<String, String?> _predefinedTagsBase = {
    'Geburtstag': null, // Datum aus Userdaten oder manuell
    'Namenstag': null, // Datum manuell setzen
    'Heiligabend': '24.12.',
    '1. Weihnachtsfeiertag': '25.12.',
    '2. Weihnachtsfeiertag': '26.12.',
    'Silvester': '31.12.',
    'Neujahr': '1.1.',
    'Heilige Drei Könige': '6.1.',
    'Valentinstag': '14.2.',
    'Muttertag': 'dynamic', // Wird berechnet
    'Vatertag': 'dynamic', // Wird berechnet
    'Tag der Arbeit': '1.5.',
    'Ostern': 'dynamic', // Wird berechnet
    'Tag der Deutschen Einheit': '3.10.',
    'Allerheiligen': '1.11.',
    'Hochzeitstag': null, // Datum manuell setzen
  };

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.playlist.name)
      ..addListener(() => setState(() => _isDirty = true));
    _highlightTag = TextEditingController(
      text: widget.playlist.highlightTag ?? '',
    )..addListener(() => setState(() => _isDirty = true));
    _coverImageUrl = widget.playlist.coverImageUrl;
    _coverOriginalFileName = widget.playlist.coverOriginalFileName;

    // Initialize weekly schedule from playlist
    for (final ws in widget.playlist.weeklySchedules) {
      _weeklySchedule[ws.weekday] = Set.from(ws.timeSlots);
    }

    _specialSchedules = List.from(widget.playlist.specialSchedules);

    // Setze Modus: bevorzugt gespeicherten Modus nutzen
    _playlistType =
        widget.playlist.scheduleMode ??
        (widget.playlist.specialSchedules.isNotEmpty &&
                widget.playlist.weeklySchedules.isEmpty
            ? 'special'
            : 'weekly');

    // Setze Anlass-Text aus gespeicherter Playlist
    _specialAnlass = widget.playlist.highlightTag ?? '';

    // Rebuild Sondertermine-UI-State aus gespeicherten Daten
    if (_specialSchedules.isNotEmpty) {
      // Fülle _specialDaySlots
      for (final sp in _specialSchedules) {
        DateTime d;
        try {
          d = DateTime.fromMillisecondsSinceEpoch(sp.startDate);
        } catch (_) {
          continue;
        }
        final key = DateTime(d.year, d.month, d.day);
        _specialDaySlots.putIfAbsent(key, () => <TimeSlot>{});
        _specialDaySlots[key]!.addAll(sp.timeSlots);
      }
      // Setze Start/Ende aus min/max
      final dates =
          _specialSchedules
              .map((s) {
                try {
                  return DateTime.fromMillisecondsSinceEpoch(s.startDate);
                } catch (_) {
                  return null;
                }
              })
              .whereType<DateTime>()
              .toList()
            ..sort();
      if (dates.isNotEmpty) {
        _specialStartDate = dates.first;
        _specialEndDate = dates.last;
      }
      // Wähle initial den ersten aktiven Wochentag
      _selectedSpecialWeekday = _specialStartDate!.weekday;
    } else {
      // Falls vordefinierter Anlass ohne Termine: automatisch auf nächstes Datum setzen
      if (_specialAnlass.isNotEmpty &&
          _predefinedTagsBase.containsKey(_specialAnlass)) {
        final dt = _computeNearestFutureDateForTag(_specialAnlass);
        if (dt != null) {
          _specialStartDate = dt;
          _specialEndDate = dt;
          _selectedSpecialWeekday = dt.weekday;
          // Default: keine Slots aktiv – User wählt danach die gewünschten Slots
        }
      }
    }

    // Bestimme, ob eigener Tag oder vordefiniert
    if (_highlightTag.text.isNotEmpty &&
        !_predefinedTagsBase.containsKey(_highlightTag.text)) {
      _isCustomTag = true;
    }

    _load();
  }

  Future<void> _load() async {
    final items = await _svc.listItems(
      widget.playlist.avatarId,
      widget.playlist.id,
    );
    final medias = await _mediaSvc.list(widget.playlist.avatarId);

    // Initialize targeting controllers (mit Listeners für _isDirty)
    final tg = widget.playlist.targeting;
    _tgActiveDays = TextEditingController(
      text: tg != null && tg['activeWithinDays'] != null
          ? tg['activeWithinDays'].toString()
          : '',
    )..addListener(() => setState(() => _isDirty = true));
    _tgNewUserDays = TextEditingController(
      text: tg != null && tg['newUserWithinDays'] != null
          ? tg['newUserWithinDays'].toString()
          : '',
    )..addListener(() => setState(() => _isDirty = true));
    _tgPriority = TextEditingController(
      text: widget.playlist.priority?.toString() ?? '0',
    )..addListener(() => setState(() => _isDirty = true));

    // Lade Targeting-State
    if (tg != null) {
      _targetingEnabled = true;
      if (tg['gender'] != null) _tgGender = tg['gender'] as String;
      if (tg['matchUserDob'] == true) _tgMatchDob = true;
    }

    setState(() {
      _items = items;
      _mediaMap = {for (final m in medias) m.id: m};
    });
  }

  Future<File?> _cropToPortrait916(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final cropController = cyi.CropController();
      Uint8List? result;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: bytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropResult) {
                          if (cropResult is cyi.CropSuccess) {
                            result = cropResult.croppedImage;
                          }
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                result = null;
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                cropController.crop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE91E63),
                                      AppColors.lightBlue,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      if (result == null) return null;
      final dir = await getTemporaryDirectory();
      final tmp = await File(
        '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await tmp.writeAsBytes(result!, flush: true);
      return tmp;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final highlightText = _highlightTag.text.trim();

    // Convert Map to List<WeeklySchedule>, FILTER OUT empty timeslots
    final weeklySchedules = _weeklySchedule.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) {
          final sorted = e.value.toList()
            ..sort((a, b) => a.index.compareTo(b.index));
          return WeeklySchedule(weekday: e.key, timeSlots: sorted);
        })
        .toList();

    print(
      '🔍 DEBUG: Saving weeklySchedules: ${weeklySchedules.length} entries',
    );
    for (final ws in weeklySchedules) {
      print(
        '   - Weekday ${ws.weekday}: ${ws.timeSlots.map((t) => t.index).toList()}',
      );
    }
    // Sondertermine aus Inline-Auswahl generieren (pro Kalendertag 1 Eintrag)
    List<SpecialSchedule> specialFromInline = [];
    if (_specialDaySlots.isNotEmpty) {
      DateTime endOfDay(DateTime d) =>
          DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
      for (final entry in _specialDaySlots.entries) {
        if (entry.value.isEmpty) continue;
        final day = entry.key;
        final slots = entry.value.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        specialFromInline.add(
          SpecialSchedule(
            startDate: DateTime(
              day.year,
              day.month,
              day.day,
            ).millisecondsSinceEpoch,
            endDate: endOfDay(day).millisecondsSinceEpoch,
            timeSlots: slots,
          ),
        );
      }
    }

    final specialSchedules = specialFromInline.isNotEmpty
        ? specialFromInline
        : _specialSchedules; // Fallback auf bestehende Liste
    // Specials robust normalisieren (keine Duplikate, pro Tag 1 Eintrag)
    final ssOut = _normalizeSpecials(specialSchedules);
    final wsOut =
        weeklySchedules; // Weekly immer mit-speichern (keine Löschung)

    print(
      '🔍 DEBUG: Saving specialSchedules: ${specialSchedules.length} entries',
    );

    final p = Playlist(
      id: widget.playlist.id,
      avatarId: widget.playlist.avatarId,
      name: _name.text.trim(),
      showAfterSec: widget.playlist.showAfterSec, // wird in Timeline gesetzt
      highlightTag: highlightText.isNotEmpty ? highlightText : null,
      coverImageUrl: _coverImageUrl,
      coverOriginalFileName: _coverOriginalFileName,
      weeklySchedules: wsOut,
      specialSchedules: ssOut,
      targeting: _targetingEnabled
          ? {
              if (_tgGender != 'any') 'gender': _tgGender,
              if (_tgMatchDob) 'matchUserDob': true,
              if ((_tgActiveDays.text.trim()).isNotEmpty)
                'activeWithinDays': int.tryParse(_tgActiveDays.text.trim()),
              if ((_tgNewUserDays.text.trim()).isNotEmpty)
                'newUserWithinDays': int.tryParse(_tgNewUserDays.text.trim()),
            }
          : null,
      priority: _targetingEnabled
          ? int.tryParse(_tgPriority.text.trim())
          : null,
      scheduleMode: _playlistType,
      createdAt: widget.playlist.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    print('🔍 DEBUG: Playlist.toMap() keys: ${p.toMap().keys}');
    print('🔍 DEBUG: weeklySchedules in map: ${p.toMap()['weeklySchedules']}');

    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _svc.update(p);
      if (mounted) {
        setState(() => _isDirty = false);
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleTimeSlot(int weekday, TimeSlot slot) {
    setState(() {
      _weeklySchedule.putIfAbsent(weekday, () => <TimeSlot>{});
      if (_weeklySchedule[weekday]!.contains(slot)) {
        _weeklySchedule[weekday]!.remove(slot);
        if (_weeklySchedule[weekday]!.isEmpty) {
          _weeklySchedule.remove(weekday);
        }
      } else {
        _weeklySchedule[weekday]!.add(slot);
      }
      _isDirty = true;
    });
  }

  String _timeSlotLabel(TimeSlot slot) {
    switch (slot) {
      case TimeSlot.earlyMorning:
        return '3-6 Uhr';
      case TimeSlot.morning:
        return '6-11 Uhr';
      case TimeSlot.noon:
        return '11-14 Uhr';
      case TimeSlot.afternoon:
        return '14-18 Uhr';
      case TimeSlot.evening:
        return '18-23 Uhr';
      case TimeSlot.night:
        return '23-3 Uhr';
    }
  }

  String _timeSlotIcon(TimeSlot slot) {
    switch (slot) {
      case TimeSlot.earlyMorning:
        return '🌅';
      case TimeSlot.morning:
        return '☀️';
      case TimeSlot.noon:
        return '🌞';
      case TimeSlot.afternoon:
        return '🌤️';
      case TimeSlot.evening:
        return '🌆';
      case TimeSlot.night:
        return '🌙';
    }
  }

  String _weekdayLabel(int weekday) {
    const labels = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    return labels[weekday - 1];
  }

  String _weekdayShort(int weekday) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return labels[weekday - 1];
  }

  bool _canSelectWeekday(int weekday) {
    // Wochentag kann gewählt werden, wenn noch nicht alle Zeitfenster belegt sind
    final existing = _weeklySchedule[weekday];
    return existing == null || existing.length < 6;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduler'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isDirty)
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, color: Colors.white),
              tooltip: 'Speichern',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image + Name (einheitlich strukturiert)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 178),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Image (nur Anzeige)
                    SizedBox(
                      width: 100,
                      height: 178,
                      child: Container(
                        width: 100,
                        height: 178,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: _coverImageUrl != null
                            ? Image.network(
                                _coverImageUrl!,
                                width: 100,
                                height: 178,
                                fit: BoxFit.cover,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.playlist_play,
                                  size: 60,
                                  color: Colors.white54,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name anzeigen
                          Text(
                            widget.playlist.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 8),
                          // Name bearbeiten
                          CustomTextField(
                            label: 'Name der Playlist',
                            controller: _name,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (_saving) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlaylistTimelineScreen(
                                    playlist: widget.playlist,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.view_timeline, size: 16),
                            label: const Text('Timeline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.1,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // Anleitung (klappbar)
                  ExpansionTile(
                    iconColor: Colors.white,
                    collapsedIconColor: Colors.white70,
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    title: const Text(
                      'Anleitung',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    childrenPadding: EdgeInsets.zero,
                    children: const [
                      SizedBox(height: 8),
                      Text(
                        'Du kannst einen allgemeinen Scheduler mit Wochentagen und Zeitfenstern festlegen oder Sondertermine wie Weihnachten oder Geburtstage anlegen (reagiert dynamisch auf den Chat-Partner).',
                        style: TextStyle(height: 1.3),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Wichtig: Bei Überschneidungen gelten Sondertermine oder neuere Zeitpläne.',
                        style: TextStyle(height: 1.3),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Lege zuerst die Zeitfenster an und fülle sie anschließend mit Medien.',
                        style: TextStyle(height: 1.3),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Scheduler / Sondertermine Section
                  // Dropdown für Typ-Auswahl
                  CustomDropdown<String>(
                    label: 'Typ',
                    value: _playlistType,
                    items: const [
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text(
                          'Scheduler',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'special',
                        child: Text(
                          'Sondertermine',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _playlistType = value;
                          _isDirty = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  // Klappbarer Bereich Header
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _weeklyScheduleExpanded = !_weeklyScheduleExpanded;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => LinearGradient(
                            colors: _weeklyScheduleExpanded
                                ? [Colors.white, Colors.white]
                                : [AppColors.magenta, AppColors.lightBlue],
                          ).createShader(bounds),
                          child: Text(
                            _playlistType == 'weekly'
                                ? 'Wochentage wählen'
                                : 'Anlass wählen',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => LinearGradient(
                            colors: _weeklyScheduleExpanded
                                ? [Colors.white, Colors.white]
                                : [AppColors.magenta, AppColors.lightBlue],
                          ).createShader(bounds),
                          child: Icon(
                            _weeklyScheduleExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_weeklyScheduleExpanded) ...[
                    const SizedBox(height: 16),
                    if (_playlistType == 'weekly')
                      _buildWeeklyScheduleMatrix()
                    else
                      _buildSpecialScheduleEditor(),
                    const SizedBox(height: 24),
                  ],
                  // Targeting Section (collapsible)
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Zielgruppe (optional)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: _targetingEnabled,
                        onChanged: (v) => setState(() {
                          _targetingEnabled = v;
                          if (v) _targetingExpanded = true;
                          _isDirty = true;
                        }),
                      ),
                    ],
                  ),
                  if (_targetingEnabled) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(
                        () => _targetingExpanded = !_targetingExpanded,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Einstellungen',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            _targetingExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    if (_targetingExpanded) _buildTargetingSection(),
                  ],

                  // Media Items Section (obsolete – durch Button oben ersetzt)
                  SizedBox(
                    height: 300,
                    child: ReorderableListView.builder(
                      itemCount: _items.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final moved = _items.removeAt(oldIndex);
                        _items.insert(newIndex, moved);
                        setState(() {});
                        await _svc.setOrder(
                          widget.playlist.avatarId,
                          widget.playlist.id,
                          _items,
                        );
                      },
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        final media = _mediaMap[it.mediaId];
                        return ListTile(
                          key: ValueKey(it.id),
                          leading: media == null
                              ? const Icon(Icons.broken_image)
                              : (media.type == AvatarMediaType.video
                                    ? const Icon(Icons.videocam)
                                    : const Icon(Icons.photo)),
                          title: Text(media?.url.split('/').last ?? it.mediaId),
                          trailing: const Icon(Icons.drag_handle),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyScheduleMatrix() {
    return LayoutBuilder(
      builder: (context, cons) {
        final buttonWidth = ((cons.maxWidth - 32) / 7) - 6;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Stufe: Wochentags-Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final isActive = _weeklySchedule.containsKey(weekday);
                final canSelect = _canSelectWeekday(weekday);
                final isSelected = _selectedWeekday == weekday;

                return SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: canSelect || isActive
                        ? () {
                            setState(() {
                              if (_selectedWeekday == weekday) {
                                // Bereits selektiert -> deselektieren
                                _selectedWeekday = null;
                              } else {
                                // Selektieren für Bearbeitung
                                _selectedWeekday = weekday;
                                // Auto-create empty set if not exists
                                _weeklySchedule.putIfAbsent(
                                  weekday,
                                  () => <TimeSlot>{},
                                );
                              }
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (isSelected || isActive)
                          ? Colors.transparent
                          : Colors.grey.shade800,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade900,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 48),
                    ),
                    child: (isSelected || isActive)
                        ? Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(
                                    0xFFE91E63,
                                  ).withValues(alpha: isSelected ? 1.0 : 0.75),
                                  Color(
                                    0xFF8AB4F8,
                                  ).withValues(alpha: isSelected ? 1.0 : 0.75),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _weekdayShort(weekday),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_weekdayShort(weekday)),
                            ),
                          ),
                  ),
                );
              }),
            ),

            // 2. Stufe: Zeitfenster für gewählten Tag
            if (_selectedWeekday != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  SizedBox(
                    width:
                        200, // Feste Breite für längsten Wochentag ("Zeitfenster für Donnerstag")
                    child: Text(
                      'Zeitfenster für ${_weekdayLabel(_selectedWeekday!)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _weeklySchedule.remove(_selectedWeekday);
                        _selectedWeekday = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: Text(
                      _weekdayShort(_selectedWeekday!),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TimeSlot.values.map((slot) {
                  final isActive =
                      _weeklySchedule[_selectedWeekday]?.contains(slot) ??
                      false;
                  final slotWidth = ((cons.maxWidth - 32) / 3) - 6;

                  return GestureDetector(
                    onTap: () => _toggleTimeSlot(_selectedWeekday!, slot),
                    child: Container(
                      width: slotWidth,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: isActive
                            ? LinearGradient(
                                colors: [
                                  const Color(
                                    0xFFE91E63,
                                  ).withValues(alpha: 0.6),
                                  const Color(
                                    0xFF8AB4F8,
                                  ).withValues(alpha: 0.6),
                                ],
                              )
                            : null,
                        color: isActive ? null : Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFE91E63).withValues(alpha: 0.8)
                              : Colors.grey.shade600,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _timeSlotIcon(slot),
                            style: TextStyle(
                              fontSize: 28,
                              color: isActive
                                  ? Colors.white
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _timeSlotLabel(slot),
                            style: TextStyle(
                              fontSize: 9,
                              color: isActive
                                  ? Colors.white
                                  : Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Checkbox: Alle Tageszeiten
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      final allSelected =
                          _weeklySchedule[_selectedWeekday]?.length == 6;
                      if (allSelected) {
                        // Alle abwählen
                        _weeklySchedule[_selectedWeekday!]?.clear();
                      } else {
                        // Alle 6 Zeitfenster auswählen
                        _weeklySchedule[_selectedWeekday!] = Set.from(
                          TimeSlot.values,
                        );
                      }
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient:
                              _weeklySchedule[_selectedWeekday]?.length == 6
                              ? const LinearGradient(
                                  colors: [
                                    AppColors.magenta,
                                    AppColors.lightBlue,
                                  ],
                                )
                              : null,
                          border: _weeklySchedule[_selectedWeekday]?.length != 6
                              ? Border.all(color: Colors.white54, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _weeklySchedule[_selectedWeekday]?.length == 6
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Alle Tageszeiten',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSpecialScheduleEditor() {
    DateTime? selectedPredefinedDateTime() {
      if (_specialAnlass.isEmpty) return null;
      final base = _predefinedTagsBase[_specialAnlass];
      final now = DateTime.now();
      if (base == null) return null;
      if (base == 'dynamic') {
        if (_specialAnlass == 'Muttertag') {
          return _calculateMothersDay(now.year, 'de');
        } else if (_specialAnlass == 'Vatertag') {
          return _calculateFathersDay(now.year, 'de');
        } else if (_specialAnlass == 'Ostern') {
          return _calculateEaster(now.year);
        }
        return null;
      }
      try {
        final parts = base.replaceAll('.', ' ').trim().split(' ');
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        return DateTime(now.year, month, day);
      } catch (_) {
        return null;
      }
    }

    final predefinedDateTime = selectedPredefinedDateTime();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GMBC Button: Anlass wählen / anzeigen + Edit-Stift, triggert Popup
        Row(
          children: [
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  await _showHighlightTagDialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(160, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: Theme.of(
                      context,
                    ).extension<AppGradients>()?.magentaBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _specialAnlass.isEmpty
                              ? 'Anlass wählen'
                              : _specialAnlass,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 32),
                        const Icon(Icons.edit, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (predefinedDateTime != null)
              Text(
                _fmt(predefinedDateTime),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Ergebniszeile entfällt: Anzeige erfolgt im Button

        // Datum-Anzeige oder Eingabe
        if (predefinedDateTime != null) ...[
          Row(
            children: [
              const Text(
                'Datum:',
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(predefinedDateTime),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _specialStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _specialStartDate = picked;
                        if (_specialEndDate == null ||
                            _specialEndDate!.isBefore(picked)) {
                          _specialEndDate = picked;
                        }
                      });
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _specialStartDate != null
                            ? _fmt(_specialStartDate!)
                            : 'Startdatum',
                        style: TextStyle(
                          fontSize: 13,
                          color: _specialStartDate != null
                              ? Colors.white
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _specialEndDate ??
                          _specialStartDate ??
                          DateTime.now(),
                      firstDate: _specialStartDate ?? DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _specialEndDate = picked;
                      });
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        _specialEndDate != null
                            ? _fmt(_specialEndDate!)
                            : 'Enddatum',
                        style: TextStyle(
                          fontSize: 13,
                          color: _specialEndDate != null
                              ? Colors.white
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Wochentage-Matrix wie im Scheduler, aber basierend auf gewähltem Zeitraum
        if (_specialStartDate != null && _specialEndDate != null)
          _buildSpecialWeekdayMatrix(),
      ],
    );
  }

  // Sondertermine: Wochentage-Ansicht nach Zeitraum
  Widget _buildSpecialWeekdayMatrix() {
    final start = _specialStartDate!;
    final end = _specialEndDate!;
    final days = <DateTime>[];
    DateTime c = DateTime(start.year, start.month, start.day);
    while (!c.isAfter(DateTime(end.year, end.month, end.day))) {
      days.add(c);
      c = c.add(const Duration(days: 1));
    }

    final ordered = <int>[]; // eindeutige Wochentage in Reihenfolge
    for (final d in days) {
      if (!ordered.contains(d.weekday)) ordered.add(d.weekday);
    }

    String shortLabel(int weekday) {
      const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      return labels[weekday - 1];
    }

    bool isActiveForAllDates(int weekday, TimeSlot slot) {
      final rel = days.where((d) => d.weekday == weekday);
      if (rel.isEmpty) return false;
      for (final d in rel) {
        final key = DateTime(d.year, d.month, d.day);
        final set = _specialDaySlots[key] ?? <TimeSlot>{};
        if (!set.contains(slot)) return false;
      }
      return true;
    }

    void toggleForAllDates(int weekday, TimeSlot slot) {
      final rel = days.where((d) => d.weekday == weekday);
      final makeActive = !isActiveForAllDates(weekday, slot);
      setState(() {
        for (final d in rel) {
          final key = DateTime(d.year, d.month, d.day);
          _specialDaySlots.putIfAbsent(key, () => <TimeSlot>{});
          if (makeActive) {
            _specialDaySlots[key]!.add(slot);
          } else {
            _specialDaySlots[key]!.remove(slot);
          }
        }
      });
    }

    return LayoutBuilder(
      builder: (context, cons) {
        // Zeige IMMER alle 7 Wochentage; Tage außerhalb des Bereichs sind disabled
        final buttonWidth = ((cons.maxWidth - 32) / 7) - 6;
        bool isActiveAnyDates(int weekday) {
          final relevant = days.where((d) => d.weekday == weekday);
          for (final d in relevant) {
            final key = DateTime(d.year, d.month, d.day);
            final set = _specialDaySlots[key] ?? <TimeSlot>{};
            if (set.isNotEmpty) return true;
          }
          return false;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wochentage wählen',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final isPresent = ordered.contains(weekday);
                final isSelected = _selectedSpecialWeekday == weekday;
                final isActive = isActiveAnyDates(weekday);
                return SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: isPresent
                        ? () {
                            setState(() {
                              _selectedSpecialWeekday = isSelected
                                  ? null
                                  : weekday;
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPresent
                          ? ((isSelected || isActive)
                                ? Colors.transparent
                                : Colors.grey.shade800)
                          : null,
                      disabledBackgroundColor: Colors.grey.shade900,
                      disabledForegroundColor: Colors.grey.shade600,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 48),
                    ),
                    child: isPresent
                        ? ((isSelected || isActive)
                              ? Ink(
                                  decoration: BoxDecoration(
                                    gradient: Theme.of(
                                      context,
                                    ).extension<AppGradients>()?.magentaBlue,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 12,
                                    ),
                                    child: Text(shortLabel(weekday)),
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 12,
                                  ),
                                  child: Text(shortLabel(weekday)),
                                ))
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: Text(shortLabel(weekday)),
                          ),
                  ),
                );
              }),
            ),
            if (_selectedSpecialWeekday != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TimeSlot.values.map((slot) {
                  final active = isActiveForAllDates(
                    _selectedSpecialWeekday!,
                    slot,
                  );
                  final slotWidth = ((cons.maxWidth - 32) / 3) - 6;
                  return GestureDetector(
                    onTap: () =>
                        toggleForAllDates(_selectedSpecialWeekday!, slot),
                    child: Container(
                      width: slotWidth,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: active
                            ? LinearGradient(
                                colors: [
                                  const Color(
                                    0xFFE91E63,
                                  ).withValues(alpha: 0.6),
                                  const Color(
                                    0xFF8AB4F8,
                                  ).withValues(alpha: 0.6),
                                ],
                              )
                            : null,
                        color: active ? null : Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? const Color(0xFFE91E63).withValues(alpha: 0.8)
                              : Colors.grey.shade600,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _timeSlotIcon(slot),
                            style: TextStyle(
                              fontSize: 28,
                              color: active
                                  ? Colors.white
                                  : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _timeSlotLabel(slot),
                            style: TextStyle(
                              fontSize: 9,
                              color: active
                                  ? Colors.white
                                  : Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Entfernen-Button wie im Wochenplan: leert alle Slots des Tages
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      final relevant = days.where(
                        (d) => d.weekday == _selectedSpecialWeekday,
                      );
                      for (final d in relevant) {
                        final key = DateTime(d.year, d.month, d.day);
                        _specialDaySlots[key]?.clear();
                      }
                      _selectedSpecialWeekday = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  label: Text(
                    _weekdayShort(_selectedSpecialWeekday!),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _fmt(DateTime d) {
    // Format nach UI-Locale (sicher, ohne Provider-Abhängigkeit)
    try {
      final locale = Localizations.localeOf(context).toLanguageTag();
      return DateFormat.yMMMd(locale).format(d);
    } catch (_) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)}';
    }
  }

  // Hilfsfunktionen: nächstes zukünftiges Datum für feste/dynamische Anlässe
  DateTime _nearestFutureFixedDate(int day, int month) {
    final now = DateTime.now();
    DateTime dt = DateTime(now.year, month, day);
    final today = DateTime(now.year, now.month, now.day);
    if (dt.isBefore(today)) dt = DateTime(now.year + 1, month, day);
    return dt;
  }

  DateTime? _computeNearestFutureDateForTag(String tagName) {
    final base = _predefinedTagsBase[tagName];
    if (base == null) return null; // freier Anlass
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? candidate;
    if (base == 'dynamic') {
      DateTime dyn(int year) {
        if (tagName == 'Muttertag') return _calculateMothersDay(year, 'de');
        if (tagName == 'Vatertag') return _calculateFathersDay(year, 'de');
        if (tagName == 'Ostern') return _calculateEaster(year);
        return today;
      }

      candidate = dyn(now.year);
      if (candidate.isBefore(today)) candidate = dyn(now.year + 1);
    } else {
      try {
        final parts = base.replaceAll('.', ' ').trim().split(' ');
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        candidate = _nearestFutureFixedDate(day, month);
      } catch (_) {
        return null;
      }
    }
    // Begrenzung: nur bis max 365 Tage in die Zukunft
    if (candidate.difference(today).inDays > 366) return null;
    return candidate;
  }

  // Targeting State
  String _tgGender = 'any'; // any|male|female
  bool _tgMatchDob = false;
  late final TextEditingController _tgActiveDays;
  late final TextEditingController _tgNewUserDays;
  late final TextEditingController _tgPriority;
  bool _targetingEnabled = false;
  bool _targetingExpanded = false;

  Future<void> _showHighlightTagDialog() async {
    final customController = TextEditingController(
      text: _isCustomTag ? _highlightTag.text : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Anlass'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eigener Anlass Input
                CustomTextField(
                  label: 'Eigener Anlass',
                  controller: customController,
                  hintText: 'z.B. Firmenjubiläum, Abschlussfeier...',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      final custom = customController.text.trim();
                      if (custom.isNotEmpty) {
                        setState(() {
                          _highlightTag.text = custom;
                          _specialAnlass = custom;
                          _isCustomTag = true;
                          // Reset Sondertermine-State – Nutzer wählt anschließend Datum/Zeiträume
                          _specialStartDate = null;
                          _specialEndDate = null;
                          _selectedSpecialWeekday = null;
                          _specialDaySlots.clear();
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: Theme.of(
                          context,
                        ).extension<AppGradients>()?.magentaBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Übernehmen',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Vordefinierte Tags (scrollbar)
                const Text(
                  'Oder wählen Sie einen vordefinierten Anlass:',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: _predefinedTagsBase.entries.map((entry) {
                      final tagName = entry.key;
                      final tagDateBase = entry.value;

                      // Bestimme Datum
                      String? displayDate;
                      if (tagDateBase == 'dynamic') {
                        displayDate = _getDateForTag(tagName, 'de');
                      } else {
                        displayDate = tagDateBase;
                      }

                      return ListTile(
                        title: Text(tagName),
                        trailing: displayDate != null
                            ? Text(
                                displayDate,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _highlightTag.text = tagName;
                            _specialAnlass = tagName;
                            _isCustomTag = false;
                            // Reset & Auto-Set für vordefinierte Anlässe
                            _specialDaySlots.clear();
                            final dt = (() {
                              final base = _predefinedTagsBase[tagName];
                              final now = DateTime.now();
                              if (base == null) return null;
                              if (base == 'dynamic') {
                                if (tagName == 'Muttertag') {
                                  return _calculateMothersDay(now.year, 'de');
                                } else if (tagName == 'Vatertag') {
                                  return _calculateFathersDay(now.year, 'de');
                                } else if (tagName == 'Ostern') {
                                  return _calculateEaster(now.year);
                                }
                                return null;
                              }
                              try {
                                final parts = base
                                    .replaceAll('.', ' ')
                                    .trim()
                                    .split(' ');
                                final day = int.parse(parts[0]);
                                final month = int.parse(parts[1]);
                                return DateTime(now.year, month, day);
                              } catch (_) {
                                return null;
                              }
                            })();
                            if (dt != null) {
                              _specialStartDate = dt;
                              _specialEndDate = dt;
                              _selectedSpecialWeekday = dt.weekday;
                            }
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
