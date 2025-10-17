# Lipsync Implementation Plan für Sunriza26

**Stand:** 17.10.2025, 01:30 Uhr  
**Status:** ✅ LivePortrait Dynamics fertig, **🚧 Lipsync Integration steht bevor**

---

## 🎯 Aktueller Stand

### ✅ Was bereits funktioniert:

1. **LivePortrait Dynamics (Idle-Loop):**
   - ✅ `idle.mp4` wird in `avatar_chat_screen.dart` als **Video-Layer** abgespielt
   - ✅ Video loopt nahtlos (3-10s)
   - ✅ Zeigt **Mikro-Kopfbewegungen** zwischen Chat-Antworten
   - ✅ Assets: `idleVideoUrl`, `atlasUrl`, `maskUrl`, `atlasJsonUrl`, `roiJsonUrl`
   - ✅ Performance: 70-90s Generierung auf Modal.com (T4 GPU)

2. **Chat-System:**
   - ✅ ElevenLabs TTS für Sprach-Ausgabe
   - ✅ Audio-Player mit `_isSpeaking` Status
   - ✅ STT (Speech-to-Text) für Voice Input
   - ✅ LiveKit für Voice-Chat (optional)

3. **UI-Layers (bereits vorbereitet!):**
   ```dart
   // avatar_chat_screen.dart, Zeile 732-760
   Stack(
     children: [
       // Layer 0: Idle-Loop Video ✅
       Positioned.fill(child: VideoPlayer(_idleController!)),
       
       // Layer 1: Mund-Overlay (VORBEREITET, aber nicht aktiv!)
       if (_atlasImage != null && _visemeMixer != null)
         Positioned.fill(
           child: AvatarOverlay(
             atlas: _atlasImage!,
             mask: _maskImage!,
             cells: _atlasCells!,
             roi: _mouthROI!,
             mixer: _visemeMixer!,
           ),
         ),
     ],
   )
   ```

4. **Assets (bereits generiert!):**
   - ✅ `atlas.png` - Sprite-Atlas für Visemes
   - ✅ `mask.png` - Alpha-Maske für Mund-ROI
   - ✅ `atlas.json` - Viseme-Koordinaten
   - ✅ `roi.json` - ROI-Position (x, y, w, h)

### ⚠️ Was noch fehlt:

1. **Viseme-Daten:** ElevenLabs liefert aktuell nur Audio, **keine Phonem-Timestamps**
2. **Viseme-Mixer:** `_visemeMixer` ist `null` → keine Lippen-Animation
3. **WebSocket:** Kein Realtime-Stream für Viseme-Events
4. **Backend Orchestrator:** Kein Service für Phonem → Viseme Mapping

---

## 📋 Implementation Plan

### **Phase 1: Offline Lipsync (SCHNELL)** 🟢 EMPFOHLEN FÜR START

**Ziel:** Lipsync **ohne** Realtime-Streaming, nur für gespeicherte TTS-Audio

**Warum zuerst Offline?**
- ✅ **Schneller:** Keine WebSocket-Infrastruktur nötig
- ✅ **Einfacher:** Nutzt bestehende Audio-Files
- ✅ **Testbar:** Kann sofort mit existierenden Chat-Messages getestet werden
- ✅ **Kosten:** Keine zusätzlichen Backend-Kosten

**Workflow:**
```
1. User sendet Message
2. Backend: LLM Response generieren
3. Backend: ElevenLabs TTS → Audio-File (.mp3)
4. Backend: Rhubarb Lipsync → Viseme-Timeline (.json)
5. Flutter: Download Audio + Viseme-JSON
6. Flutter: Spiele Audio + animate Visemes synchron ab
```

**Was wir brauchen:**

#### 1.1 Backend: Rhubarb Lipsync Integration

**Rhubarb** ist ein **offline Lipsync-Tool**, das aus Audio-Files Viseme-Timelines generiert.

