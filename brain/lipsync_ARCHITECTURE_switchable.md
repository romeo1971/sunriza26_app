# Lipsync Architecture - Switchable Implementation

**Stand:** 17.10.2025, 02:30 Uhr  
**Ziel:** Beide Methoden parallel implementieren, per Config umschaltbar

---

## 🎯 **STRATEGIE: Interface-basiert**

Wir erstellen ein **gemeinsames Interface**, das beide Implementierungen (File-based & Streaming) erfüllen!

---

## 📐 **ARCHITECTURE:**

```
┌─────────────────────────────────────┐
│      LipsyncStrategy (Interface)    │
├─────────────────────────────────────┤
│  + Future<void> speak(text, voiceId)│
│  + void stop()                      │
│  + void dispose()                   │
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       │                │
┌──────▼──────┐  ┌─────▼──────────┐
│ FileBased   │  │ StreamingBased │
│ Strategy    │  │ Strategy       │
├─────────────┤  ├────────────────┤
│ - Aktuell   │  │ - WebSocket    │
│ - Einfach   │  │ - Low Latency  │
│ - Stabil    │  │ - Visemes      │
└─────────────┘  └────────────────┘
```

---

## 💻 **CODE IMPLEMENTATION:**

### **1. Interface (Abstract Class)**

```dart
// lib/services/lipsync/lipsync_strategy.dart (NEU)

abstract class LipsyncStrategy {
  /// Spricht den Text mit der angegebenen Stimme
  Future<void> speak(String text, String voiceId);
  
  /// Stoppt die aktuelle Wiedergabe
  void stop();
  
  /// Cleanup
  void dispose();
  
  /// Optional: Viseme-Updates
  Stream<VisemeEvent>? get visemeStream => null;
}

class VisemeEvent {
  final String viseme;
  final int ptsMs;
  final int durationMs;
  
  VisemeEvent({
    required this.viseme,
    required this.ptsMs,
    required this.durationMs,
  });
}
```

---

### **2. File-Based Strategy (Aktuell)**

```dart
// lib/services/lipsync/file_based_strategy.dart (NEU)

class FileBasedStrategy implements LipsyncStrategy {
  final AudioPlayer _player;
  final String _backendUrl;
  
  FileBasedStrategy({
    required String backendUrl,
  }) : _backendUrl = backendUrl,
       _player = AudioPlayer();
  
  @override
  Future<void> speak(String text, String voiceId) async {
    // Aktueller Flow (bleibt gleich!)
    final response = await http.post(
      Uri.parse('$_backendUrl/avatar/chat'),
      body: jsonEncode({'text': text, 'voice_id': voiceId}),
      headers: {'Content-Type': 'application/json'},
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final ttsB64 = data['tts_audio_b64'] as String?;
      
      if (ttsB64 != null) {
        // Decode & Save
        final bytes = base64Decode(ttsB64);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(bytes, flush: true);
        
        // Play
        await _player.setFilePath(file.path);
        await _player.play();
      }
    }
  }
  
  @override
  void stop() {
    _player.stop();
  }
  
  @override
  void dispose() {
    _player.dispose();
  }
}
```

---

### **3. Streaming Strategy (Neu)**

