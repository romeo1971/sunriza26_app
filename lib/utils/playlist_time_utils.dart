// Utils für Zeitfenster-Zusammenfassung und Slot-Merge
// Kontext & Root Cause Doku: siehe brain/incidents/playlist_crash_root_cause.md

/// Baut ein menschenlesbares Label aus Slot-Indizes (0..5),
/// berücksichtigt Wrap-Fälle (z. B. 5→0 als durchgehender Bereich 23–6 Uhr).
///
/// Mapping der Slots:
/// 0: 3–6, 1: 6–11, 2: 11–14, 3: 14–18, 4: 18–23, 5: 23–3
String buildSlotSummaryLabel(List<int> slots) {
  if (slots.isEmpty) return '';
  // Nur 0..5 zulassen, Duplikate entfernen
  final valid = slots.where((s) => s >= 0 && s < 6).toSet().toList()..sort();
  if (valid.isEmpty) return '';
  if (valid.length == 6) return 'Ganztägig';

  // Prüfe, ob zirkulärer Wrap zwischen 5 und 0 vorliegt
  List<int> seq = List<int>.from(valid);
  final wraps = seq.first == 0 && seq.last == 5;
  if (wraps) {
    // 0 hinter 6 verschieben, um einen linearen Run zu bilden
    seq = seq.map((v) => v == 0 ? 6 : v).toList()..sort();
  }

  // Lineare Runs bilden
  final runs = <List<int>>[];
  int start = seq.first;
  int prev = seq.first;
  for (int i = 1; i < seq.length; i++) {
    final cur = seq[i];
    if (cur == prev + 1) {
      prev = cur;
      continue;
    }
    runs.add([start, prev]);
    start = prev = cur;
  }
  runs.add([start, prev]);

  int hourForStart(int idx) {
    const startTimes = [3, 6, 11, 14, 18, 23];
    return startTimes[idx % 6];
  }

  int hourForEnd(int idx) {
    const endTimes = [6, 11, 14, 18, 23, 27];
    int h = endTimes[idx % 6];
    if (idx >= 6) h += 24; // verschobene Bereiche anheben
    return h;
  }

  String labelForRun(int sIdx, int eIdx) {
    final sh = hourForStart(sIdx);
    int eh = hourForEnd(eIdx);
    if (eh >= 24) eh -= 24; // zurück in 0..23
    return '$sh–$eh Uhr';
  }

  final labels = runs.map((r) => labelForRun(r[0], r[1])).toList();
  return labels.join(', ');
}
