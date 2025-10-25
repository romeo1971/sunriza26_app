# Timeline & Scheduler System - Dokumentation

## Übersicht

Das Timeline & Scheduler System steuert, **wann** und **welche** Media Assets (Bilder, Videos, Dokumente, Audio) im Avatar Chat Screen angezeigt werden. Es besteht aus zwei Hauptkomponenten:

1. **Timeline Screen** - Definiert WAS und WIE angezeigt wird
2. **Scheduler Screen** - Definiert WANN angezeigt wird

---

## 1. Timeline Screen (`playlist_timeline_screen.dart`)

### Zweck
Konfiguration der **Reihenfolge**, **Timing** und **Aktivierungsstatus** von Media Assets, die während einer Chat-Session im Avatar Chat Screen erscheinen.

### Hauptfunktionen

#### 1.1 Timeline Items
Jedes Timeline Item repräsentiert ein Media Asset mit folgenden Eigenschaften:

| Eigenschaft | Typ | Beschreibung | Wertebereich |
|------------|-----|-------------|--------------|
| **eindeutigeId** | String | Eindeutige ID (mediaId + timestamp) | - |
| **minDropdown** | int | Verzögerung in Minuten nach Chat-Start | 1-30 Minuten |
| **delaySec** | int | Verzögerung in Sekunden | 60-1800 Sekunden |
| **timeStartzeit** | int | Kumulative Startzeit (Summe aller Vorgänger) | ≥ 0 Sekunden |
| **activity** / **enabled** | bool | ON/OFF Status (wird Asset angezeigt?) | true/false |

#### 1.2 Timeline Konfiguration

| Eigenschaft | Beschreibung |
|------------|-------------|
| **Timeline Loop** | Ob die Timeline nach dem letzten Item neu startet (Wiederholung) |
| **Timeline Enabled** | Master-Schalter: Ob die Timeline überhaupt aktiv ist |

#### 1.3 Funktionen

##### Media Assets hinzufügen
- **Drag & Drop** von Media Assets aus der Asset-Liste in die Timeline
- Assets werden automatisch in die Timeline-Reihenfolge eingefügt
- Jedes Asset erhält automatisch:
  - Eine eindeutige ID
  - Standard-Verzögerung (1 Minute)
  - Status "enabled" (ON)

##### Reihenfolge ändern
- **Reorder** via Drag & Drop innerhalb der Timeline
- Die `timeStartzeit` wird automatisch neu berechnet basierend auf:
  - Position in der Timeline
  - Verzögerung aller Vorgänger

##### Timing konfigurieren
- **Dropdown-Auswahl**: 1-30 Minuten
- Zeigt den **absoluten Anzeigezeitpunkt** nach Chat-Start
- Beispiel:
  - Item 1: Nach 2 Minuten (Duration: 2 Min)
  - Item 2: Nach 5 Minuten (Duration: 3 Min)
  - Item 3: Nach 8 Minuten (Duration: 3 Min)

##### ON/OFF Toggle
- Jedes Item kann individuell aktiviert/deaktiviert werden
- **Grünes Item**: Aktiv (wird angezeigt)
- **Rotes Item**: Inaktiv (wird übersprungen)

##### Loop-Modus
- **Loop ON**: Nach dem letzten Item startet die Timeline von vorne
- **Loop OFF**: Timeline stoppt nach dem letzten Item

---

## 2. Scheduler Screen (`playlist_scheduler_screen.dart`)

### Zweck
Definiert **an welchen Tagen** und **zu welchen Zeiten** die Timeline-Items im Avatar Chat Screen angezeigt werden.

### Scheduler-Modi

#### 2.1 Weekly Schedule (Wöchentlicher Zeitplan)

##### Konfiguration
- **Wochentage**: Montag bis Sonntag (0-6)
- **TimeSlots**: Zeitfenster pro Tag

##### TimeSlots (Zeitfenster)
Standard-Zeitfenster mit Index 0-5:

