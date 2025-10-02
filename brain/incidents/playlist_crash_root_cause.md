# Playlist-Liste crashte nach Speichern von weeklySchedules – Root Cause

Datum: 2025-10-01

## Symptome
- Nach dem Speichern von weeklySchedules in `playlist_edit_screen` ließ sich die `playlist_list_screen` nicht mehr öffnen.
- Build & Sign liefen durch (BUILD SUCCEEDED), aber beim Öffnen der Liste beendete sich der Screen/Flow ohne Flutter-Stacktrace.
- Im macOS-Live-Log nur Firebase-Warnungen (GoogleService-Info.plist), kein „EXCEPTION CAUGHT“.

## Ursache
1) Dateninkonsistenz (bereits behoben):
Die Query in `PlaylistService.list()` verwendete

```text
orderBy('createdAt', descending: true)
```

Mindestens ein Dokument in `avatars/{avatarId}/playlists` hatte ein inkonsistentes Feld `createdAt` (fehlend oder falscher Typ, z. B. String statt Zahl/Millisekunden). Nach dem Löschen/Neuaufsetzen der Collection wurde ein Datensatz ohne korrektes `createdAt` gespeichert/editiert. Firestore bricht in diesem Fall die gesamte Abfrage ab; dadurch kippte das Laden der Liste.

Indirekter Hinweis: Der Crash verschwand unmittelbar, sobald wir die Query robust gemacht und die Dokumente beim Laden „sanitized“ haben.

2) Wrap‑Merge der Zeitfenster 5↔0 (eigentliche, reproduzierbare Crash‑Ursache beim Speichern von Sonderterminen):
- Nach dem Speichern von Sonderterminen mit den Slots `5` (23–3) und `0` (3–6) wurde in der Liste `mergeSlotsLabel(...)` aufgerufen, um die Slots als Zeitbereich anzuzeigen.
- Die frühere Implementierung versuchte, Zirkularität (Wrap über Mitternacht) über eine Schleife und einen Sonderfall „merge first/last run“ zu behandeln. In Kombinationen wie `[5,0]` oder `[4,5,0]` konnte die Laufsteuerung inkonsistent werden (z. B. fehlerhafte Run‑Grenzen), was zu einem unhandlbaren Zustand/RangeError im Render führte. Der Absturz zeigte sich direkt nach „Speichern“, tatsächlich passierte er aber beim Rendern der Liste nach dem Navigator‑Pop.
- Fix: `mergeSlotsLabel(...)` wurde neu implementiert (lineares Run‑Building mit optionalem „Shift“ von 0→6), wodurch Wraps stabil zu Labels wie `23–6 Uhr` zusammengefasst werden. Zusätzlich werden Weekly/Special‑Slots vor dem Speichern dedupliziert und sortiert.

## Fix (implementiert)
1) `PlaylistService.list()`
   - Query mit Fallback: erst `orderBy('createdAt')`, bei Fehler ohne Sortierung laden.
   - JEDES Dokument vor dem Parsen durch `_sanitizePlaylistMap(...)` normalisieren.

```text
lib/services/playlist_service.dart
→ Fallback ohne orderBy und Sanitisierung pro Doc
```

2) UI-Failsafe:
   - In `playlist_list_screen.dart` wird die Zusammenfassung über `_buildSafeSummary(p)` gerendert, das Exceptions abfängt, damit die Liste niemals crasht.

3) Wrap‑Merge stabilisiert:
- `playlist_list_screen.dart` → `mergeSlotsLabel(...)` fasst Slots jetzt deterministisch zusammen (inkl. 5↔0‑Wrap) und vermeidet zirkuläre Schleifen/indizierte Sonderfälle.

## Warum half das?
- Der Fallback verhindert, dass eine einzelne fehlerhafte `createdAt`-Value die gesamte Query scheitern lässt.
- Die Sanitisierung sorgt dafür, dass fehlende/falsche Typen (z. B. `createdAt`, `timeSlots`) beim Client-Lesen korrigiert werden und `Playlist.fromMap` stabile Daten sieht.
- Die neue Merge-Logik eliminiert den Wrap‑Bug (Slots `[5,0]`) und erzeugt stabile Labels (z. B. `23–6 Uhr`) ohne Sonderfall‑Brüche.

## Prävention/Follow-ups
- Datenhygiene: Einmalige „Repair“-Routine über alle Playlists laufen lassen (es gibt bereits `validate(...)` und `repair(...)` im Service), um inkonsistente Datensätze endgültig zu beheben.
- Optional Firestore-Regel verschärfen: `createdAt` als Zahl verlangen.
- Beim Erstellen/Updaten sicherstellen, dass `createdAt` IMMER als Millisekunden-Zahl gesetzt bleibt (der Code tut das; manuelle Console-Edits vermeiden).

## Status
- Behoben durch robustes Laden und UI-Failsafe. Liste lässt sich wieder öffnen, Speichern von weeklySchedules funktioniert.
 - Wrap‑Merge 5↔0 in der Listenansicht behoben; Sondertermine mit Slot 0 und 5 verursachen keinen Absturz mehr.

## Diagnose‑Fallen & Fehler‑Masking (Transparenz)
- Kein Flutter‑Stacktrace: Der Fehler trat im Renderpfad auf und beendete die View ohne „EXCEPTION CAUGHT“. In der macOS‑Konsole waren nur Firebase‑Warnungen sichtbar. Ohne Stacktrace war die Verursacher‑Datei zunächst nicht offensichtlich.
- Mehrere Ursachen nacheinander: Zuerst eine Dateninkonsistenz (`orderBy('createdAt')`), danach ein separater UI‑Bug (Wrap‑Merge 5↔0). Das hat die Diagnose verwischt und die Suche verzögert.
- State-/Navigation‑abhängige Repro: Der Wrap‑Bug zeigte sich zuverlässig erst nach dem Navigationspfad „Meine Avatare → Playlist‑Liste → Edit“ in Kombination mit Slots 5+0; normale Saves sahen unauffällig aus.
- Potenzielles Masking durch Failsafes: Sanitisierung/Fail‑safe‑Rendering verhindert Crash (gewünscht), kann aber Symptome kaschieren. Deshalb: Failsafes nur mit Logging und Diagnostik einsetzen.

## Prävention – konkrete Maßnahmen
- Unit‑Tests für Slot‑Merge (insb. Wrap‑Fälle): [0,1]→3–11, [5,0]→23–6, [4,5,0]→18–6, [alle]→Ganztägig.
- Invarianten prüfen (asserts/guards):
  - `timeSlots` ⊆ {0..5}; keine Duplikate; Specials pro Tag ein Eintrag; sortiert.
  - Vor Rendern/Merge defensiv normalisieren und loggen, wenn Korrekturen nötig sind.
- Telemetrie & Logging:
  - Warn‑Logs bei Sanitisierungen, optional Sentry‑Breadcrumbs im Renderpfad der Liste.
  - Navigationspfad (MA→PL→PE) als Breadcrumb erfassen, um state‑abhängige Bugs zu erkennen.
- E2E‑Testfall „Wrap 5↔0 mit Navigation“ aufnehmen.