```python
# backend/services/lipsync_service.py (NEU)

import subprocess
import json
from pathlib import Path

class LipsyncService:
    """Generiert Viseme-Timeline aus Audio-File mit Rhubarb"""
    
    @staticmethod
    def generate_visemes(audio_path: str, output_json: str) -> dict:
        """
        Nutzt Rhubarb CLI um Visemes zu generieren
        
        Args:
            audio_path: Path zum TTS Audio-File (.mp3/.wav)
            output_json: Output path für viseme.json
            
        Returns:
            dict: Viseme-Timeline
        """
        # Rhubarb CLI (muss installiert sein!)
        cmd = [
            'rhubarb',
            '-f', 'json',  # JSON Output
            '-o', output_json,
            audio_path
        ]
        
        subprocess.run(cmd, check=True)
        
        # Load & return
        with open(output_json, 'r') as f:
            return json.load(f)
```

**Rhubarb Output Format:**
```json
{
  "metadata": {
    "soundFile": "audio.mp3",
    "duration": 3.45
  },
  "mouthCues": [
    { "start": 0.00, "end": 0.10, "value": "X" },
    { "start": 0.10, "end": 0.25, "value": "A" },
    { "start": 0.25, "end": 0.40, "value": "B" },
    { "start": 0.40, "end": 0.55, "value": "C" },
    ...
  ]
}
```

**Viseme-Klassen (Rhubarb → LivePortrait Mapping):**
| Rhubarb | Phonem | LivePortrait Sprite |
|---------|--------|---------------------|
| X | Rest/Silence | Rest |
| A | AI (father) | AI |
| B | MBP (lips closed) | MBP |
| C | E (bed) | E |
| D | AI (cake) | AI |
| E | O (though) | O |
| F | U (boot) | U |
| G | FV (five) | FV |
| H | L (hello) | L |

#### 1.2 Backend: TTS-Endpoint erweitern

```python
# functions/src/index.ts (erweitern)

export const generateTTS = functions.https.onRequest(async (req, res) => {
  // ... existing ElevenLabs TTS logic ...
  
  const audioPath = `/tmp/tts_${messageId}.mp3`;
  const visemePath = `/tmp/visemes_${messageId}.json`;
  
  // 1. Generate Audio (existing)
  await elevenLabsTTS(text, voiceId, audioPath);
  
  // 2. Generate Visemes (NEU!)
  await generateVisemes(audioPath, visemePath);
  
  // 3. Upload BEIDE zu Firebase Storage
  const audioUrl = await uploadToStorage(audioPath, `tts/${messageId}.mp3`);
  const visemeUrl = await uploadToStorage(visemePath, `tts/${messageId}_visemes.json`);
  
  // 4. Return URLs
  res.json({
    audioUrl,
    visemeUrl,  // NEU!
    duration: audioDuration
  });
});
```

#### 1.3 Flutter: Viseme-Player

```dart
// lib/services/viseme_player.dart (NEU)

class VisemePlayer {
  final VisemeMixer mixer;
  final String visemeJsonUrl;
  
  List<VisemeCue> _cues = [];
  int _currentIndex = 0;
  Timer? _timer;
  
  Future<void> load() async {
    // Download viseme.json
    final response = await http.get(Uri.parse(visemeJsonUrl));
    final data = json.decode(response.body);
    
    // Parse cues
    final mouthCues = data['mouthCues'] as List;
    _cues = mouthCues.map((c) => VisemeCue(
      start: c['start'] as double,
      end: c['end'] as double,
      viseme: _mapRhubarbToViseme(c['value'] as String),
    )).toList();
  }
  
  void play(AudioPlayer audioPlayer) {
    _currentIndex = 0;
    
    // Synchronisiere mit Audio-Position
    _timer = Timer.periodic(Duration(milliseconds: 16), (_) {
      final pos = audioPlayer.position?.inMilliseconds ?? 0;
      final posSec = pos / 1000.0;
      
      // Finde aktuelle Viseme
      while (_currentIndex < _cues.length && 
             _cues[_currentIndex].end < posSec) {
        _currentIndex++;
      }
      
      if (_currentIndex < _cues.length) {
        final cue = _cues[_currentIndex];
        
        // Interpolation für smooth transitions
        final progress = (posSec - cue.start) / (cue.end - cue.start);
        
        // Nächstes Viseme für Blending
        final nextViseme = _currentIndex + 1 < _cues.length 
            ? _cues[_currentIndex + 1].viseme 
            : 'Rest';
        
        // Update Mixer
        mixer.setViseme(cue.viseme, 1.0 - progress);
        mixer.setViseme(nextViseme, progress);
      }
    });
  }
  
  void stop() {
    _timer?.cancel();
    mixer.reset();
  }
  
  String _mapRhubarbToViseme(String rhubarb) {
    const map = {
      'X': 'Rest',
      'A': 'AI', 'D': 'AI',
      'B': 'MBP',
      'C': 'E',
      'E': 'O',
      'F': 'U',
      'G': 'FV',
      'H': 'L',
    };
    return map[rhubarb] ?? 'Rest';
  }
}
```

