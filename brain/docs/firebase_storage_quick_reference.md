# Firebase Storage Quick Reference

## Pfad-Übersicht (Cheat Sheet)

| Typ | Pfad-Template | Beispiel | Ownership |
|-----|---------------|----------|-----------|
| **Avatar Hero-Bild** | `avatars/{avatarId}/avatar_{timestamp}.jpg` | `avatars/abc123/avatar_1696262400000.jpg` | Via Firestore |
| **Avatar Bilder** | `avatars/{avatarId}/images/{timestamp}_{index}.jpg` | `avatars/abc123/images/1696262400000_0.jpg` | Via Firestore |
| **Avatar Videos** | `avatars/{avatarId}/videos/{timestamp}_{index}.mp4` | `avatars/abc123/videos/1696262400000_0.mp4` | Via Firestore |
| **Avatar Audio** | `avatars/{avatarId}/audio/{timestamp}_{index}.mp3` | `avatars/abc123/audio/1696262400000_0.mp3` | Via Firestore |
| **Avatar Texte** | `avatars/{avatarId}/texts/{filename}.txt` | `avatars/abc123/texts/profile.txt` | Via Firestore |
| **Playlist Cover** | `avatars/{avatarId}/playlists/{playlistId}/cover.jpg` | `avatars/abc123/playlists/xyz789/cover.jpg` | Via Firestore |
| **User Profilbild** | `users/{userId}/images/profileImage/profile_{timestamp}.jpg` | `users/user456/images/profileImage/profile_1696262400000.jpg` | Via Pfad |
| **Legacy Upload** | `users/{userId}/uploads/{type}/{timestamp}_{filename}` | `users/user456/uploads/images/1696262400000_photo.jpg` | Via Pfad |

---

## Code-Snippets

### Avatar-Bild hochladen
```dart
final url = await FirebaseStorageService.uploadImage(
  imageFile,
  customPath: 'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_0.jpg',
);
```

### Playlist-Cover hochladen
```dart
final ref = FirebaseStorage.instance.ref().child(
  'avatars/$avatarId/playlists/$playlistId/cover.jpg',
);
await ref.putFile(file);
final url = await ref.getDownloadURL();
```

### User-Profilbild hochladen
```dart
final ref = FirebaseStorage.instance.ref(
  'users/${user.uid}/images/profileImage/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
);
await ref.putFile(file);
final url = await ref.getDownloadURL();
```

---

## Validierungs-Checklist

- [ ] Pfad enthält **kein `$uid`** bei Avatar-Uploads
- [ ] Pfad beginnt mit **`avatars/$avatarId/...`** für Avatar-Medien
- [ ] Pfad beginnt mit **`users/$userId/...`** für User-Profile
- [ ] Timestamp verwendet **`DateTime.now().millisecondsSinceEpoch`**
- [ ] File-Extension ist **korrekt** (`.jpg`, `.mp4`, `.txt`, etc.)
- [ ] `contentType` ist **explizit gesetzt** (bei Video/Audio)

---

## Häufige Fehler

| ❌ Falsch | ✅ Richtig |
|-----------|-----------|
| `avatars/$uid/$avatarId/images/...` | `avatars/$avatarId/images/...` |
| `avatars/${user.uid}/images/...` | `avatars/$avatarId/images/...` |
| `avatars/$avatarId/images/${avatarId}_0.jpg` | `avatars/$avatarId/images/1696262400000_0.jpg` |
| `users/$userId/profileImage/...` | `users/$userId/images/profileImage/...` |

---

## Siehe auch

- **Detaillierte Doku:** `brain/docs/firebase_storage_architecture.md`
- **Fix-Historie:** `brain/incidents/firebase_storage_path_consistency_fix.md`
- **Storage Rules:** `storage.rules`

