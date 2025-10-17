# Lipsync - FINALE ENTSCHEIDUNG (keine Tageslaune!)

**Stand:** 17.10.2025, 02:15 Uhr  
**Dokumentiert von:** AI Assistant (nach Realitätscheck)

---

## 🔍 **REALITÄT CHECK - WAS IST AKTUELL IMPLEMENTIERT:**

### **Audio-Playback (AKTUELL):**
```dart
// avatar_chat_screen.dart, Zeile 2059
Future<void> _playAudioAtPath(String path) async {
  await _player.stop();
  await _player.setFilePath(path);  // ← LOKALE MP3-Datei!
  await _player.play();
}
```

**FAKT:** Audio wird als **VOLLSTÄNDIGE MP3-Datei** abgespielt, **NICHT gestreamt**!

### **TTS-Flow (AKTUELL):**
```
1. Flutter → Backend: Chat-Message
2. Backend: LLM Response generieren
3. Backend: ElevenLabs TTS → Vollständige MP3-Datei
4. Backend → Flutter: Base64-encoded MP3
5. Flutter: Decode → Save to /tmp → Play with AudioPlayer
```

**FAKT:** **KEIN Streaming**, vollständige Datei wird erst generiert, dann übertragen!

### **Orchestrator (EXISTIERT, aber nicht aktiv!):**
```typescript
// orchestrator/src/eleven_adapter.ts
export function startElevenStream(opts: {
  onAudio: (pcm: Buffer) => void;  // ← WebSocket Stream
  onTimestamp: (ts: TimestampEvent) => void;  // ← Phoneme!
}) {
  // WebSocket zu ElevenLabs Streaming API
}
```

**FAKT:** Orchestrator **existiert**, aber **Flutter nutzt ihn NICHT**!

---

## 🎯 **DIE ENTSCHEIDUNG:**

### **Option 1: WebSocket (Einfach, ABER...)**

**Workflow:**
```
Orchestrator WebSocket → Flutter
  ↓
{type: 'audio', data: base64chunk}  → AudioPlayer.playBytes()
{type: 'viseme', value: 'MBP', pts_ms: 123}  → VisemeMixer
```

**Problem:** `just_audio` (AudioPlayer) kann **KEINE Chunks streamen**!
- Braucht **vollständige Datei** oder **URL**
- Kein `playBytes()` Support
- Alternative: `audioplayers` package → hat Streaming, aber weniger Features

**Vorteile:**
- ✅ Einfach zu implementieren (WebSocket ist simpel)
- ✅ Günstig ($5-10/Monat)
- ✅ Viseme-Events funktionieren perfekt

**Nachteile:**
- ❌ Audio-Player wechseln nötig (`just_audio` → `audioplayers`)
- ❌ Höhere Latenz (~200-300ms extra durch Buffering)
- ❌ Keine native Browser-Integration

---

### **Option 2: WebRTC (Komplex, ABER...)**

**Workflow:**
```
Orchestrator WebRTC Track → Flutter (livekit_client)
  ↓
Audio: Native Browser/OS Audio Pipeline (ultra-low latency!)
Viseme: WebSocket/DataChannel → VisemeMixer
```

**LiveKit Integration (BEREITS im Code!):**
```dart
// lib/services/livekit_service.dart (EXISTIERT!)
class LiveKitService {
  Room? _room;
  
  Future<void> joinRoom(String token) async {
    _room = Room();
    await _room!.connect(url, token);
    
    // Audio von Server empfangen
    _room!.on<TrackSubscribedEvent>((event) {
      // Native Audio-Playback! ✅
    });
  }
}
```

**FAKT:** LiveKit ist **BEREITS integriert**! (aber nicht für TTS genutzt)

**Vorteile:**
- ✅ **ULTRA-LOW LATENCY** (~50-150ms glass-to-glass!)
- ✅ Native Audio-Playback (besser als jeder Player)
- ✅ Bewährte Technologie (Zoom, Discord nutzen es)
- ✅ **LiveKit ist BEREITS im Code!**
- ✅ DataChannel für Viseme-Events (parallel zum Audio!)

