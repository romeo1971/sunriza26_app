# Firebase Storage Pfad-Konsistenz Fix (2025-10-02)

## Problem
Die Firebase Storage Pfade waren **inkonsistent** zwischen verschiedenen Services und entsprachen **nicht** den Storage Rules:

### ❌ Alte, inkonsistente Pfade:
1. **`avatar_details_screen.dart`**: `avatars/$uid/$avatarId/images/...` (doppelte Hierarchie)
2. **`firebase_storage_service.dart`**: `avatars/${user.uid}/images/...` (ohne avatarId)
3. **`avatar_service.dart`**: `avatars/${user.uid}/images/${avatarId}_...` (mit avatarId im Dateinamen, nicht im Pfad)
4. **`firebase_diagnostics.dart`**: `avatars/${user.uid}` (ohne avatarId)

### ✅ Storage Rules erwarteten:
```
avatars/{avatarId}/{allPaths=**}
```
Die Ownership-Prüfung erfolgt über den Firestore-Avatar-Dokument (`userId` ist ein Feld im Avatar-Dokument), **nicht** über den Storage-Pfad.

---

## Root Cause
- **Alte Datenbank-Struktur**: Ursprünglich wurde `userId` als Teil des Storage-Pfads verwendet.
- **Neue Architektur**: `userId` wird **im** Avatar-Dokument (Firestore) gespeichert, nicht mehr im Pfad.
- **Fehlende Migration**: Die Services wurden nicht vollständig aktualisiert.

---

## Lösung

### 1. **Alle Avatar-spezifischen Uploads korrigiert** auf:
```dart
'avatars/$avatarId/images/${timestamp}_$i.jpg'
'avatars/$avatarId/videos/${timestamp}_$i.mp4'
'avatars/$avatarId/texts/${timestamp}_$i.txt'
'avatars/$avatarId/audio/${timestamp}_$i.mp3'
```

### 2. **Fallback-Pfade** (für Uploads ohne `avatarId`) geändert auf:
```dart
'users/${user.uid}/uploads/images/${timestamp}_$fileName'
'users/${user.uid}/uploads/videos/${timestamp}_$fileName'
'users/${user.uid}/uploads/texts/${timestamp}_$fileName'
'users/${user.uid}/uploads/audio/${timestamp}_$fileName'
```

### 3. **Storage Rules erweitert**:
```
// Haupt-Avatar-Struktur (mit Firestore Ownership Check)
match /avatars/{avatarId}/{allPaths=**} {
  allow read: if true; // Public read
  allow write: if signedIn() && 
                (
                  firestore.exists(/databases/(default)/documents/avatars/$(avatarId)) &&
                  firestore.get(/databases/(default)/documents/avatars/$(avatarId)).data.userId == request.auth.uid
                ) &&
                isValidFileType() && 
                isValidFileSize();
}

// Fallback für Legacy-Uploads ohne avatarId
match /users/{userId}/uploads/{allPaths=**} {
  allow read: if true; // Public read
  allow write, delete: if isOwner(userId) && isValidFileType() && isValidFileSize();
}
```

---

## Betroffene Dateien

### ✅ Korrigiert:
1. **`lib/screens/avatar_details_screen.dart`**
   - `_onAddImages()`: `avatars/$avatarId/images/...`
   - `_onAddVideos()`: `avatars/$avatarId/videos/...`
   - `_onAddAudio()`: `avatars/$avatarId/audio/...`
   - Text-Upload: `avatars/$avatarId/texts/...`

2. **`lib/services/firebase_storage_service.dart`**
   - `uploadAvatarImages()`: `avatars/$avatarId/images/...`
   - `uploadAvatarVideos()`: `avatars/$avatarId/videos/...`
   - `uploadAvatarTextFiles()`: `avatars/$avatarId/texts/...`
   - Fallback-Pfade: `users/${user.uid}/uploads/...`

3. **`lib/services/avatar_service.dart`**
   - `createAvatar()`: Avatar-Bild, Bilder, Videos, Textdateien
   - `addMediaToAvatar()`: Neue Medien hinzufügen
   - Alle Pfade jetzt: `avatars/$avatarId/...`

4. **`storage.rules`**
   - Neue Rule für `users/{userId}/uploads/**` hinzugefügt

### ⚠️ Noch zu prüfen:
- **`lib/services/firebase_diagnostics.dart`**: Zeile 54 verwendet noch `avatars/${user.uid}` - sollte evtl. alle Avatare durchgehen oder angepasst werden.

---

## Prävention

### 1. **Code-Konvention dokumentieren**:
- Alle Avatar-Medien: `avatars/$avatarId/{images|videos|texts|audio}/...`
- Ownership via Firestore-Dokument, **nicht** via Storage-Pfad
- User-spezifische Uploads (ohne Avatar): `users/$userId/uploads/...`

### 2. **Unit Tests**:
```dart
test('Avatar image upload path should be avatars/{avatarId}/images/', () {
  final path = FirebaseStorageService.buildAvatarImagePath(avatarId, timestamp);
  expect(path, startsWith('avatars/$avatarId/images/'));
  expect(path, isNot(contains(user.uid))); // kein user.uid im Pfad!
});
```

### 3. **Lint-Rule** (Custom):
- Verbiete `'avatars/\${user.uid}'` im Code
- Verbiete `'avatars/\$uid'` im Code

### 4. **Dokumentation**:
- `brain/docs/firebase_storage_architecture.md` erstellen
- In `lib/boot/engineering_notes.dart` verlinken

---

## Testing Checklist
- [ ] Image-Upload in `avatar_details_screen` testen
- [ ] Video-Upload in `avatar_details_screen` testen
- [ ] Audio-Upload in `avatar_details_screen` testen
- [ ] Text-Upload in `avatar_details_screen` testen
- [ ] Avatar-Erstellung mit `avatar_service.dart` testen
- [ ] Medien zu bestehendem Avatar hinzufügen testen
- [ ] Console-Logs auf korrekte Pfade prüfen
- [ ] Firebase Storage Rules deploy testen

---

## Related
- `brain/docs/firebase_storage_architecture.md` - **Offizielle Pfad-Struktur-Dokumentation**
- `brain/incidents/playlist_crash_root_cause.md` - Ähnliches Problem: Daten-Inkonsistenz führt zu Crashes
- `lib/boot/engineering_notes.dart` - Globaler Engineering-Anker

