import 'package:flutter/material.dart';
import '../models/playlist_models.dart';
import 'package:intl/intl.dart';
import '../utils/playlist_time_utils.dart';

/// Zeigt die Wochenübersicht (Mo–So) bzw. bei Sonderterminen
/// eine kompakte Zusammenfassung für eine `Playlist`.
class PlaylistScheduleSummary extends StatelessWidget {
  final Playlist playlist;

  const PlaylistScheduleSummary({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    if (p.weeklySchedules.isEmpty && p.specialSchedules.isEmpty) {
      return const Text(
        'Kein Scheduler',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      );
    }

    final weekdays = const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    // Modus bestimmen: weekly oder special
    final mode = p.scheduleMode ?? 'weekly';
    final Map<int, List<int>> weekdaySlots = {};
    if (mode == 'weekly') {
      for (final ws in p.weeklySchedules) {
        weekdaySlots[ws.weekday] = ws.timeSlots.map((t) => t.index).toList();
      }
    } else {
      // Aggregiere SpecialSchedules zu Wochentagen (Infoansicht)
      for (final sp in p.specialSchedules) {
        DateTime d;
        try {
          d = DateTime.fromMillisecondsSinceEpoch(sp.startDate);
        } catch (_) {
          continue;
        }
        final wd = d.weekday; // 1=Mo ... 7=So
        weekdaySlots.putIfAbsent(wd, () => []);
        for (final t in sp.timeSlots) {
          final idx = t.index;
          if (!weekdaySlots[wd]!.contains(idx)) {
            weekdaySlots[wd]!.add(idx);
          }
        }
      }
    }

    String mergeSlotsLabel(List<int> slots) => buildSlotSummaryLabel(slots);

    // Zeilenlayout: Für jeden vorhandenen Tag eine Zeile (Tag links, Info rechts)
    final rows = <Widget>[];
    for (int wd = 1; wd <= 7; wd++) {
      if (!weekdaySlots.containsKey(wd)) continue;
      final ints = weekdaySlots[wd]!;
      final info = ints.length == 6
          ? 'Ganztägig'
          : mergeSlotsLabel(List<int>.from(ints));

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28, // fixe Breite für saubere Ausrichtung
              child: Text(
                weekdays[wd - 1],
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                info,
                style: const TextStyle(fontSize: 9, color: Colors.white70),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
      if (wd < 7) rows.add(const SizedBox(height: 4));
    }

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );

    // Bei 'special' zeige kompakte Kopfzeile mit Datum + Zeitspannen
    if ((p.scheduleMode ?? 'weekly') == 'special' &&
        p.specialSchedules.isNotEmpty) {
      final specials = List<SpecialSchedule>.from(p.specialSchedules)
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final first = specials.first;

      DateTime? start;
      try {
        start = DateTime.fromMillisecondsSinceEpoch(first.startDate);
      } catch (_) {
        start = null;
      }
      final locale = Localizations.localeOf(context).toLanguageTag();
      final label = start != null
          ? DateFormat('EEEE, d. MMM. y', locale).format(start)
          : 'Sondertermin';
      final ranges = mergeSlotsLabel(
        first.timeSlots.map((e) => e.index).toList(),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.amber,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ranges,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          // summary (Wochenübersicht) bewusst nicht erneut rendern
        ],
      );
    }

    return summary;
  }
}
