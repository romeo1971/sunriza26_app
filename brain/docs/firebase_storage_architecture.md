# Firebase Storage Architektur

## Übersicht

Dieses Dokument definiert die **offizielle Pfad-Struktur** für alle Firebase Storage Uploads in der Sunriza26-App. Diese Struktur muss **konsistent** in allen Services, Screens und Storage Rules verwendet werden.

---

## Pfad-Struktur

### 1. **Avatar-Medien** (Hauptstruktur)

```
avatars/{avatarId}/
├── avatar_{timestamp}.jpg              # Hero/Profilbild des Avatars
├── images/
│   ├── {timestamp}_0.jpg
│   ├── {timestamp}_1.jpg
│   └── ...
├── videos/
│   ├── {timestamp}_0.mp4
│   ├── {timestamp}_cam.mp4
│   └── ...
├── audio/
│   ├── {timestamp}_0.mp3
│   ├── {timestamp}_1.wav
│   └── ...
├── texts/
│   ├── profile.txt
│   ├── {timestamp}_0.txt
│   └── ...
└── playlists/
    └── {playlistId}/
        └── cover.jpg                   # Playlist Cover Image (9:16)
```

**Ownership:** Via Firestore-Dokument `avatars/{avatarId}` → Feld `userId`

**Code-Beispiel:**
```dart
// ✅ KORREKT
'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_0.jpg'

// ❌ FALSCH - NIEMALS userId im Pfad!
'avatars/$userId/$avatarId/images/...'
'avatars/${user.uid}/images/...'
```

---

### 2. **User-Profile**

```
users/{userId}/
├── images/
│   └── profileImage/
│       └── profile_{timestamp}.jpg     # User Profilbild
└── uploads/                            # Legacy-Fallback (ohne avatarId)
    ├── images/
    ├── videos/
    ├── texts/
    └── audio/
```

**Ownership:** Via `userId` im Pfad

**Code-Beispiel:**
```dart
// ✅ KORREKT - User Profile Image
'users/${user.uid}/images/profileImage/profile_${timestamp}.jpg'

// ✅ KORREKT - Legacy-Fallback (wenn kein avatarId vorhanden)
'users/${user.uid}/uploads/images/${timestamp}_image.jpg'
```

---

### 3. **Chat-Dateien**

```
chats/{chatId}/
└── files/
    ├── {timestamp}_image.jpg
    ├── {timestamp}_document.pdf
    └── ...
```

**Ownership:** Alle eingeloggten User haben Zugriff

---

### 4. **Legal Pages**

```
legal_pages/{type}/
├── privacy_policy.pdf
├── terms_of_service.pdf
└── ...
```

**Ownership:** Public read, signed-in write

---

### 5. **Analytics**

```
analytics/{userId}/
├── logs/
├── reports/
└── ...
```

**Ownership:** Via `userId` im Pfad

---

### 6. **Public Assets**

```
public/
├── logos/
├── banners/
└── ...
```

**Ownership:** Public read, signed-in write

---

## Storage Rules

### Aktuelle Rules (Stand: 2025-10-02)

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Helper Functions
    function signedIn() { return request.auth != null; }
    function isOwner(userId) { return signedIn() && request.auth.uid == userId; }
    function isValidFileType() {
      return request.resource.contentType.matches('image/.*') ||
             request.resource.contentType.matches('video/.*') ||
             request.resource.contentType.matches('audio/.*') ||
             request.resource.contentType.matches('text/.*') ||
             request.resource.contentType.matches('application/pdf');
    }
    function isValidFileSize() {
      return request.resource.size < 50 * 1024 * 1024; // 50MB limit
    }

    // 1. Avatar Files - Ownership via Firestore
    match /avatars/{avatarId}/{allPaths=**} {
      allow read: if true; // Public read
      allow write: if signedIn() && 
                      (
                        (firestore.exists(/databases/(default)/documents/avatars/$(avatarId)) &&
                         firestore.get(/databases/(default)/documents/avatars/$(avatarId)).data.userId == request.auth.uid) ||
                        firestore.exists(/databases/(default)/documents/users/$(request.auth.uid)/avatars/$(avatarId))
                      ) &&
                      isValidFileType() && 
                      isValidFileSize();
    }

    // 2. User Profile Images
    match /users/{userId}/images/profileImage/{allPaths=**} {
      allow read: if true; // Public read
      allow write, delete: if signedIn() && request.auth.uid == userId;
    }

    // 3. User Uploads (Legacy-Fallback)
    match /users/{userId}/uploads/{allPaths=**} {
      allow read: if true; // Public read
      allow write, delete: if isOwner(userId) && isValidFileType() && isValidFileSize();
    }

    // 4. Chat Files
    match /chats/{chatId}/files/{allPaths=**} {
      allow read, write: if signedIn() && isValidFileType() && isValidFileSize();
    }

    // 5. Legal Pages
    match /legal_pages/{type}/{allPaths=**} {
      allow read: if true;
      allow write: if signedIn() && isValidFileType() && isValidFileSize();
    }

    // 6. Analytics
    match /analytics/{userId}/{allPaths=**} {
      allow read, write: if isOwner(userId) && isValidFileType() && isValidFileSize();
    }

    // 7. Public Assets
    match /public/{allPaths=**} {
      allow read: if true;
      allow write: if signedIn() && isValidFileType() && isValidFileSize();
    }
  }
}
```

---

## Wichtige Prinzipien

### ✅ DO's

1. **Avatar-Medien:** Immer `avatars/{avatarId}/...` verwenden
2. **Ownership:** Über Firestore-Dokument prüfen, **nicht** über Storage-Pfad
3. **Timestamps:** Verwende `DateTime.now().millisecondsSinceEpoch` für Eindeutigkeit
4. **Extensions:** Immer korrekte Datei-Endung verwenden (`.jpg`, `.mp4`, `.txt`, etc.)
5. **Content-Type:** Explizit setzen bei `SettableMetadata`

### ❌ DON'Ts

1. **NIEMALS `userId` in Avatar-Pfaden:** `avatars/$uid/$avatarId/...` ist FALSCH!
2. **Keine doppelten IDs im Pfad:** Nicht `avatars/$avatarId/images/${avatarId}_...`
3. **Keine leeren Pfad-Segmente:** `avatars//images` ist ungültig
4. **Keine Sonderzeichen:** Nur alphanumerisch, `_`, `-`, `/`, `.`