#### 1.4 Flutter: Chat-Screen Integration

```dart
// avatar_chat_screen.dart (erweitern)

VisemePlayer? _visemePlayer;

Future<void> _playTTSAudio(String audioUrl, String visemeUrl) async {
  // Initialisiere Viseme-Player
  if (_visemeMixer != null && visemeUrl.isNotEmpty) {
    _visemePlayer = VisemePlayer(
      mixer: _visemeMixer!,
      visemeJsonUrl: visemeUrl,
    );
    await _visemePlayer!.load();
  }
  
  // Starte Audio
  await _player.setUrl(audioUrl);
  await _player.play();
  
  // Starte Viseme-Animation synchron
  if (_visemePlayer != null) {
    _visemePlayer!.play(_player);
  }
  
  // Cleanup wenn Audio fertig
  _player.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      _visemePlayer?.stop();
    }
  });
}
```

**Vorteile Phase 1:**
- ✅ Funktioniert sofort mit bestehendem Code
- ✅ Keine WebSocket-Infrastruktur nötig
- ✅ Keine zusätzlichen Backend-Kosten
- ✅ Testbar mit allen existierenden Messages
- ✅ Gute Lipsync-Qualität (Rhubarb ist sehr präzise!)

**Nachteile Phase 1:**
- ⏱️ Latenz: Viseme-Generierung dauert ~200-500ms extra
- 📦 Größere Payload: Audio + JSON müssen geladen werden
- ❌ Kein Realtime-Streaming (Lipsync startet erst nach Audio-Download)

---

### **Phase 2: Realtime Lipsync (SPÄTER)** 🔵 FÜR PRODUCTION

**Ziel:** Lipsync **mit** Realtime-Streaming, ultra-low latency

**Workflow:**
```
1. User sendet Message
2. Backend: LLM Response → Stream
3. Backend: ElevenLabs Streaming TTS → Audio Chunks + Phoneme Timestamps
4. Backend: Viseme-Mapper → Viseme Events
5. WebSocket: Stream Viseme-Events zum Client
6. Flutter: Spiele Audio-Stream + animate Visemes in Realtime
```

**Was wir brauchen:**

#### 2.1 Backend: Orchestrator Service

```typescript
// orchestrator/src/lipsync_service.ts (NEU)

import { ElevenLabs } from 'elevenlabs';
import WebSocket from 'ws';

class LipsyncOrchestrator {
  async streamTTS(text: string, voiceId: string, clientWs: WebSocket) {
    const elevenlabs = new ElevenLabs({ apiKey: process.env.ELEVENLABS_API_KEY });
    
    // ElevenLabs Streaming mit Phoneme Alignment
    const stream = await elevenlabs.textToSpeech.convertWithTimestamps(
      voiceId,
      {
        text,
        model_id: 'eleven_multilingual_v2',
        output_format: 'mp3_44100_128',
        apply_text_normalization: 'auto',
      }
    );
    
    // Process Stream
    for await (const chunk of stream) {
      if (chunk.audio) {
        // Audio chunk → Client
        clientWs.send(JSON.stringify({
          type: 'audio',
          data: chunk.audio.toString('base64'),
          pts: chunk.audio_pts_ms,
        }));
      }
      
      if (chunk.alignment) {
        // Phoneme → Viseme Mapping
        const visemes = this.mapPhonemesToVisemes(chunk.alignment);
        
        // Viseme events → Client
        for (const viseme of visemes) {
          clientWs.send(JSON.stringify({
            type: 'viseme',
            pts_ms: viseme.pts_ms,
            value: viseme.value,
            duration_ms: viseme.duration_ms,
          }));
        }
      }
    }
    
    // End signal
    clientWs.send(JSON.stringify({ type: 'end' }));
  }
  
  mapPhonemesToVisemes(alignment: any): Viseme[] {
    // Phoneme → Viseme Mapping (IPA → LivePortrait)
    const map: Record<string, string> = {
      'ə': 'E', 'ɚ': 'E', 'ɝ': 'E',
      'i': 'AI', 'ɪ': 'AI',
      'u': 'U', 'ʊ': 'U',
      'o': 'O', 'ɔ': 'O',
      'm': 'MBP', 'b': 'MBP', 'p': 'MBP',
      'f': 'FV', 'v': 'FV',
      'l': 'L',
      // ... mehr Mappings
    };
    
    return alignment.phonemes.map((p: any) => ({
      pts_ms: p.start_ms,
      value: map[p.symbol] || 'Rest',
      duration_ms: p.end_ms - p.start_ms,
    }));
  }
}
```