| Index | Zeitfenster | Beschreibung |
|-------|------------|-------------|
| 0 | Morgens | Früh am Tag |
| 1 | Vormittags | Vor Mittag |
| 2 | Mittags | Um die Mittagszeit |
| 3 | Nachmittags | Nach Mittag |
| 4 | Abends | Am Abend |
| 5 | Nachts | Spät in der Nacht |

##### Beispiel
```dart
{
  1: {TimeSlot(0), TimeSlot(2)}, // Montag: Morgens + Mittags
  3: {TimeSlot(1), TimeSlot(4)}, // Mittwoch: Vormittags + Abends
  5: {TimeSlot(0), TimeSlot(1), TimeSlot(2)}, // Freitag: Morgens + Vormittags + Mittags
}
```

**Bedeutung**: Die Timeline wird nur an den konfigurierten Wochentagen **UND** nur während der ausgewählten Zeitfenster angezeigt.

#### 2.2 Special Schedules (Sondertermine)

##### Zweck
Für besondere Anlässe, Feiertage oder spezielle Events mit festem Datum.

##### Konfiguration

| Eigenschaft | Typ | Beschreibung |
|------------|-----|-------------|
| **startDate** | DateTime | Start-Datum (Timestamp) |
| **endDate** | DateTime | End-Datum (Timestamp) |
| **timeSlots** | Set\<TimeSlot\> | Zeitfenster während des Datumsbereichs |
| **anlass** | String | Beschreibung des Anlasses (optional) |

##### Beispiele

###### Weihnachten
```dart
SpecialSchedule(
  startDate: DateTime(2024, 12, 24).millisecondsSinceEpoch,
  endDate: DateTime(2024, 12, 26).millisecondsSinceEpoch,
  timeSlots: {
    TimeSlot(0), // Morgens
    TimeSlot(2), // Mittags
    TimeSlot(4), // Abends
  },
  anlass: 'Weihnachten'
)
```

###### Produktlaunch Event
```dart
SpecialSchedule(
  startDate: DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch,
  endDate: DateTime(2024, 6, 15, 18, 0).millisecondsSinceEpoch,
  timeSlots: {
    TimeSlot(1), // Vormittags
    TimeSlot(2), // Mittags
    TimeSlot(3), // Nachmittags
  },
  anlass: 'Produktlaunch'
)
```

##### Normalisierung
Sondertermine werden automatisch normalisiert:
- **Ein Eintrag pro Kalendertag** im Datumsbereich
- **Deduplizierte TimeSlots** (keine Duplikate)
- **Sortierte TimeSlots** (0-5)

---

## 3. Integration: Timeline + Scheduler

### Wie funktioniert das Zusammenspiel?

#### Ablauf im Avatar Chat Screen

1. **User öffnet Chat** mit einem Avatar
2. **System prüft**:
   - Gibt es eine aktive Timeline für diesen Avatar?
   - Ist die Timeline enabled?
   - Passt der aktuelle Zeitpunkt zum Scheduler?
     - Wochentag + Zeitfenster (Weekly Schedule)
     - ODER Datum + Zeitfenster (Special Schedule)
3. **Wenn alle Bedingungen erfüllt**:
   - Timeline startet
   - Items werden gemäß `timeStartzeit` angezeigt
   - Nur Items mit `enabled=true` werden gezeigt
4. **Nach letztem Item**:
   - **Loop ON**: Timeline startet von vorne
   - **Loop OFF**: Timeline stoppt

#### Priorität
- **Special Schedules** haben Vorrang vor **Weekly Schedules**
- Wenn ein Special Schedule für das aktuelle Datum existiert, wird der Weekly Schedule ignoriert

---

## 4. Datenstruktur (Firestore)

### Timeline Items
```
avatars/{avatarId}/playlists/{playlistId}/timelineItems/{itemId}
```