**Nachteile:**
- 💰 Höhere Kosten ($20-50/Monat für LiveKit Cloud oder eigenen TURN Server)
- 🏗️ Komplexere Infrastruktur (STUN/TURN)
- ⚙️ Mehr Debugging (NAT-Traversal, Firewalls)

---

## 💡 **MEINE FINALE EMPFEHLUNG:**

### **STARTE MIT: WebSocket + audioplayers** ✅

**Warum?**

1. **Schneller Start:** 2-3 Tage statt 1 Woche
2. **Günstiger:** $5-10/Monat statt $20-50/Monat
3. **Weniger Risiko:** Einfacher zu debuggen
4. **Gute Latenz:** ~700-1300ms ist **akzeptabel** für MVP

**Migration später zu WebRTC:**
- Wenn User-Feedback: "Latenz zu hoch"
- Wenn Traffic > 100 Requests/Tag (dann lohnt sich LiveKit-Invest)
- LiveKit-Service ist **bereits da**, nur aktivieren!

---

## 📋 **IMPLEMENTATION - WebSocket Path:**

### **1. Orchestrator: WebSocket Server**

```typescript
// orchestrator/src/lipsync_ws.ts (NEU)
import { WebSocketServer } from 'ws';
import { startElevenStream } from './eleven_adapter.js';

const wss = new WebSocketServer({ port: 3001 });

wss.on('connection', (ws) => {
  let elevenWs: any = null;
  
  ws.on('message', async (data) => {
    const msg = JSON.parse(data.toString());
    
    if (msg.type === 'speak') {
      // Start ElevenLabs Streaming
      elevenWs = await startElevenStream({
        voice_id: msg.voice_id,
        apiKey: process.env.ELEVENLABS_API_KEY!,
        
        onAudio: (pcm) => {
          // Audio-Chunk zu Client
          ws.send(JSON.stringify({
            type: 'audio',
            data: pcm.toString('base64'),
            format: 'pcm_16000',  // PCM 16kHz
          }));
        },
        
        onTimestamp: (ts) => {
          // Viseme-Event zu Client
          const viseme = mapPhonemeToViseme(ts.phoneme);
          ws.send(JSON.stringify({
            type: 'viseme',
            value: viseme,
            pts_ms: ts.t_ms,
          }));
        },
      });
      
      // Send Text to ElevenLabs
      elevenWs.send(JSON.stringify({
        text: msg.text,
        voice_settings: { stability: 0.5, similarity_boost: 0.75 },
      }));
    }
    
    if (msg.type === 'stop') {
      elevenWs?.close();
    }
  });
});

function mapPhonemeToViseme(phoneme: string | null): string {
  if (!phoneme) return 'Rest';
  
  const map: Record<string, string> = {
    // Vokale
    'ə': 'E', 'ɚ': 'E', 'ɝ': 'E', 'ɛ': 'E', 'e': 'E',
    'i': 'AI', 'ɪ': 'AI', 'iː': 'AI',
    'u': 'U', 'ʊ': 'U', 'uː': 'U',
    'o': 'O', 'ɔ': 'O', 'oː': 'O',
    'ɑ': 'AI', 'aː': 'AI', 'æ': 'AI',
    // Konsonanten
    'm': 'MBP', 'b': 'MBP', 'p': 'MBP',
    'f': 'FV', 'v': 'FV',
    'l': 'L',
    'w': 'WQ', 'r': 'R',
    'θ': 'TH', 'ð': 'TH',
    'ʃ': 'CH', 'ʒ': 'CH', 'tʃ': 'CH', 'dʒ': 'CH',
  };
  
  return map[phoneme] || 'Rest';
}
```

### **2. Flutter: Audio-Player wechseln**

```yaml
# pubspec.yaml
dependencies:
  # ERSETZE:
  # just_audio: ^0.9.36
  
  # MIT:
  audioplayers: ^5.2.1  # Hat playBytes() Support!
  web_socket_channel: ^2.4.0
```

### **3. Flutter: Lipsync Service**

