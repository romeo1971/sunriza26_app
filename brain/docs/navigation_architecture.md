# Navigation-Architektur: Intelligente Zurück-Button Logik

## Problem

Bei komplexen Apps mit mehreren verschachtelten Screens (z.B. Hauptliste → Details → 4 Sub-Bereiche) führt der Standard-Zurück-Button zu verwirrenden Navigation-Stapeln:
- Screens stapeln sich unkontrolliert
- Benutzer landen nach mehreren Klicks in unerwarteten Screens
- Keine klare Hierarchie

## Lösung: Context-basierte Zurück-Navigation

### Konzept

Jeder Screen merkt sich, **von wo** er aufgerufen wurde (`fromScreen` Parameter) und entscheidet basierend darauf, wohin der Zurück-Button führt.

### Implementierung

#### 1. **Parameter-Übergabe**

Alle Sub-Screens erhalten einen optionalen `fromScreen` Parameter:

```dart
class MediaGalleryScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null
  
  const MediaGalleryScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });
}
```

#### 2. **Von Hauptliste aufrufen**

```dart
// avatar_list_screen.dart
Navigator.pushNamed(
  context,
  '/media-gallery',
  arguments: {
    'avatarId': avatar.id,
    'fromScreen': 'avatar-list', // ← WICHTIG!
  },
);
```

#### 3. **Von Details oder Sub-Screens aufrufen**

```dart
// avatar_details_screen.dart oder andere Sub-Screens
Navigator.pushReplacementNamed( // ← pushReplacement statt push!
  context,
  '/media-gallery',
  arguments: {
    'avatarId': avatarId,
    // KEIN fromScreen → null
  },
);
```

**WICHTIG:** `pushReplacementNamed` verhindert Stapel-Bildung zwischen Sub-Screens!

#### 4. **Custom Back-Button Logik**

Jeder Sub-Screen implementiert eine `_handleBackNavigation` Methode:

```dart
void _handleBackNavigation(BuildContext context) async {
  if (widget.fromScreen == 'avatar-list') {
    // Von Hauptliste → zurück zu Hauptliste (Stack komplett löschen)
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/avatar-list',
      (route) => false, // ← Löscht ALLE Screens
    );
  } else {
    // Von Details/Sub-Screens → zurück zu Details
    final avatarService = AvatarService();
    final avatar = await avatarService.getAvatar(widget.avatarId);
    if (avatar != null && context.mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/avatar-details',
        arguments: avatar,
      );
    } else {
      Navigator.pop(context); // Fallback
    }
  }
}
```

#### 5. **AppBar Integration**

```dart
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => _handleBackNavigation(context),
  ),
  // ...
)
```

#### 6. **Details-Screen zurück zu Hauptliste**

Der Details-Screen geht **IMMER** zur Hauptliste zurück:

```dart
// avatar_details_screen.dart
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/avatar-list',
        (route) => false,
      );
    },
  ),
)
```

## Navigation-Flow Beispiel

### Architektur: Sunriza App

```
Meine Avatare (avatar-list)
    ↓
Avatar Details (avatar-details)
    ↓
[Media | Playlists | Moments | Facts] (Sub-Screens)
```

### Flow 1: Von Hauptliste

```
Meine Avatare → Media → Zurück → Meine Avatare ✅
```

**Warum?** `fromScreen: 'avatar-list'` → `pushNamedAndRemoveUntil` löscht Stack komplett

### Flow 2: Von Details zu Sub-Screen

```
Meine Avatare → Avatar Details → Media → Zurück → Avatar Details ✅
```

**Warum?** KEIN `fromScreen` → `pushReplacementNamed` geht zu Details

### Flow 3: Zwischen Sub-Screens wechseln

```
Avatar Details → Media → Playlists → Moments → Zurück → Avatar Details ✅
```

**Warum?** 
- Navigation zwischen Sub-Screens nutzt `pushReplacementNamed` (ersetzt statt stapelt)
- KEIN `fromScreen` → alle führen zu Details zurück
- **NICHT**: Media ← Playlists ← Moments (das wäre falsch!)

### Flow 4: Details zurück zu Hauptliste

```
Meine Avatare → Avatar Details → Zurück → Meine Avatare ✅
```