**Felder:**
```dart
{
  'eindeutigeId': 'mediaId_timestamp',
  'minDropdown': 5,                    // Anzeigezeitpunkt in Minuten
  'timeStartzeit': 300,                // Kumulative Startzeit in Sekunden
  'delaySec': 300,                     // Verzögerung in Sekunden
  'activity': true,                    // ON/OFF Status
  'timelineAssetsId': 'mediaAssetId',  // Referenz zum Media Asset
  'order': 2,                          // Position in Timeline
}
```

### Playlist
```
avatars/{avatarId}/playlists/{playlistId}
```

**Scheduler-Felder:**
```dart
{
  'name': 'Playlist Name',
  'avatarId': 'avatarId',
  'type': 'weekly',                    // 'weekly' oder 'special'
  
  // Weekly Schedule
  'weeklySchedule': {
    '1': [0, 2],                       // Montag: Morgens, Mittags
    '3': [1, 4],                       // Mittwoch: Vormittags, Abends
  },
  
  // Special Schedules
  'specialSchedules': [
    {
      'startDate': 1735084800000,      // Timestamp
      'endDate': 1735257600000,        // Timestamp
      'timeSlots': [0, 2, 4],          // Zeitfenster-Indices
    }
  ],
  
  // Timeline Settings
  'timelineLoop': true,                // Loop aktiviert?
  'timelineEnabled': true,             // Timeline aktiviert?
}
```

---

## 5. Use Cases

### Use Case 1: Restaurant-Avatar
**Szenario**: Restaurant-Avatar zeigt Tagesmenüs und Specials

**Timeline Setup**:
- Item 1: Willkommensvideo (nach 1 Min)
- Item 2: Frühstückskarte (nach 3 Min)
- Item 3: Mittagsmenü (nach 5 Min)
- Item 4: Abendmenü (nach 8 Min)
- Loop: ON

**Scheduler Setup**:
- **Weekly**: Mo-Fr, Zeitfenster: Morgens, Mittags, Abends
- **Special**: Wochenende (Sa-So) mit erweitertem Brunch-Menü

### Use Case 2: Event-Avatar
**Szenario**: Avatar für Messe/Event zeigt Programm-Highlights

**Timeline Setup**:
- Item 1: Event-Übersicht (nach 2 Min)
- Item 2: Keynote-Info (nach 4 Min)
- Item 3: Workshop-Plan (nach 6 Min)
- Item 4: Networking-Info (nach 8 Min)
- Loop: OFF (einmaliges Durchlaufen)

**Scheduler Setup**:
- **Special**: Nur an Event-Tagen (15.-17. Juni 2024)
- Zeitfenster: Vormittags, Mittags, Nachmittags

### Use Case 3: Feiertags-Kampagne
**Szenario**: Weihnachtskampagne mit Special Content

**Timeline Setup**:
- Item 1: Weihnachts-Video (nach 1 Min)
- Item 2: Special-Angebote (nach 3 Min)
- Item 3: Öffnungszeiten (nach 5 Min)
- Loop: ON

**Scheduler Setup**:
- **Special**: 24.-26. Dezember
- Zeitfenster: Alle (0-5)

---

## 6. Best Practices

### Timeline Design
1. **Erste Minute frei lassen**: User sollte zuerst mit Avatar chatten können
2. **Logische Reihenfolge**: Items sinnvoll aufeinander aufbauen
3. **Loop mit Bedacht**: Nur bei kurzen Timelines (<10 Items)
4. **ON/OFF nutzen**: Saisonale Items deaktivieren statt löschen

### Scheduler Design
1. **Weekly als Default**: Für regelmäßige Inhalte
2. **Special für Events**: Für zeitlich begrenzte Kampagnen
3. **Zeitfenster realistisch wählen**: Zu viele Zeitfenster = User-Overload
4. **Testen**: Scheduler-Logik vor Go-Live testen

### Performance
1. **Timeline-Länge**: Max. 20-30 Items pro Timeline
2. **Asset-Größe**: Videos komprimieren, Bilder optimieren
3. **Preload**: Erste 3 Items sollten schnell laden