---

## Code-Konventionen

### Service-Layer

**`firebase_storage_service.dart`:**
```dart
// Avatar-spezifische Uploads
static Future<List<String>> uploadAvatarImages(
  List<File> imageFiles,
  String avatarId, // ← avatarId als Parameter!
) async {
  // ...
  final path = 'avatars/$avatarId/images/${ts}_$i.jpg';
  // ...
}
```

**`avatar_service.dart`:**
```dart
// Bei Avatar-Erstellung
final url = await FirebaseStorageService.uploadImage(
  images[i],
  customPath: 'avatars/$avatarId/images/${now.millisecondsSinceEpoch}_$i.jpg',
);
```

### Screen-Layer

**`avatar_details_screen.dart`:**
```dart
// Bilder hochladen
final url = await FirebaseStorageService.uploadWithProgress(
  file,
  'images',
  customPath: 'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
  onProgress: (v) { /* ... */ },
);
```

**`playlist_edit_screen.dart`:**
```dart
// Playlist Cover hochladen
final ref = FirebaseStorage.instance.ref().child(
  'avatars/${widget.playlist.avatarId}/playlists/${widget.playlist.id}/cover.jpg',
);
```

**`user_profile_screen.dart`:**
```dart
// User Profile Image hochladen
final ref = _storage.ref(
  'users/${user.uid}/images/profileImage/profile_$timestamp.jpg',
);
```

---

## Fallback-Strategie

Wenn **kein `avatarId` vorhanden** ist (z.B. bei generischen Uploads), verwende:

```dart
'users/${user.uid}/uploads/{images|videos|texts|audio}/${timestamp}_file.ext'
```

**Beispiel:**
```dart
// ✅ Fallback für generische Uploads
final filePath = customPath ?? 
  'users/${user.uid}/uploads/images/${timestamp}_$fileName';
```

---

## Migration von alten Pfaden

### Alte Struktur (DEPRECATED)
```
avatars/{userId}/{avatarId}/images/...  ❌
avatars/{userId}/images/...              ❌
```

### Neue Struktur (CURRENT)
```
avatars/{avatarId}/images/...            ✅
```

### Migration-Script (TODO)
```dart
// Migriere alte Pfade zu neuer Struktur
Future<void> migrateOldPaths() async {
  // 1. Liste alle Dateien unter avatars/{userId}/
  // 2. Identifiziere zugehörigen avatarId aus Firestore
  // 3. Kopiere zu avatars/{avatarId}/
  // 4. Lösche alte Dateien
  // 5. Update Firestore-URLs
}
```

---

## Testing Checklist

Beim Testen von Storage-Uploads:

- [ ] **Console-Logs prüfen:** `📁 Upload-Pfad: ...` sollte korrekte Struktur zeigen
- [ ] **Firebase Console:** Pfade in Storage entsprechen der Dokumentation
- [ ] **Firestore-URLs:** Download-URLs sind gültig und erreichbar
- [ ] **Ownership:** Andere User können keine fremden Dateien überschreiben
- [ ] **File Types:** Nur erlaubte Content-Types (images, videos, audio, text, pdf)
- [ ] **File Size:** Max. 50MB pro Upload

---

## Debugging

### Häufige Fehler

**1. "Permission denied" beim Upload**
- **Ursache:** `userId` im Pfad statt `avatarId`
- **Lösung:** Prüfe, ob `avatars/$avatarId/...` verwendet wird

**2. "File not found" beim Download**
- **Ursache:** Inkonsistente Pfade zwischen Upload und Firestore-URL
- **Lösung:** Prüfe Firestore-Dokument, ob URL mit tatsächlichem Storage-Pfad übereinstimmt

**3. "Invalid file type"**
- **Ursache:** `contentType` nicht gesetzt oder nicht erlaubt
- **Lösung:** Explizit `SettableMetadata(contentType: '...')` setzen

### Debug-Logs aktivieren

```dart
// In firebase_storage_service.dart
debugPrint('📤 uploadImage START: ${imageFile.path}');
debugPrint('✅ User authenticated: ${user.uid}');
debugPrint('📁 Upload-Pfad: $filePath');
debugPrint('✅ uploadImage OK → $downloadUrl');
```

---

## Related Documents

- `brain/incidents/firebase_storage_path_consistency_fix.md` - Fix-Historie (2025-10-02)
- `lib/boot/engineering_notes.dart` - Globaler Engineering-Anker
- `storage.rules` - Aktuelle Firebase Storage Rules

---

## Version History

- **2025-10-02:** Initiale Dokumentation nach Storage-Pfad-Konsistenz-Fix
  - Alle Avatar-Pfade von `avatars/$uid/$avatarId/...` zu `avatars/$avatarId/...` migriert
  - Legacy-Fallback `users/{userId}/uploads/**` hinzugefügt
  - Storage Rules deployed und dokumentiert

