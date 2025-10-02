# Dokumentation

Dieser Ordner enthält alle technischen Dokumentationen, Architektur-Entscheidungen und Konventionen für die Sunriza26-App.

## Inhalte

### **Architektur & Konventionen**
- **`firebase_storage_architecture.md`** - Offizielle Firebase Storage Pfad-Struktur (WICHTIG!)
- **`firebase_storage_quick_reference.md`** - Cheat Sheet für Storage-Pfade
- **`architecture.md`** - Allgemeine App-Architektur

### **Features & Planung**
- **`playlist_targeting_plan.md`** - Playlist-Targeting-System
- **`tasks_media_playlist.md`** - Media & Playlist Tasks

---

## Wichtige Regeln

### Firebase Storage Pfade
**IMMER verwenden:**
```dart
'avatars/{avatarId}/images/...'
'avatars/{avatarId}/videos/...'
'avatars/{avatarId}/playlists/{playlistId}/cover.jpg'
```

**NIEMALS verwenden:**
```dart
'avatars/{userId}/{avatarId}/...'  ❌
'avatars/{userId}/...'              ❌
```

→ Siehe `firebase_storage_architecture.md` für Details!

---

## Navigation

- **Incident Reports:** `brain/incidents/`
- **Operations:** `brain/ops/`
- **Media Assets:** `brain/media/`
- **Dokumentation:** `brain/docs/` (hier)

