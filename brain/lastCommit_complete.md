# ERFOLGREICHE Implementierungen: Hero Images & Timeline Features

**Datum:** 11. Oktober 2025  
**Branch:** main  
**Status:** ✅ Erfolgreich committed

---

## 📋 Commit-Details: 12 Dateien geändert

### Hauptdatei
- `lib/screens/avatar_details_screen.dart` - Timeline-UI & Sofort-Speicherung

### Weitere betroffene Dateien
- `lib/widgets/media_purchase_dialog.dart`
- `lib/services/media_purchase_service.dart`
- `firestore.rules`
- `lib/screens/avatar_chat_screen.dart`
- `lib/screens/media_gallery_screen.dart`
- Brain-Dokumentationen (go_live, firebase, domain)

---

## 🎯 Erfolgreich Implementierte Features

### 1. Hero Image Toggle-System (Grid/List View)

#### Toggle-Navigation
**Position:** Top-Right Navigation  
**Icons:**
- `Icons.view_headline` - Listenansicht (wenn Grid aktiv)
- `Icons.window` - Grid-Ansicht (wenn List aktiv)

**Styling:**
- Aktiv: GMBC Gradient Background + weißes Icon
- Inaktiv: GMBC Gradient Icon + transparenter BG
- Kein BorderRadius
- Hover: GMBC-Mix Color mit alpha 0.12

```dart
// Toggle View-Mode
SizedBox(
  height: 35,
  width: 35,
  child: TextButton(
    onPressed: () {
      final wasListView = _heroViewMode == 'list';
      setState(() {
        _heroViewMode = _heroViewMode == 'grid' ? 'list' : 'grid';
      });
      if (wasListView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_heroScrollController.hasClients) {
            _heroScrollController.jumpTo(0);
          }
        });
      }
    },
    style: ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: const WidgetStatePropertyAll(Size(35, 35)),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.hovered)) {
          final mix = Color.lerp(AppColors.magenta, AppColors.lightBlue, 0.5)!;
          return mix.withValues(alpha: 0.12);
        }
        return null;
      }),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    child: (_heroViewMode == 'list')
        ? Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: Theme.of(context).extension<AppGradients>()!.magentaBlue,
            ),
            child: const Icon(Icons.view_headline, size: 20),
          )
        : ShaderMask(
            shaderCallback: (bounds) {
              return Theme.of(context)
                  .extension<AppGradients>()!
                  .magentaBlue
                  .createShader(bounds);
            },
            child: const Icon(Icons.window, size: 22, color: Colors.white),
          ),
  ),
)
```

---

### 2. Kachel-Ansicht (Grid View)

#### Layout
- **Linke Seite:** Große Hero-Image Vorschau (223px Höhe, 9:16 Ratio)
- **Rechte Seite:** Horizontal scrollbare Kacheln

#### Kachel-Spezifikationen
```dart
const double leftH = 223.0;  // Image-Höhe
final double leftW = leftH * (9 / 16);  // ~125px Breite
```

#### Kachel-Features
- **Klick-Funktion:** Setzt Bild als Hero (verschiebt zu Position 0)
- **Auto-Scroll:** Springt zu Position 0 nach Hero-Änderung
- **Scroll-Fix:** `ValueKey(_imageUrls[0])` für kompletten Rebuild
- **Cursor:** `SystemMouseCursors.click` (außer Hero-Image)
- **Name:** Original-Dateiname unter Bild

#### Scroll-Logik (wichtig!)
```dart
// ValueKey zwingt kompletten Rebuild bei Hero-Änderung
ListView.builder(
  key: ValueKey(_imageUrls.isNotEmpty ? _imageUrls[0] : 'empty'),
  controller: _heroScrollController,
  scrollDirection: Axis.horizontal,
  itemCount: _imageUrls.length,
  // ...
)

// Bei Hero-Änderung durch Klick
GestureDetector(
  onTap: () async {
    if (isHero || index == 0) return;
    setState(() {
      final item = _imageUrls.removeAt(index);
      _imageUrls.insert(0, item);
      _profileImageUrl = _imageUrls[0];
    });
    await _saveTimelineData();
  },
)
```

