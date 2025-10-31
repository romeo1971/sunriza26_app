# Hero Chat System - Implementierung

## Übersicht

Highlights-System für wichtige Chat-Nachrichten mit Icons.

## Features

### ✅ Chat Message Model
- `highlightIcon` - Gewähltes Icon (🐣🔥🍻...)
- `highlightedAt` - Zeitstempel
- `deleteTimerStart` - Timer-Start
- `remainingDeleteSeconds` - Helper für Countdown

### ✅ Icon-Picker Dialog
- **Widget**: `lib/widgets/hero_chat_icon_picker.dart`
- Tap auf Chat-Blase → Dialog erscheint AN der Blase
- Position: Unter Blase, User rechts / Avatar links
- 24 Icons zur Auswahl
- "Icon entfernen" Button wenn bereits gesetzt
- Tap ins Leere → schließt Dialog

### ✅ Chat Message Bubble
- **Widget**: `lib/widgets/chat_message_bubble.dart`
- Tap-Handler für Icon-Dialog
- Zeigt Icon klein unter der Blase (wenn gesetzt)
- Delete-Timer Countdown (klein, oben in Blase)
- Border wenn highlighted

### ✅ Hero Chat Screen
- **Screen**: `lib/screens/hero_chat_screen.dart`
- Background: Hero-Image des Avatars
- Zeigt nur highlighted Nachrichten
- Wischen nach links → zurück zum Chat
- KEIN Room-Leave (bleibt verbunden)

### ✅ Icon-Filter Toggles
- Toggle zwischen "Alle" und "Gefiltert"
- Jedes Icon einzeln an/aus (colored = an, greyscale = aus)
- Anzahl pro Icon

### ✅ Hero Chat FAB
- **Widget**: `lib/widgets/hero_chat_fab_button.dart`
- Position: Oben rechts im Chat
- Zeigt Anzahl der Highlights
- Klick → Hero Chat Screen

## Workflow

```
1. User tappt auf Chat-Blase
2. Icon-Dialog erscheint AN der Blase
3. User wählt Icon (z.B. 🔥)
   → Message wird highlighted
   → Icon erscheint unter der Blase
   → Message wird in Firebase gespeichert

4. User tappt auf Hero Chat FAB (oben rechts)
5. Hero Chat Screen öffnet sich
   → Background: Hero-Image
   → Nur highlighted Messages
   → Filter nach Icons (colored/greyscale)

6. User entfernt Icon in Hero Chat
   → 2-Minuten Timer startet
   → Countdown läuft
   → Nach 120s → Message wird gelöscht
   → User kann neu markieren → Timer stoppt
```

## Integration in avatar_chat_screen.dart

### 1. State hinzufügen:

```dart
// Nach _messages Liste:
final Map<String, Timer> _deleteTimers = {};
```

### 2. Icon-Handler:

```dart
void _handleIconChanged(ChatMessage message, String? icon) {
  setState(() {
    if (icon != null) {
      // Icon setzen
      message.highlightIcon = icon;
      message.highlightedAt = DateTime.now();
      message.deleteTimerStart = null;
      
      // Stoppe laufenden Timer
      _deleteTimers[message.timestamp.toString()]?.cancel();
      _deleteTimers.remove(message.timestamp.toString());
      
    } else {
      // Icon entfernen → Timer starten
      message.deleteTimerStart = DateTime.now();
      
      // 2-Minuten Timer
      _deleteTimers[message.timestamp.toString()] = Timer(
        const Duration(minutes: 2),
        () {
          setState(() {
            _messages.remove(message);
            _deleteTimers.remove(message.timestamp.toString());
          });
          // Aus Firebase löschen
          _deleteMessageFromFirebase(message);
        },
      );
    }
  });
  
  // In Firebase speichern
  _saveMessageToFirebase(message);
}
```

### 3. Hero Chat FAB im AppBar:

```dart
actions: [
  Padding(
    padding: const EdgeInsets.only(right: 16),
    child: HeroChatFabButton(
      highlightCount: _messages.where((m) => m.isHighlighted).length,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HeroChatScreen(
              avatarData: _avatarData!,
              messages: _messages,
              onIconChanged: _handleIconChanged,
            ),
          ),
        );
      },
    ),
  ),
],
```

### 4. Messages rendern:

```dart
// Statt Text/Container für Messages:
ChatMessageBubble(
  message: _messages[index],
  onIconChanged: _handleIconChanged,
)
```

## Firebase Struktur

```
users/{uid}/avatars/{avatarId}/messages/{messageId}
{
  "text": "...",
  "isUser": true/false,
  "timestamp": Timestamp,
  "highlightIcon": "🔥" (optional),
  "highlightedAt": Timestamp (optional),
  "deleteTimerStart": Timestamp (optional)
}
```

## Timer-Logik

1. Icon entfernt → `deleteTimerStart` = jetzt
2. Timer läuft 2 Minuten
3. Jede Sekunde: UI update (Countdown)
4. Nach 120s: Message löschen (lokal + Firebase)
5. Wenn neu markiert → Timer stoppen, `deleteTimerStart` = null

## UI Details

- **Icons**: 24 Emojis
- **Positionierung**: Dialog AN der Blase (Offset)
- **Alignment**: User rechts, Avatar links
- **Timer**: Rot, klein, oben in Blase
- **Hero Chat**: Wischen zurück, Hero-Image Background
- **Filter**: Colored = aktiv, Greyscale = inaktiv

## TODO Integration

Noch zu tun:
- [ ] `_handleIconChanged` in avatar_chat_screen.dart
- [ ] FAB Button in AppBar
- [ ] ChatMessageBubble statt aktuelle Bubble
- [ ] Firebase Save/Load/Delete
- [ ] Timer bei App-Restart fortsetzen