---

## 7. Technische Details

### Services
- `PlaylistService`: CRUD für Playlists, Timeline Items, Scheduler
- `MediaService`: Verwaltung von Media Assets

### Models
- `Playlist`: Playlist-Daten inkl. Scheduler
- `PlaylistItem`: Referenz auf Media Asset (deprecated)
- `AvatarMedia`: Media Asset (Bild, Video, Dokument, Audio)
- `TimeSlot`: Zeitfenster-Definition (0-5)
- `SpecialSchedule`: Sondertermin mit Datumsbereich

### Firestore Collections
```
avatars/
  {avatarId}/
    playlists/
      {playlistId}/
        timelineItems/
          {itemId}/
    media/
      {mediaId}/
```

---

## 8. Zusammenfassung

| Komponente | Funktion | Key Features |
|-----------|---------|--------------|
| **Timeline Screen** | Was wird angezeigt? | - Reihenfolge<br>- Timing (1-30 Min)<br>- ON/OFF Toggle<br>- Loop-Modus |
| **Scheduler Screen** | Wann wird angezeigt? | - Weekly Schedule (Wochentage + Zeitfenster)<br>- Special Schedules (Datum + Zeitfenster)<br>- Priorität: Special > Weekly |
| **Chat Integration** | Wie wird angezeigt? | - Automatische Überprüfung<br>- Timeline-Playback<br>- Loop-Support |

---

## 9. Chat Screen Integration & Anzeige

### 9.1 Timeline Item Darstellung

#### Position & Layout
| Eigenschaft | Wert | Beschreibung |
|------------|------|-------------|
| **Position** | Links am Bildrand | Feste Position |
| **Breite** | 20% des Screens | Responsive |
| **Höhe** | Dynamisch | Basierend auf Asset-Typ |
| **Z-Index** | Über Chat-Nachrichten | Overlay-ähnlich |

#### Slide-Animation
Timeline Items sliden **von unten nach oben** in den sichtbaren Bereich und wieder hinaus.

**Timing-Berechnung:**
```
slidingTime = min(3 Minuten, max(1 Minute, nextItemDelay - 1 Minute))

Beispiele:
- Nächstes Item in 2 Min → slidingTime = 1 Min (minimum)
- Nächstes Item in 4 Min → slidingTime = 3 Min (maximum)
- Nächstes Item in 6 Min → slidingTime = 3 Min (maximum)
- Nächstes Item in 1.5 Min → slidingTime = 1 Min (minimum)
```

**Animation-Phasen:**
1. **Slide In** (0-20% der slidingTime): Item slided von unten in den Screen
2. **Display** (20-80% der slidingTime): Item ist vollständig sichtbar
3. **Slide Out** (80-100% der slidingTime): Item slided nach oben aus dem Screen

#### Content-Darstellung

##### Bilder
- **Thumbnail**: Volle Sichtbarkeit
- **Verpixelt/Blur**: Bei nicht gekauften Items
- **Click**: Öffnet Fullsize Overlay

##### Videos
- **Thumbnail**: Erster Frame oder Custom Thumbnail
- **Verpixelt/Blur**: Bei nicht gekauften Items
- **Autoplay**: NEIN (nur Thumbnail)
- **Click**: Öffnet Fullsize Overlay

##### Dokumente (PDF, etc.)
- **Thumbnail**: Erste Seite als Vorschau
- **Verpixelt/Blur**: Bei nicht gekauften Items
- **Click**: Öffnet Fullsize Overlay

##### Audio
- **Cover Thumb**: Bild-Cover (muss implementiert werden!)
- **Fallback**: Generisches Audio-Icon mit Titel
- **Verpixelt/Blur**: Bei nicht gekauften Items
- **Click**: Öffnet Fullsize Overlay mit Audio-Player

### 9.2 Fullsize Overlay