---

### 3. Listen-Ansicht (List View)

#### Layout-Struktur
```
┌─────────────────────────────────────────┐
│ [Loop/Ende]  [ON/OFF]                   │ ← Toggles
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ 🖼️ 00:00 - 15:30        👁️         │ │ ← Hero
│ │    [30 min ▼]                       │ │
│ │    hero_image.jpg           ⋮⋮      │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ 🖼️ 01:30                 👁️         │ │ ← Bild 2
│ │    [5 min ▼]                        │ │
│ │    beach_sunset.jpg         ⋮⋮      │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

#### Höhe & Dimensionen
- **Container-Höhe:** 223px (gleich wie Grid View)
- **List-Item-Höhe:** 72px
- **Thumbnail:** 72px Höhe, 9:16 Ratio Breite

#### Toggle-Leiste (ÜBER der Liste)

##### Loop/Ende Toggle
```dart
SizedBox(
  width: 90,  // Fixed width - verhindert "Springen"
  child: InkWell(
    onTap: () {
      setState(() => _isImageLoopMode = !_isImageLoopMode);
      _saveTimelineData();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _isImageLoopMode ? AppColors.primaryGreen : Colors.white,
        border: Border.all(
          color: _isImageLoopMode ? AppColors.primaryGreen : Colors.white,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isImageLoopMode ? Icons.loop : Icons.stop_circle_outlined,
            size: 16,
            color: _isImageLoopMode ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 4),
          Text(
            _isImageLoopMode ? 'Loop' : 'Ende',
            style: TextStyle(
              color: _isImageLoopMode ? Colors.white : Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  ),
)
```

##### ON/OFF Toggle (Timeline)
```dart
SizedBox(
  width: 80,  // Fixed width
  child: InkWell(
    onTap: () {
      setState(() => _isTimelineEnabled = !_isTimelineEnabled);
      _saveTimelineData();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _isTimelineEnabled ? AppColors.primaryGreen : Colors.white,
        border: Border.all(
          color: _isTimelineEnabled ? AppColors.primaryGreen : Colors.white,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isTimelineEnabled ? Icons.play_circle_outline : Icons.pause_circle_outline,
            size: 16,
            color: _isTimelineEnabled ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 4),
          Text(
            _isTimelineEnabled ? 'ON' : 'OFF',
            style: TextStyle(
              color: _isTimelineEnabled ? Colors.white : Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  ),
)
```

**Logik:**
- OFF: Zeigt nur Hero-Image (statisch)
- ON: Spielt Playlist ab (nur aktive Bilder)

#### Listen-Einträge (3 Reihen)

##### Reihe 1: Zeit + Auge-Icon
```dart
Row(
  children: [
    Expanded(
      child: Text(
        isHero ? '00:00 - ${_getTotalEndTime()}' : _getImageStartTime(index),
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ),
    if (!isHero)
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () async {
            await _showExplorerInfoDialog();  // Beim ersten Mal
            setState(() {
              final currentVisible = _imageExplorerVisible[url] ?? false;
              _imageExplorerVisible[url] = !currentVisible;
            });
          },
          child: (_imageExplorerVisible[url] ?? false)
              ? ShaderMask(
                  shaderCallback: (bounds) => Theme.of(context)
                      .extension<AppGradients>()!
                      .magentaBlue
                      .createShader(bounds),
                  child: const Icon(Icons.visibility, size: 20, color: Colors.white),
                )
              : const Icon(Icons.visibility_off, size: 20, color: Colors.grey),
        ),
      ),
  ],
)
```

**Auge-Icon Zweck:** Explorer-Sichtbarkeit (NICHT Timeline!)

##### Reihe 2: Minuten-Dropdown
```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: Colors.black.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(4),
  ),
  child: DropdownButton<int>(
    value: ((_imageDurations[url] ?? 60) ~/ 60).clamp(1, 30),
    isDense: true,
    underline: const SizedBox.shrink(),
    dropdownColor: Colors.black87,
    style: const TextStyle(color: Colors.white, fontSize: 11),
    items: List.generate(30, (i) => i + 1)
        .map((min) => DropdownMenuItem(
              value: min,
              child: Text('${min} min'),
            ))
        .toList(),
    onChanged: (newMin) {
      if (newMin != null) {
        setState(() => _imageDurations[url] = newMin * 60);
        _saveTimelineData();  // SOFORT speichern
      }
    },
  ),
)
```

##### Reihe 3: Name + Drag-Handle
```dart
Row(
  children: [
    Expanded(
      child: Text(
        imageName,
        style: TextStyle(
          color: isHero ? Colors.white : (_imageActive[url] ?? true) ? Colors.white : Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ),
    // Drag-Handle AUSSEN (außerhalb der Row)
  ],
)

// Drag-Handle
ReorderableDragStartListener(
  index: index,
  child: MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Container(
      height: listItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: const Icon(Icons.drag_indicator, color: Colors.white70, size: 24),
    ),
  ),
)
```

#### Thumbnail Click-Funktion
```dart
MouseRegion(
  cursor: isHero ? SystemMouseCursors.basic : SystemMouseCursors.click,
  child: GestureDetector(
    onTap: isHero ? null : () {
      setState(() {
        final currentActive = _imageActive[url] ?? true;
        _imageActive[url] = !currentActive;
      });
      _saveTimelineData();
    },
    child: ClipRRect(
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(6),
        right: Radius.zero,
      ),
      child: SizedBox(
        width: listItemHeight * 9 / 16,
        height: listItemHeight,
        child: Image.network(url, fit: BoxFit.cover),
      ),
    ),
  ),
)
```

**Zweck:** Toggle Timeline aktiv/inaktiv (NICHT Explorer!)

#### Background-Gradient
- **Hero-Image:** GMBC Gradient (aus Theme)
- **Aktiv (Timeline):** Grüner Gradient (0.3→0.15 alpha)
- **Inaktiv:** Transparent

---

### 4. Timeline-Logik & Berechnungen

#### Zeit-Berechnung
```dart
String _getImageStartTime(int index) {
  int totalSeconds = 0;
  for (int i = 0; i < index; i++) {
    final url = _imageUrls[i];
    // Nur AKTIVE Bilder zählen
    if (_imageActive[url] ?? true) {
      totalSeconds += _imageDurations[url] ?? 60;
    }
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _getTotalEndTime() {
  int totalSeconds = 0;
  for (final url in _imageUrls) {
    if (_imageActive[url] ?? true) {
      totalSeconds += _imageDurations[url] ?? 60;
    }
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
```

#### Hero-Image Auto-Update
```dart
onReorder: (oldIndex, newIndex) async {
  if (oldIndex < newIndex) newIndex--;
  setState(() {
    final item = _imageUrls.removeAt(oldIndex);
    _imageUrls.insert(newIndex, item);

    // Fall 1: Anderes Bild auf Pos 0 → wird Hero
    if (newIndex == 0 && item != _profileImageUrl) {
      _profileImageUrl = item;
    }

    // Fall 2: Hero von Pos 0 weg → neues erstes Bild wird Hero
    if (oldIndex == 0 && item == _profileImageUrl && _imageUrls.isNotEmpty) {
      _profileImageUrl = _imageUrls[0];
    }
  });
  await _saveTimelineData();
}
```

---

### 5. Firebase Integration

#### Timeline-Daten-Struktur
```javascript
avatars/{avatarId} {
  imageUrls: [url1, url2, ...],
  avatarImageUrl: heroImageUrl,
  imageTimeline: {
    durations: {
      url1: 120,  // Sekunden
      url2: 300,
      // ...
    },
    loopMode: true,
    enabled: true,
    active: {
      url1: true,
      url2: false,
      // ...
    }
  }
}
```

#### Speicher-Funktion
```dart
Future<void> _saveTimelineData() async {
  if (_avatarData == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('avatars')
        .doc(_avatarData!.id)
        .update({
      'imageUrls': _imageUrls,
      'avatarImageUrl': _profileImageUrl,
      'imageTimeline': {
        'durations': _imageDurations,
        'loopMode': _isImageLoopMode,
        'enabled': _isTimelineEnabled,
        'active': _imageActive,
      },
    });
  } catch (e) {
    debugPrint('❌ Fehler beim Speichern der Timeline-Daten: $e');
  }
}
```

#### Lade-Funktion
```dart
Future<void> _loadTimelineData(String avatarId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('avatars')
        .doc(avatarId)
        .get();
    if (doc.exists && doc.data() != null) {
      final timeline = doc.data()!['imageTimeline'] as Map<String, dynamic>?;
      if (timeline != null) {
        // Durations laden
        final durationsMap = timeline['durations'] as Map<String, dynamic>?;
        if (durationsMap != null) {
          _imageDurations.clear();
          durationsMap.forEach((key, value) {
            if (value is int) _imageDurations[key] = value;
          });
        }
        
        // LoopMode & Enabled
        _isImageLoopMode = timeline['loopMode'] ?? true;
        _isTimelineEnabled = timeline['enabled'] ?? true;
        
        // Active Status
        final activeMap = timeline['active'] as Map<String, dynamic>?;
        if (activeMap != null) {
          _imageActive.clear();
          activeMap.forEach((key, value) {
            if (value is bool) _imageActive[key] = value;
          });
        }
      }
    }
  } catch (e) {
    debugPrint('❌ Fehler beim Laden: $e');
  }
}
```

#### Original-Dateinamen
```javascript
avatars/{avatarId}/media/{fileName} {
  url: downloadUrl,
  originalFileName: "beach_sunset.jpg",
  type: "image",
  uploadedAt: timestamp
}
```

```dart
Future<void> _loadMediaOriginalNames(String avatarId) async {
  try {
    final mediaSnapshot = await FirebaseFirestore.instance
        .collection('avatars')
        .doc(avatarId)
        .collection('media')
        .get();

    for (final doc in mediaSnapshot.docs) {
      final data = doc.data();
      if (data.containsKey('url') && data.containsKey('originalFileName')) {
        _mediaOriginalNames[data['url']] = data['originalFileName'];
      }
    }
  } catch (e) {
    debugPrint('❌ Fehler: $e');
  }
}
```

#### Sofort-Speicherung
**WICHTIG:** Alle Timeline-Änderungen werden SOFORT gespeichert (kein `_isDirty`):

- ✅ Loop/Ende Toggle
- ✅ ON/OFF Toggle
- ✅ Minuten-Dropdown
- ✅ Bild-Klick (aktiv/inaktiv)
- ✅ Drag & Drop Reorder
- ✅ Hero-Image Änderung

---

### 6. Chat-Integration (avatar_chat_screen.dart)

#### State-Variablen
```dart
String? _currentBackgroundImage;
Timer? _imageTimer;
int _currentImageIndex = 0;
List<String> _imageUrls = [];
List<String> _activeImageUrls = [];
Map<String, int> _imageDurations = {};
Map<String, bool> _imageActive = {};
bool _isImageLoopMode = true;
bool _isTimelineEnabled = true;
```

#### Lade-Funktion
```dart
Future<void> _loadAndStartImageTimeline(String avatarId) async {
  final doc = await FirebaseFirestore.instance
      .collection('avatars')
      .doc(avatarId)
      .get();

  if (doc.exists && doc.data() != null) {
    final data = doc.data()!;
    _imageUrls = List<String>.from(data['imageUrls'] ?? []);
    
    final timeline = data['imageTimeline'] as Map<String, dynamic>?;
    if (timeline != null) {
      // Durations laden
      final durationsMap = timeline['durations'] as Map<String, dynamic>?;
      if (durationsMap != null) {
        _imageDurations.clear();
        durationsMap.forEach((key, value) {
          if (value is int) _imageDurations[key] = value;
        });
      }
      
      _isImageLoopMode = timeline['loopMode'] ?? true;
      _isTimelineEnabled = timeline['enabled'] ?? true;
      
      // Active Status
      final activeMap = timeline['active'] as Map<String, dynamic>?;
      if (activeMap != null) {
        _imageActive.clear();
        activeMap.forEach((key, value) {
          if (value is bool) _imageActive[key] = value;
        });
      }
    }

    // Filtere aktive Bilder (Hero ist IMMER aktiv)
    _activeImageUrls = _imageUrls
        .asMap()
        .entries
        .where((entry) {
          final index = entry.key;
          final url = entry.value;
          final isHero = index == 0;
          final isActive = isHero || (_imageActive[url] ?? true);
          return isActive;
        })
        .map((entry) => entry.value)
        .toList();

    // Starte Timeline
    if (_isTimelineEnabled && _activeImageUrls.isNotEmpty) {
      _currentImageIndex = 0;
      _currentBackgroundImage = _activeImageUrls[0];
      precacheImage(NetworkImage(_activeImageUrls[0]), context);
      _startImageTimer();
    } else if (_imageUrls.isNotEmpty) {
      _currentBackgroundImage = _imageUrls[0];
      precacheImage(NetworkImage(_imageUrls[0]), context);
    }
  }
}
```

#### Timer-Funktion
```dart
void _startImageTimer() {
  _imageTimer?.cancel();
  if (_activeImageUrls.isEmpty || !_isTimelineEnabled) return;

  final currentUrl = _activeImageUrls[_currentImageIndex];
  final duration = Duration(seconds: _imageDurations[currentUrl] ?? 60);

  // VORLADEN: Nächstes Bild in Cache laden
  final nextIndex = (_currentImageIndex + 1) % _activeImageUrls.length;
  if (nextIndex < _activeImageUrls.length) {
    final nextUrl = _activeImageUrls[nextIndex];
    precacheImage(NetworkImage(nextUrl), context);
  }

  _imageTimer = Timer(duration, () {
    if (!mounted) return;

    int nextImageIndex = _currentImageIndex + 1;

    // Loop oder Ende?
    if (nextImageIndex >= _activeImageUrls.length) {
      if (_isImageLoopMode) {
        nextImageIndex = 0;
      } else {
        _imageTimer?.cancel();
        return;
      }
    }

    setState(() {
      _currentImageIndex = nextImageIndex;
      _currentBackgroundImage = _activeImageUrls[_currentImageIndex];
    });

    _startImageTimer();
  });
}
```

#### Background-Rendering
```dart
@override
Widget build(BuildContext context) {
  return Stack(
    children: [
      // Background Image
      if (_currentBackgroundImage != null)
        Positioned.fill(
          child: Image.network(_currentBackgroundImage!, fit: BoxFit.cover),
        ),
      // Chat-Content darüber
    ],
  );
}
```

---

### 7. Explorer-Info-Dialog

#### Trigger-Logik
```dart
Future<void> _showExplorerInfoDialog({bool forceShow = false}) async {
  final prefs = await SharedPreferences.getInstance();
  final hasSeenInfo = prefs.getBool('hasSeenExplorerInfo') ?? false;

  // forceShow: true → Info-Button (immer zeigen)
  // forceShow: false → Auge-Klick (nur beim ersten Mal)
  if (!forceShow && hasSeenInfo) return;

  bool dontShowAgain = false;

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Stack(
          children: [
            const Center(
              child: Text(
                'Startseiten-Galerie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  WidgetSpan(
                    child: ShaderMask(
                      shaderCallback: (bounds) => Theme.of(context)
                          .extension<AppGradients>()!
                          .magentaBlue
                          .createShader(bounds),
                      child: const Text(
                        'Aktivierte Bilder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(
                    text: ' rotieren auf deiner Startseite im 2-Sekunden-Takt.\n\n'
                        'Das verhindert schnelles Swipen und motiviert Besucher, '
                        'sich deine Galerie anzusehen.\n\n'
                        'Mehr Bilder = mehr Interesse!',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Großes Auge-Icon
            ShaderMask(
              shaderCallback: (bounds) => Theme.of(context)
                  .extension<AppGradients>()!
                  .magentaBlue
                  .createShader(bounds),
              child: const Icon(Icons.visibility, size: 125, color: Colors.white),
            ),
            const SizedBox(height: 24),
            // Checkbox
            InkWell(
              onTap: () {
                setDialogState(() => dontShowAgain = !dontShowAgain);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      gradient: dontShowAgain
                          ? Theme.of(context).extension<AppGradients>()!.magentaBlue
                          : null,
                      border: Border.all(
                        color: dontShowAgain ? Colors.transparent : Colors.grey,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: dontShowAgain
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Diesen Dialog nicht mehr anzeigen',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () async {
                if (dontShowAgain) {
                  await prefs.setBool('hasSeenExplorerInfo', true);
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => Theme.of(context)
                    .extension<AppGradients>()!
                    .magentaBlue
                    .createShader(bounds),
                child: const Text(
                  'Verstanden',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

#### Info-Button (Manuelle Trigger)
```dart
// In _buildHeroMediaNav
Padding(
  padding: const EdgeInsets.only(right: 8),
  child: SizedBox(
    height: 35,
    width: 35,
    child: IconButton(
      onPressed: () async {
        await _showExplorerInfoDialog(forceShow: true);
      },
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.info_outline, size: 20, color: Colors.white70),
    ),
  ),
),
```

---

### 8. Upload-System

#### Upload-Limit
```dart
if (_imageUrls.length >= 30) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Maximal 30 Bilder erlaubt'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
```

#### Crop & Upload
```dart
Future<void> _uploadCroppedImage(Uint8List croppedBytes) async {
  if (_avatarData == null) return;

  try {
    setState(() => _isUploading = true);

    // 1. Upload zu Storage
    final fileName = 'avatar_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('avatars/${_avatarData!.id}/images/$fileName');

    final uploadTask = storageRef.putData(
      croppedBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    // 2. Füge URL zur Liste hinzu
    setState(() {
      _imageUrls.add(downloadUrl);
      _imageDurations[downloadUrl] = 60;  // 1 Minute initial
      _imageActive[downloadUrl] = false;   // INAKTIV initial
    });

    // 3. Speichere in Firestore
    await _avatarService.updateAvatar(_avatarData!.id, {
      'imageUrls': _imageUrls,
    });

    // 4. Speichere Timeline
    await _saveTimelineData();

    // 5. Speichere originalFileName
    await FirebaseFirestore.instance
        .collection('avatars')
        .doc(_avatarData!.id)
        .collection('media')
        .doc(fileName)
        .set({
      'url': downloadUrl,
      'originalFileName': fileName,
      'type': 'image',
      'uploadedAt': FieldValue.serverTimestamp(),
    });

    // 6. Lade Namen neu
    await _loadMediaOriginalNames(_avatarData!.id);

  } catch (e) {
    debugPrint('Upload-Fehler: $e');
  } finally {
    setState(() => _isUploading = false);
  }
}
```

---

## 🔧 Technische Herausforderungen & Lösungen

### Problem: Scroll springt nicht zu Position 0
**Lösung:** `ValueKey` auf ListView.builder

```dart
ListView.builder(
  key: ValueKey(_imageUrls.isNotEmpty ? _imageUrls[0] : 'empty'),
  // ... zwingt kompletten Rebuild
)
```

### Problem: Dropdown-Wert außerhalb Range
**Lösung:** `.clamp(1, 30)`

```dart
value: ((_imageDurations[url] ?? 60) ~/ 60).clamp(1, 30),
```

### Problem: Schwarzer Screen zwischen Bildern
**Lösung:** `precacheImage` im Timer

```dart
final nextIndex = (_currentImageIndex + 1) % _activeImageUrls.length;
if (nextIndex < _activeImageUrls.length) {
  final nextUrl = _activeImageUrls[nextIndex];
  precacheImage(NetworkImage(nextUrl), context);
}
```

---

## ✅ Status & Erfolgskriterien

**ALLE ERFÜLLT:**
- ✅ Hero Image Toggle (Grid/List)
- ✅ Timeline mit Loop/Ende
- ✅ ON/OFF Global Toggle
- ✅ Drag & Drop Sorting
- ✅ Auto Hero-Update
- ✅ Sofort-Speicherung
- ✅ Explorer-Info-Dialog
- ✅ Image Preloading
- ✅ Original-Dateinamen
- ✅ Git Commit erfolgreich

---

**ENDE DER DOKUMENTATION**

*Erstellt am: 11. Oktober 2025*  
*Status: ✅ ERFOLGREICH IMPLEMENTIERT*
