# Playlist Targeting & Selection Plan (v1)

Ziel: Zwei parallele Pläne pro Playlist unterstützen, plus einfache Zielgruppen-Filter – UI konsistent mit „Scheduler“, erweiterbar für Chat-Livebetrieb.

## Datenmodell
- `weeklySchedules: WeeklySchedule[]` (bereits vorhanden)
- `specialSchedules: SpecialSchedule[]` (Tag/Zeitraum + `timeSlots`)
- `targeting: { gender?: 'male'|'female'; matchUserDob?: boolean; activeWithinDays?: number; newUserWithinDays?: number }`
- `priority?: number` (höher gewinnt bei Kollision)

## UI (Playlist Edit)
- Dropdown: Scheduler/Sondertermine → steuert, welche Ansicht angezeigt wird
- Sondertermine: 1:1 „Scheduler“-UI, aber über Datumsbereich; Wochentage disabled außerhalb des Bereichs
- Rechts neben „Anlass“: lokalisiertes Datum
- Zielgruppe (optional):
  - Gender Chips: Alle/Männlich/Weiblich
  - Switch: Geburtstag (DOB) berücksichtigen
  - Inputs: Aktiv in X Tagen, Neu registriert in X Tagen
  - Input: Priorität

## Speichern
- `weeklySchedules`: aus Map<int, Set<TimeSlot>>
- `specialSchedules`: aus `Map<Date, Set<TimeSlot>>` → pro Datum `SpecialSchedule` (00:00–23:59:59)
- `targeting` und `priority` direkt an `Playlist`

## Auswahl-Logik (Chat Start)
1) Ermitteln, ob Sondertermin trifft (Datum + Zeitfenster). Falls ja, diese Playlists vormerken
2) Sonst weekly prüfen (Wochentag + Zeitfenster)
3) Zielgruppe filtern:
   - `gender`, `matchUserDob` (Tag/Monat), `activeWithinDays`, `newUserWithinDays`
4) Konflikte: nach `priority` (desc), danach `createdAt` (desc)
5) Fallback: Default-Playlist

## Roadmap v2
- `ageRange`, `languages`, `countries`, `userTags`
- Frequency Capping: `maxImpressionsPerUser`
- A/B Auswahlstrategie