#### Öffnung
- **Trigger**: Click auf Timeline Item
- **Cursor**: Pointer (überall auf dem Item)
- **Animation**: Fade In + Scale Up

#### Inhalt
| Element | Beschreibung |
|---------|-------------|
| **Media** | Verpixelt/Blurred (bis Kauf/Annahme) |
| **Titel** | Asset-Name |
| **Beschreibung** | Optional: Zusatztext |
| **Preis** | "Kostenlos" ODER "X,XX €" ODER "X Credits" |
| **CTA Button** | "Annehmen" (kostenlos) ODER "Kaufen" (Preis > 0) |
| **Close Button** | X oben rechts |

#### Nach Kauf/Annahme
- Blur/Verpixelung wird **sofort** entfernt
- Media wird in voller Qualität angezeigt
- Button ändert sich zu "Herunterladen" (öffnet Moments)

---

## 10. Monetarisierung & Payment System

### 10.1 Pricing Model

#### Preis-Typen
| Typ | Wert | Beschreibung |
|-----|------|-------------|
| **Kostenlos** | 0 € / 0 Credits | User kann sofort annehmen |
| **Geld (EUR)** | > 0 € | Stripe Checkout |
| **Credits** | > 0 Credits | Internes Credit-System |

#### Preiskonfiguration
Pro Timeline Item in Firestore:
```dart
{
  'priceType': 'free' | 'money' | 'credits',
  'priceAmount': 0.00,           // EUR oder Credits
  'currency': 'EUR',             // Bei money
}
```

### 10.2 Payment Flow

#### Free Content (Kostenlos)
```
1. User klickt "Annehmen"
2. Media wird entblurred
3. Original-Datei wird in Moments gespeichert
4. Kein Beleg notwendig
```

#### Paid Content (Geld)
```
1. User klickt "Kaufen"
2. Stripe Checkout öffnet sich
   - Amount: priceAmount
   - Currency: EUR
   - Product: Media Asset Name
3. Nach erfolgreicher Zahlung:
   - Media wird entblurred
   - Original-Datei wird in Moments gespeichert
   - Kaufbeleg wird in Moments/Rechnungen gespeichert
```

#### Credits Content
```
1. User klickt "Kaufen"
2. System prüft:
   - Hat User genug Credits?
   - JA: Credits werden abgezogen
   - NEIN: Error-Dialog ("Nicht genug Credits")
3. Nach erfolgreicher Credit-Zahlung:
   - Media wird entblurred
   - Original-Datei wird in Moments gespeichert
   - Kaufbeleg wird in Moments/Rechnungen gespeichert
```

### 10.3 Stripe Integration

#### Checkout Session
```dart
final session = await stripe.checkoutSessions.create({
  'payment_method_types': ['card'],
  'line_items': [{
    'price_data': {
      'currency': 'eur',
      'product_data': {
        'name': media.originalFileName,
        'description': 'Timeline Media Asset',
        'images': [media.thumbnailUrl],
      },
      'unit_amount': (priceAmount * 100).toInt(), // Cents
    },
    'quantity': 1,
  }],
  'mode': 'payment',
  'success_url': 'app://success?media_id={mediaId}',
  'cancel_url': 'app://cancel',
  'metadata': {
    'userId': userId,
    'avatarId': avatarId,
    'mediaId': mediaId,
    'type': 'timeline_media',
  },
});
```

#### Webhook (Backend)
```dart
// Nach erfolgreicher Zahlung
if (event.type == 'checkout.session.completed') {
  final session = event.data.object;
  final userId = session.metadata['userId'];
  final mediaId = session.metadata['mediaId'];
  
  // 1. Media zu User's Moments hinzufügen
  await addToMoments(userId, mediaId);
  
  // 2. Kaufbeleg erstellen
  await createReceipt(userId, session);
}
```

---

## 11. Moments Integration

### 11.1 Moments Backend Screen
**Existiert bereits im Backend!**

Moments ist der persönliche Bereich des Users für gekaufte/angenommene Timeline Media.