#### 2.2 Flutter: WebSocket Client

```dart
// lib/services/realtime_lipsync_service.dart (NEU)

class RealtimeLipsyncService {
  WebSocketChannel? _channel;
  AudioPlayer? _streamPlayer;
  VisemeMixer? _mixer;
  
  void connect(String sessionId, VisemeMixer mixer) {
    _mixer = mixer;
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
        case 'end':
          _handleEnd();
          break;
      }
    });
  }
  
  void _handleAudio(Map<String, dynamic> data) {
    // Decode base64 audio chunk
    final audioBytes = base64.decode(data['data']);
    
    // Play audio chunk (requires streaming audio player!)
    _streamPlayer?.playBytes(audioBytes);
  }
  
  void _handleViseme(Map<String, dynamic> data) {
    final viseme = data['value'] as String;
    final ptMs = data['pts_ms'] as int;
    final durationMs = data['duration_ms'] as int;
    
    // Schedule viseme animation
    Future.delayed(Duration(milliseconds: ptMs), () {
      _mixer?.setViseme(viseme, 1.0);
      
      // Fade out nach duration
      Future.delayed(Duration(milliseconds: durationMs), () {
        _mixer?.setViseme(viseme, 0.0);
      });
    });
  }
  
  void _handleEnd() {
    _mixer?.reset();
  }
  
  void speak(String text) {
    _channel?.sink.add(json.encode({
      'type': 'speak',
      'text': text,
    }));
  }
  
  void stop() {
    _channel?.sink.add(json.encode({'type': 'stop'}));
    _mixer?.reset();
  }
}
```

**Vorteile Phase 2:**
- ✅ Ultra-low Latency (~250-400ms glass-to-glass)
- ✅ Lipsync startet sofort (streaming)
- ✅ Bessere UX (kein Warten auf Audio-Download)
- ✅ Professioneller (wie D-ID, HeyGen)

**Nachteile Phase 2:**
- 🏗️ Komplexere Backend-Infrastruktur (Orchestrator, WebSocket)
- 💰 Höhere Kosten (Realtime-Server, Bandwidth)
- ⚙️ Mehr Debugging (Clock-Sync, Network-Issues)

---

## 🎯 Empfohlene Reihenfolge

### Sprint 1: **Offline Lipsync (Phase 1)** ✅ START HIER!

**Ziele:**
1. ✅ Rhubarb Lipsync im Backend integrieren
2. ✅ TTS-Endpoint erweitern (Audio + Viseme-JSON)
3. ✅ Flutter: VisemePlayer implementieren
4. ✅ Chat-Screen: Lipsync bei TTS-Playback aktivieren

**Erfolgs-Kriterium:**
- Avatar bewegt Lippen synchron zu TTS-Audio
- Funktioniert mit allen existierenden Chat-Messages

**Zeitaufwand:** 2-3 Tage

---

### Sprint 2: **Qualität & Smoothing** 🎨

**Ziele:**
1. ✅ Co-articulation: Smooth Transitions zwischen Visemes
2. ✅ Blending: Interpolation für natürlichere Bewegung
3. ✅ Optimierung: Viseme-Mapping verfeinern (DE vs EN)
4. ✅ Testing: Mit verschiedenen Texten/Stimmen testen

**Erfolgs-Kriterium:**
- Lipsync sieht "natürlich" aus (keine ruckelnden Übergänge)
- Funktioniert gut mit deutschen UND englischen Texten

**Zeitaufwand:** 1-2 Tage

---

### Sprint 3: **Realtime Lipsync (Phase 2)** 🚀 SPÄTER!