**Warum?** Details-Screen verwendet `pushNamedAndRemoveUntil` zu `/avatar-list`

## Wichtige Navigator-Methoden

| Methode | Verwendung | Effekt |
|---------|-----------|--------|
| `pushNamed` | Von Hauptliste zu Sub-Screens | Stapelt Screen (für späteres `popUntil`) |
| `pushReplacementNamed` | Zwischen Sub-Screens | Ersetzt aktuellen Screen (kein Stapel!) |
| `pushNamedAndRemoveUntil` | Zurück zu Hauptliste | Löscht kompletten Stack |
| `pop` | Einfacher Zurück | Nur für Dialoge/einfache Fälle |

## Route-Definitionen (main.dart)

```dart
routes: {
  '/avatar-list': (context) => const AvatarListScreen(),
  '/avatar-details': (context) => const AvatarDetailsScreen(),
  '/media-gallery': (context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final avatarId = (args?['avatarId'] as String?) ?? '';
    final fromScreen = args?['fromScreen'] as String?; // ← Parameter extrahieren
    return MediaGalleryScreen(
      avatarId: avatarId,
      fromScreen: fromScreen,
    );
  },
  // ... andere Sub-Screens analog
}
```

## Checkliste für Implementation

- [ ] **Sub-Screens:** `fromScreen` Parameter hinzufügen
- [ ] **Hauptliste:** `fromScreen: 'avatar-list'` bei Navigation übergeben
- [ ] **Sub-Screen Navigation:** `pushReplacementNamed` verwenden (KEIN `fromScreen`)
- [ ] **Back-Button Logik:** `_handleBackNavigation` implementieren
- [ ] **Details-Screen:** `pushNamedAndRemoveUntil` zu Hauptliste
- [ ] **Route-Definitionen:** `fromScreen` Parameter extrahieren

## Vorteile

1. ✅ **Klare Hierarchie:** Benutzer wissen immer, wo sie landen
2. ✅ **Kein Stapel-Chaos:** Sub-Screens ersetzen sich gegenseitig
3. ✅ **Konsistent:** Immer gleicher Flow, egal wie komplex die Navigation
4. ✅ **Skalierbar:** Beliebig viele Sub-Screens möglich
5. ✅ **Testbar:** Logik ist klar nachvollziehbar

## Anti-Patterns (NICHT tun!)

❌ **`popUntil` für Hauptliste:**
```dart
Navigator.popUntil(context, ModalRoute.withName('/avatar-list'));
```
→ Problem: Funktioniert nur, wenn Route im Stack ist

❌ **`pushNamed` zwischen Sub-Screens:**
```dart
Navigator.pushNamed(context, '/playlists', ...); // Von Media zu Playlists
```
→ Problem: Screens stapeln sich unkontrolliert

❌ **`pop()` für komplexe Navigation:**
```dart
Navigator.pop(context); // Von Sub-Screen zu Details
```
→ Problem: Funktioniert nicht, wenn Screen per `pushReplacement` kam

## Anwendung auf andere Apps

Diese Architektur funktioniert für **jede App** mit folgender Struktur:

```
Hauptliste (z.B. Produkte, Projekte, Kontakte)
    ↓
Details (z.B. Produktdetails, Projektübersicht)
    ↓
Sub-Bereiche (z.B. Bewertungen, Aufgaben, Nachrichten)
```

**Beispiele:**
- **E-Commerce:** Produktliste → Produktdetails → [Bewertungen | Ähnliche | Händler]
- **Projektmanagement:** Projekte → Projektdetails → [Aufgaben | Team | Dateien]
- **Social Media:** Profilliste → Profil → [Posts | Followers | Media]

## Zusammenfassung

**Kernprinzip:** Der Zurück-Button führt **immer** zu einem sinnvollen übergeordneten Screen, basierend auf dem Einstiegspunkt des Benutzers.

**3 Navigations-Ebenen:**
1. **Hauptliste** → Details/Sub-Screens (mit `fromScreen`)
2. **Details** → Sub-Screens (ohne `fromScreen`, mit `pushReplacement`)
3. **Sub-Screens** → Zurück zu Details ODER Hauptliste (basierend auf `fromScreen`)

**Dokumentiert:** Oktober 2025 | Sunriza26 App