### 11.2 Speicherung

#### WICHTIG: Original-Datei, NICHT Link!
```dart
// ❌ FALSCH: Nur Link speichern
{
  'mediaUrl': 'https://storage.googleapis.com/...',
}

// ✅ RICHTIG: Original-Datei kopieren/duplizieren
{
  'originalFileUrl': 'https://storage.googleapis.com/.../user_copy.jpg',
  'originalFileName': 'media_asset.jpg',
  'fileSize': 2048576,
  'mimeType': 'image/jpeg',
  'purchaseDate': timestamp,
}
```

#### Firestore Struktur
```
users/
  {userId}/
    moments/
      {momentId}/
        - originalFileUrl: String (User's eigene Kopie!)
        - originalFileName: String
        - fileSize: int
        - mimeType: String
        - mediaType: 'image' | 'video' | 'document' | 'audio'
        - purchaseDate: Timestamp
        - priceAmount: double
        - priceCurrency: String
        - fromAvatarId: String (Referenz)
        - fromTimelineId: String (Referenz)
```

#### Storage-Strategie
```
Storage Path für User-Kopie:
users/{userId}/moments/{momentId}/{filename}

Beispiel:
users/user123/moments/mom456/beach_sunset.jpg
```

**Warum Original-Datei?**
- User behält Asset auch wenn Timeline/Avatar gelöscht wird
- Keine Abhängigkeit von Avatar-Owner
- Volle Download-Rechte

### 11.3 Moments Reiter

#### Übersicht
```
┌─────────────────────────────────────┐
│           Meine Moments              │
├─────────────────────────────────────┤
│  [Alle] [Bilder] [Videos] [Docs]   │
│  [Audio] [Rechnungen]               │
├─────────────────────────────────────┤
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │ Img1 │  │ Vid1 │  │ Doc1 │      │
│  └──────┘  └──────┘  └──────┘      │
│   5.99€     12.99€    Free          │
└─────────────────────────────────────┘
```

#### Rechnungen Reiter
```
┌─────────────────────────────────────┐
│            Rechnungen                │
├─────────────────────────────────────┤
│ Datum      | Artikel        | Preis │
│ 25.10.2024 | Beach Sunset   | 5.99€ │
│ 24.10.2024 | Product Video  | 12.99€│
│ 23.10.2024 | Brochure PDF   | Free  │
├─────────────────────────────────────┤
│ [Download Rechnung] [Als PDF]       │
└─────────────────────────────────────┘
```

### 11.4 Funktionen in Moments

#### Download
- **Button**: "Herunterladen"
- **Action**: Original-Datei wird heruntergeladen
- **Format**: Original-Format (keine Konvertierung)

#### Ansehen/Anhören
- **Bilder**: Fullscreen Image Viewer
- **Videos**: Inline Video Player
- **Dokumente**: PDF Viewer / Download
- **Audio**: Audio Player mit Cover

#### Teilen (Optional)
- **Social Media**: Direkt teilen
- **Link**: Teilen-Link generieren (nur für User sichtbar)

---

## 12. Audio Cover Thumb (TODO)

### 12.1 Problem
Audio-Dateien haben keine visuelle Repräsentation.

### 12.2 Lösung: Cover Thumb
Jedes Audio-Asset bekommt ein **Cover-Bild** (wie bei Musik-Alben).

#### Firestore Erweiterung
```dart
AvatarMedia (Audio) {
  ...
  'coverThumbUrl': String?,        // URL zum Cover-Bild
  'coverOriginalFileName': String?, // Original-Dateiname
}
```

#### Upload-Flow
1. User wählt Audio-Datei
2. System fragt: "Cover-Bild auswählen?" (optional)
3. User wählt Bild ODER System generiert Default-Cover
4. Cover wird hochgeladen zu `media/{mediaId}/cover_thumb.jpg`