```dart
// lib/services/lipsync/streaming_strategy.dart (NEU)

class StreamingStrategy implements LipsyncStrategy {
  final String _orchestratorUrl;
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;
  
  final StreamController<VisemeEvent> _visemeController = 
      StreamController<VisemeEvent>.broadcast();
  
  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;
  
  StreamingStrategy({
    required String orchestratorUrl,
  }) : _orchestratorUrl = orchestratorUrl;
  
  Future<void> _connect() async {
    if (_channel != null) return;
    
    _channel = WebSocketChannel.connect(
      Uri.parse(_orchestratorUrl),
    );
    
    _audioPlayer = AudioPlayer();
    
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      
      switch (data['type']) {
        case 'audio':
          _handleAudio(data);
          break;
        case 'viseme':
          _handleViseme(data);
          break;
      }
    });
  }
  
  @override
  Future<void> speak(String text, String voiceId) async {
    await _connect();
    
    // Send speak command
    _channel!.sink.add(jsonEncode({
      'type': 'speak',
      'text': text,
      'voice_id': voiceId,
    }));
  }
  
  void _handleAudio(Map<String, dynamic> data) {
    final audioBytes = base64Decode(data['data']);
    // Stream audio chunks (mit audioplayers package)
    _audioPlayer?.play(BytesSource(audioBytes));
  }
  
  void _handleViseme(Map<String, dynamic> data) {
    _visemeController.add(VisemeEvent(
      viseme: data['value'],
      ptsMs: data['pts_ms'],
      durationMs: data['duration_ms'] ?? 100,
    ));
  }
  
  @override
  void stop() {
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    _audioPlayer?.stop();
  }
  
  @override
  void dispose() {
    _channel?.sink.close();
    _audioPlayer?.dispose();
    _visemeController.close();
  }
}
```

---

### **4. Factory mit Config-Switch**

```dart
// lib/services/lipsync/lipsync_factory.dart (NEU)

enum LipsyncMode {
  fileBased,    // Aktuell, stabil
  streaming,    // Neu, low-latency
}

class LipsyncFactory {
  static LipsyncStrategy create({
    required LipsyncMode mode,
    required String backendUrl,
    String? orchestratorUrl,
  }) {
    switch (mode) {
      case LipsyncMode.fileBased:
        return FileBasedStrategy(backendUrl: backendUrl);
        
      case LipsyncMode.streaming:
        if (orchestratorUrl == null) {
          throw ArgumentError('orchestratorUrl required for streaming mode');
        }
        return StreamingStrategy(orchestratorUrl: orchestratorUrl);
    }
  }
}
```

---

### **5. Config (umschaltbar!)**

```dart
// lib/config.dart (ERWEITERN)

class AppConfig {
  // ... existing config ...
  
  // 🔄 LIPSYNC MODE (HIER UMSCHALTEN!)
  static const lipsyncMode = LipsyncMode.fileBased;  // ← DEFAULT: Aktuell
  // static const lipsyncMode = LipsyncMode.streaming;  // ← NEU: Streaming
  
  static const backendUrl = 'https://backend.sunriza26.com';
  static const orchestratorUrl = 'wss://orchestrator.sunriza26.com/lipsync';
}
```

---

### **6. Chat Screen Integration**

```dart
// lib/screens/avatar_chat_screen.dart (ÄNDERN)

class _AvatarChatScreenState extends State<AvatarChatScreen> {
  // ERSETZE:
  // AudioPlayer _player = AudioPlayer();
  
  // MIT:
  late LipsyncStrategy _lipsyncStrategy;
  StreamSubscription<VisemeEvent>? _visemeSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize Strategy
    _lipsyncStrategy = LipsyncFactory.create(
      mode: AppConfig.lipsyncMode,  // ← CONFIG!
      backendUrl: AppConfig.backendUrl,
      orchestratorUrl: AppConfig.orchestratorUrl,
    );
    
    // Listen zu Viseme-Events (nur bei Streaming)
    _visemeSubscription = _lipsyncStrategy.visemeStream?.listen((event) {
      if (_visemeMixer != null) {
        _visemeMixer!.setViseme(event.viseme, 1.0);
        
        // Fade out
        Future.delayed(Duration(milliseconds: event.durationMs), () {
          _visemeMixer!.setViseme(event.viseme, 0.0);
        });
      }
    });
  }
  
  Future<void> _sendMessage(String text) async {
    // ... existing LLM logic ...
    
    // ERSETZE:
    // await _playAudioAtPath(file.path);
    
    // MIT:
    await _lipsyncStrategy.speak(llmResponse, voiceId);
  }
  
  @override
  void dispose() {
    _visemeSubscription?.cancel();
    _lipsyncStrategy.dispose();
    super.dispose();
  }
}
```

---

## 🔄 **UMSCHALTEN (So einfach!):**

### **Option 1: File-Based (Aktuell, stabil)**
```dart
// config.dart
static const lipsyncMode = LipsyncMode.fileBased;
```