**Ziele:**
1. ✅ Orchestrator Backend aufsetzen (Node.js + WebSocket)
2. ✅ ElevenLabs Streaming API integrieren
3. ✅ Phoneme → Viseme Mapping (mit Timestamps)
4. ✅ Flutter: Realtime WebSocket Client
5. ✅ Clock-Sync & Latency-Optimierung

**Erfolgs-Kriterium:**
- Lipsync startet sofort (keine Audio-Download-Wartezeit)
- Glass-to-glass < 400ms

**Zeitaufwand:** 5-7 Tage

---

## 📦 Benötigte Tools & Dependencies

### Backend (Firebase Functions):

```json
{
  "dependencies": {
    "rhubarb-lipsync": "^1.13.0",  // CLI Tool (npm wrapper)
    "@google-cloud/storage": "^7.7.0",
    "ffmpeg-static": "^5.2.0"
  }
}
```

### Backend (Orchestrator) - SPÄTER:

```json
{
  "dependencies": {
    "elevenlabs": "^0.7.0",
    "ws": "^8.14.0",
    "fastify": "^4.24.0",
    "fastify-websocket": "^5.0.0"
  }
}
```

### Flutter:

```yaml
dependencies:
  # Bereits vorhanden:
  video_player: ^2.8.1
  just_audio: ^0.9.36
  
  # Neu für Lipsync:
  web_socket_channel: ^2.4.0  # Für Phase 2 (Realtime)
```

---

## 💰 Kosten-Abschätzung

### Phase 1 (Offline Lipsync):

| Komponente | Kosten |
|------------|--------|
| Rhubarb CLI | Kostenlos (Open Source) |
| Compute (Viseme-Gen) | ~10ms → negligible |
| Storage (Viseme-JSON) | ~1-5 KB → $0.000001/Request |
| **TOTAL** | **~$0 extra** (nur TTS-Kosten) |

### Phase 2 (Realtime Lipsync):

| Komponente | Kosten |
|------------|--------|
| ElevenLabs Streaming | Gleich wie TTS (~$0.12/min) |
| Orchestrator Server | $20-50/Monat (Cloud Run) |
| WebSocket Bandwidth | ~100 KB/min → $0.001/min |
| **TOTAL** | **$20-50/Monat + $0.121/min** |

**Empfehlung:** Start mit Phase 1 (kostenlos!), Phase 2 nur wenn UX-Feedback positiv.

---

## 🎓 Lern-Ressourcen

1. **Rhubarb Lipsync:**
   - GitHub: https://github.com/DanielSWolf/rhubarb-lip-sync
   - Wiki: https://github.com/DanielSWolf/rhubarb-lip-sync/wiki

2. **Viseme-Theorie:**
   - Preston Blair Animation: https://www.animatorisland.com/preston-blair-mouth-charts/
   - Disney Viseme-Guide: 12 Standard-Visemes

3. **ElevenLabs Streaming:**
   - Docs: https://elevenlabs.io/docs/api-reference/websockets
   - Phoneme Alignment: https://elevenlabs.io/docs/api-reference/text-to-speech-with-timestamps

---

## ✅ Next Steps (Sofort starten!)

### 1. Rhubarb Lipsync testen (lokal):

```bash
# Install Rhubarb
brew install rhubarb-lipsync  # macOS
# oder Download: https://github.com/DanielSWolf/rhubarb-lip-sync/releases

# Test mit existierendem TTS-Audio
rhubarb -f json -o visemes.json test_audio.mp3

# Check Output
cat visemes.json
```

### 2. Backend: Firebase Function erweitern

```bash
cd functions
npm install rhubarb-lipsync ffmpeg-static
# Implementiere generateVisemes() in src/index.ts
```

### 3. Flutter: VisemePlayer implementieren

```bash
cd lib/services
# Erstelle viseme_player.dart
# Implementiere load(), play(), stop()
```

### 4. Test mit einem Avatar!

```bash
# 1. Generate Dynamics (bereits fertig)
# 2. Generate TTS Audio + Visemes (neu!)
# 3. Play Audio + Animate Visemes (neu!)
```

---

**🚀 START MIT PHASE 1 (OFFLINE LIPSYNC) - SCHNELL & KOSTENLOS!**

**Danach:** User-Feedback sammeln → bei Bedarf Phase 2 (Realtime) implementieren.

---

**Letzte Aktualisierung:** 17.10.2025, 01:45 Uhr  
**Status:** Ready to implement! 🎬