#### Default-Cover Generierung
Wenn kein Cover hochgeladen:
```dart
// Generiere Cover mit:
- Audio-Icon (🎵)
- Titel des Audio-Assets
- Farb-Gradient (GMBC)
- Dauer (z.B. "3:45")
```

#### Darstellung
```
┌─────────────┐
│             │
│   🎵 3:45   │  ← Generiertes Cover
│  Song Name  │
│             │
└─────────────┘
```

---

## 13. Implementierungs-Roadmap

### Phase 1: Chat Screen Integration
- [ ] Timeline Item Loader (lädt aktive Timeline)
- [ ] Sliding Animation System (1-3 Min)
- [ ] Left-Sidebar Container (20% Breite)
- [ ] Blur/Verpixel Filter für nicht gekaufte Items

### Phase 2: Overlay & Interaction
- [ ] Fullsize Overlay Component
- [ ] Cursor Pointer auf Items
- [ ] Click Handler
- [ ] Close/Back Navigation

### Phase 3: Payment Integration
- [ ] Stripe Checkout Integration
- [ ] Credits Payment System
- [ ] Free Content Flow (Annehmen)
- [ ] Payment Success Handling

### Phase 4: Moments Integration
- [ ] Original-Datei Kopier-System (Storage)
- [ ] Moments Firestore Struktur
- [ ] Moments Screen (Übersicht)
- [ ] Rechnungen Reiter
- [ ] Download-Funktionalität

### Phase 5: Audio Cover Thumb
- [ ] Cover Thumb Upload UI
- [ ] Cover Thumb Storage
- [ ] Default Cover Generator
- [ ] Audio Player mit Cover

### Phase 6: Testing & Polish
- [ ] Edge Cases testen (Timeline Loop, Payment Failures)
- [ ] Performance Optimierung (Lazy Loading)
- [ ] UI/UX Polish (Animationen, Transitions)

---

## 14. Technische Spezifikationen

### 14.1 Sliding Animation
```dart
class TimelineItemSlider extends StatefulWidget {
  final AvatarMedia media;
  final Duration slidingTime;
  final bool isBlurred;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: slidingTime,
      curve: Curves.easeInOut,
      bottom: _calculateBottomPosition(),
      left: 0,
      width: MediaQuery.of(context).size.width * 0.2,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: _buildMediaCard(),
        ),
      ),
    );
  }
  
  double _calculateBottomPosition() {
    // Phase 1: Slide In (0-20%)
    // Phase 2: Display (20-80%)
    // Phase 3: Slide Out (80-100%)
    final progress = _animationProgress;
    if (progress < 0.2) {
      return lerp(-200, 100, progress / 0.2); // Slide In
    } else if (progress < 0.8) {
      return 100; // Display
    } else {
      return lerp(100, MediaQuery.of(context).size.height, 
                  (progress - 0.8) / 0.2); // Slide Out
    }
  }
}
```

### 14.2 Blur Filter
```dart
Widget _buildBlurredMedia(AvatarMedia media) {
  return ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
    child: Image.network(media.url),
  );
}
```

### 14.3 Payment Service
```dart
class TimelinePaymentService {
  Future<bool> purchaseWithMoney(String mediaId, double amount) async {
    final session = await _createStripeSession(mediaId, amount);
    final result = await _openStripeCheckout(session);
    if (result.success) {
      await _addToMoments(mediaId);
      await _createReceipt(mediaId, amount);
      return true;
    }
    return false;
  }
  
  Future<bool> purchaseWithCredits(String mediaId, int credits) async {
    final hasEnough = await _checkCredits(credits);
    if (!hasEnough) throw InsufficientCreditsException();
    
    await _deductCredits(credits);
    await _addToMoments(mediaId);
    await _createReceipt(mediaId, credits);
    return true;
  }
  
  Future<bool> acceptFree(String mediaId) async {
    await _addToMoments(mediaId);
    return true;
  }
}
```

---

**Version**: 2.0  
**Stand**: Oktober 2024  
**Autoren**: Sunriza Development Team

