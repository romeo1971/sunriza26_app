# Media-Galerie, Playlists und Shared Moments – Aufgabenliste

Ziel: Für jeden Avatar eine Medien-Galerie, planbare Playlists und eine an den Chat angebundene Anzeige mit Nutzerentscheidung. Entscheidungen werden dauerhaft in „Shared Moments“ gespeichert.

## Architektur grob
- Firestore Collections:
  - `avatars/{avatarId}/media/{mediaId}`: Metadaten für Bild/Video (url, type, created_at, width, height, duration, owner_user_id)
  - `avatars/{avatarId}/playlists/{playlistId}`: name, schedule (daily|weekly|monthly|date|events), rules, items_order
  - `avatars/{avatarId}/playlistItems/{itemId}` (oder Subcollection von playlists): media_ref, show_at_offset_sec, created_at
  - `users/{userId}/avatars/{avatarId}/sharedMoments/{momentId}`: media_ref, decision (shown|rejected), decided_at
- Storage: Uploads wie bisher über Firebase Storage; URLs werden in `media` hinterlegt.
- Backend: keine Pflicht, Anzeige-/Entscheidungslogik läuft im Client; optional Endpoint für serverseitige Validierung.

## Datenmodell (Dart – geplant)
- `AvatarMedia { id, avatarId, type: image|video, url, thumbUrl?, durationMs?, createdAt }`
- `Playlist { id, avatarId, name, schedule: { kind, time?, daysOfWeek?, date?, events[] }, items: [PlaylistItemRef] }`
- `PlaylistItem { id, mediaId, offsetSec, order }`
- `SharedMoment { id, userId, avatarId, mediaId, decision, decidedAt }`

## Screens/Flows
1) `media_gallery_screen`:
   - Upload (Bild/Video) + Crop bei Bildern
   - Mehrfachauswahl, Löschen
   - Auswahl für Playlist (Popup)
2) Playlist-Management:
   - Liste, Neue Playlist, Items hinzufügen (aus Galerie), Reorder (Drag & Drop), Offset je Item
   - Scheduler: täglich/wöchentlich/monatlich/spezifisches Datum/Event-Tage (Geburtstag, Weihnachten etc.)
3) Chat-Overlay:
   - Scheduler prüft, welche Items fällig sind (Schedule + Item-Offsets), zeigt Item verpixelt
   - Buttons: Anzeigen/Ablehnen; bei Anzeigen max. 45s sichtbar, dann fade out
   - Entscheidung → `sharedMoments` persistieren
4) `shared_moments_screen`:
   - Alle Items der Playlist, markiert als gesehen/abgelehnt; abgelehnte dauerhaft verpixelt, Anzeige on-demand möglich

## Akzeptanzkriterien
- Galerie: Upload, Crop, Anzeige, Auswahl für Playlist funktioniert stabil.
- Playlist: Erstellen, Hinzufügen, Reordering, Offsets, Scheduler speichern und laden.
- Chat: Overlay triggert korrekt nach Scheduler/Offsets; Entscheidungen werden persistiert.
- Shared Moments: Übersicht mit Status; abgelehnte Inhalte weiterhin verpixelt.
- Lokalisierungsschlüssel vorhanden; Fehlerbehandlung und Loading-States vorhanden.

## Folgearbeiten
- Optional serverseitiger Scheduler; aktuell clientseitig beim Chat aktiv.
- Tests (Widget/Service) für Playlist-Reordering und Overlay-Timing.