```dart
// lib/services/lipsync_service.dart (NEU)
import 'package:audioplayers/audioplayers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:typed_data';

class LipsyncService {
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;
  VisemeMixer? _mixer;
  
  // Audio Buffer für Streaming
  final List<Uint8List> _audioBuffer = [];
  bool _isPlaying = false;
  
  void connect(String sessionId, VisemeMixer mixer) {
    _mixer = mixer;
    _audioPlayer = AudioPlayer();
    
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://orchestrator.sunriza26.com/lipsync/$sessionId'),
    );
    
    _channel!.stream.listen((message) {
      final data = json.decode(message);
      
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
  
  void _handleAudio(Map<String, dynamic> data) {
    final audioBytes = base64.decode(data['data']);
    _audioBuffer.add(audioBytes);
    
    // Start Playback nach erstem Chunk
    if (!_isPlaying && _audioBuffer.isNotEmpty) {
      _startPlayback();
    }
  }
  
  Future<void> _startPlayback() async {
    _isPlaying = true;
    
    // audioplayers unterstützt BytesSource!
    for (final chunk in _audioBuffer) {
      await _audioPlayer!.play(BytesSource(chunk));
      // Wait for chunk to finish
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    _audioBuffer.clear();
    _isPlaying = false;
  }
  
  void _handleViseme(Map<String, dynamic> data) {
    final viseme = data['value'] as String;
    final ptsMs = data['pts_ms'] as int;
    
    // Viseme mit Delay abspielen (für Sync)
    Future.delayed(Duration(milliseconds: ptsMs), () {
      _mixer?.setViseme(viseme, 1.0);
      
      // Fade out nach 100ms
      Future.delayed(Duration(milliseconds: 100), () {
        _mixer?.setViseme(viseme, 0.0);
      });
    });
  }
  
  void speak(String text, String voiceId) {
    _channel?.sink.add(json.encode({
      'type': 'speak',
      'text': text,
      'voice_id': voiceId,
    }));
  }
  
  void stop() {
    _channel?.sink.add(json.encode({'type': 'stop'}));
    _audioPlayer?.stop();
    _mixer?.reset();
  }
  
  void dispose() {
    _channel?.sink.close();
    _audioPlayer?.dispose();
  }
}
```

---

## 💰 **KOSTEN (WebSocket Path):**

| Komponente | Kosten |
|------------|--------|
| ElevenLabs Streaming | $0.12/min (bereits kalkuliert) |
| Orchestrator (Cloud Run) | $5-10/Monat |
| WebSocket Bandwidth | ~100 KB/min → negligible |
| **TOTAL** | **$5-10/Monat fix** |

---

## ⏱️ **LATENZ (WebSocket Path):**

| Phase | Zeit |
|-------|------|
| LLM Response | 500-1000ms |
| ElevenLabs First Chunk | 150-250ms |
| WebSocket → Flutter | 50-100ms |
| Audio Buffer → Play | 100-200ms |
| Viseme Render | 5-10ms |
| **Glass-to-glass** | **~800-1500ms** |

**Vergleich:**
- **Aktuell (MP3-Datei):** ~2000-3000ms
- **WebSocket:** ~800-1500ms (**50% schneller!**)
- **WebRTC (später):** ~400-700ms (**3x schneller!**)

---

## 🎯 **MIGRATION ZU WEBRTC (SPÄTER):**

**Wann upgraden?**
- User-Feedback: "Latenz zu hoch"
- Traffic > 100 Requests/Tag
- Budget für $20-50/Monat verfügbar

**Wie?**
```dart
// Nur LipsyncService ändern:
// WebSocket → LiveKit Room
// audioplayers → Keine Änderung nötig (Audio kommt von LiveKit Track)
// Rest bleibt gleich!
```

---

## ✅ **FINALE ENTSCHEIDUNG:**

**START MIT:** WebSocket + audioplayers + Orchestrator  
**LATENZ:** 800-1500ms (50% schneller als jetzt!)  
**KOSTEN:** $5-10/Monat (günstig!)  
**ZEIT:** 2-3 Tage  

**UPGRADE SPÄTER:** WebRTC wenn nötig (LiveKit ist bereits integriert!)

---

**Keine Tageslaune mehr - das ist die richtige Lösung!** ✅

**Letzte Aktualisierung:** 17.10.2025, 02:20 Uhr