**Vorteile:**
- ✅ Funktioniert sofort
- ✅ Keine neuen Dependencies
- ✅ Stabil, getestet
- ✅ Kein Orchestrator nötig

**Nachteile:**
- ⏱️ Langsam (~3-6s bis Audio startet)
- ❌ Keine Visemes (Lippen bewegen sich nicht)

---

### **Option 2: Streaming (Neu, schnell)**
```dart
// config.dart
static const lipsyncMode = LipsyncMode.streaming;
```

**Vorteile:**
- ⚡ SCHNELL (~0.7-1.3s bis Audio startet)
- ✅ Visemes (Lippen bewegen sich!)
- ✅ Bessere UX

**Nachteile:**
- 🏗️ Orchestrator muss laufen
- 💰 +$5-10/Monat
- ⚙️ Mehr Debugging

---

## 📋 **IMPLEMENTATION PLAN:**

### **Phase 1: Interface & File-Based** (1 Tag)
1. ✅ `LipsyncStrategy` Interface erstellen
2. ✅ `FileBasedStrategy` implementieren (aktueller Code!)
3. ✅ `LipsyncFactory` erstellen
4. ✅ Chat-Screen refactoren (Strategy Pattern nutzen)
5. ✅ Testen mit `LipsyncMode.fileBased`

**Ergebnis:** Alles funktioniert **GENAU WIE VORHER**, aber mit sauberem Interface!

---

### **Phase 2: Streaming Implementation** (2-3 Tage)
1. ✅ Orchestrator erweitern (WebSocket Server)
2. ✅ `StreamingStrategy` implementieren
3. ✅ `audioplayers` package hinzufügen (für Chunk-Playback)
4. ✅ Testen mit `LipsyncMode.streaming`

**Ergebnis:** Beide Modes funktionieren, per Config umschaltbar!

---

### **Phase 3: Production Testing** (1 Tag)
1. ✅ A/B Testing: Beide Modes parallel testen
2. ✅ Latency Measurements
3. ✅ User Feedback sammeln
4. ✅ Entscheidung: Welcher Mode wird Default?

---

## 🎯 **VORTEILE DIESER ARCHITECTURE:**

1. ✅ **Zero Risk:** File-Based bleibt funktionsfähig!
2. ✅ **Easy Rollback:** Config ändern → fertig!
3. ✅ **A/B Testing:** Verschiedene User, verschiedene Modes
4. ✅ **Clean Code:** Strategy Pattern, kein Spaghetti-Code
5. ✅ **Future-Proof:** Später WebRTC als 3. Strategy hinzufügen!

---

## 💡 **BONUS: Feature Flags**

```dart
// lib/config.dart (ERWEITERN)

class AppConfig {
  // Dynamisch von Firebase Remote Config laden!
  static Future<LipsyncMode> getLipsyncMode(String userId) async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.fetchAndActivate();
    
    // Feature Flag für Beta-User
    final isBetaUser = remoteConfig.getBool('lipsync_streaming_enabled');
    
    if (isBetaUser) {
      return LipsyncMode.streaming;  // Beta-User bekommen Streaming
    } else {
      return LipsyncMode.fileBased;  // Normale User bekommen File-Based
    }
  }
}
```

**So kannst du:**
- ✅ 10% der User auf Streaming testen
- ✅ Bei Problemen: Instant Rollback via Firebase Console
- ✅ Graduell auf 100% Streaming migrieren

---

## ✅ **FAZIT:**

**JA, wir implementieren BEIDES!**

**Workflow:**
1. Zuerst: Interface + File-Based (Refactoring, 1 Tag)
2. Dann: Streaming implementieren (2-3 Tage)
3. Testen: Beide Modes parallel
4. Entscheiden: Welcher wird Default?

**Umschalten:** Eine Zeile in `config.dart` ändern! 🔄

---

**Letzte Aktualisierung:** 17.10.2025, 02:35 Uhr  
**Status:** BESTE Lösung - flexibel, sicher, sauber!

