# Lipsync REALTIME Integration - Der richtige Weg

**Stand:** 17.10.2025, 02:00 Uhr  
**Status:** System ist BEREIT - nur Viseme-Stream fehlt!

---

## ✅ **WAS BEREITS LÄUFT:**

1. ✅ **LivePortrait Dynamics** → `idle.mp4` Loop zwischen Antworten
2. ✅ **ElevenLabs TTS** → Audio-Streams laufen (backend + orchestrator!)
3. ✅ **Orchestrator** → `/orchestrator/src/eleven_adapter.ts` → **HAT BEREITS `onTimestamp`!** 🔥
4. ✅ **Flutter UI** → `AvatarOverlay` + `VisemeMixer` → **WARTEN NUR AUF DATEN!**
5. ✅ **Assets** → `atlas.png`, `mask.png`, `roi.json` → von LivePortrait generiert
6. ✅ **Pinecone RAG** → Brain funktioniert

---

## 🎯 **WAS FEHLT (NUR 3 SACHEN!):**

### 1. **Orchestrator: Viseme-Mapping aktivieren**

```typescript
// orchestrator/src/eleven_adapter.ts (BEREITS DA!)

export function startElevenStream(opts: {
  voice_id: string;
  apiKey: string;
  onAudio: (pcm: Buffer) => void;
  onTimestamp: (ts: TimestampEvent) => void;  // ← BEREITS VORHANDEN!
}) {
  // ElevenLabs WebSocket Streaming
  const ws = new WebSocket(`wss://api.elevenlabs.io/v1/text-to-speech/${voice_id}/stream-input?...`);
  
  ws.on('message', (data) => {
    const msg = JSON.parse(data);
    
    if (msg.audio) {
      opts.onAudio(Buffer.from(msg.audio, 'base64'));
    }
    
    // ← HIER: Phoneme Timestamps!
    if (msg.alignment) {
      const visemes = mapPhonemesToVisemes(msg.alignment);
      opts.onTimestamp(visemes);  // ← SCHON DA!
    }
  });
}

// NEU: Phoneme → Viseme Mapping
function mapPhonemesToVisemes(alignment: any): VisemeEvent[] {
  const map: Record<string, string> = {
    // IPA Phoneme → LivePortrait Viseme
    'ə': 'E', 'ɚ': 'E', 'ɝ': 'E',  // Schwa
    'i': 'AI', 'ɪ': 'AI', 'iː': 'AI',  // EE
    'u': 'U', 'ʊ': 'U', 'uː': 'U',  // OO
    'o': 'O', 'ɔ': 'O', 'oː': 'O',  // OH
    'ɑ': 'AI', 'aː': 'AI',  // AH
    'e': 'E', 'eː': 'E', 'ɛ': 'E',  // EH
    'm': 'MBP', 'b': 'MBP', 'p': 'MBP',  // Lips closed
    'f': 'FV', 'v': 'FV',  // Teeth on lip
    'l': 'L',  // Tongue
    'w': 'WQ', 'r': 'R',
    'θ': 'TH', 'ð': 'TH',  // TH
    'ʃ': 'CH', 'ʒ': 'CH', 'tʃ': 'CH', 'dʒ': 'CH',  // SH/CH
    // Silence
    '': 'Rest', ' ': 'Rest',
  };
  
  return alignment.chars.map((char: any) => ({
    character: char.character,
    start_ms: char.start_time_ms,
    end_ms: char.end_time_ms,
    viseme: map[char.phoneme] || 'Rest',
  }));
}
```

### 2. **Orchestrator: WebSocket zu Flutter**

```typescript
// orchestrator/src/lipsync_handler.ts (NEU)

import { WebSocket, WebSocketServer } from 'ws';

const wss = new WebSocketServer({ port: 3001 });

wss.on('connection', (clientWs: WebSocket, req) => {
  const sessionId = req.url?.split('/').pop();
  
  clientWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    
    if (msg.type === 'speak') {
      // Start ElevenLabs Stream
      startElevenStream({
        voice_id: msg.voice_id,
        apiKey: process.env.ELEVENLABS_API_KEY!,
        
        onAudio: (pcm) => {
          // Audio zu Client streamen
          clientWs.send(JSON.stringify({
            type: 'audio',
            data: pcm.toString('base64'),
          }));
        },
        
        onTimestamp: (visemes) => {
          // Viseme-Events zu Client streamen
          for (const v of visemes) {
            clientWs.send(JSON.stringify({
              type: 'viseme',
              start_ms: v.start_ms,
              end_ms: v.end_ms,
              value: v.viseme,
            }));
          }
        },
      });
    }
  });
});

console.log('🎤 Lipsync Orchestrator läuft auf Port 3001');
```

### 3. **Flutter: WebSocket Client**

```dart
// lib/services/lipsync_service.dart (NEU)

import 'package:web_socket_channel/web_socket_channel.dart';

class LipsyncService {
  WebSocketChannel? _channel;
  VisemeMixer? _mixer;
  
  void connect(String sessionId, VisemeMixer mixer) {
    _mixer = mixer;
    
    // Connect zu Orchestrator
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://orchestrator.sunriza26.com/lipsync/$sessionId'),
    );
    
    _channel!.stream.listen((message) {
      final data = json.decode(message);
      
      switch (data['type']) {
        case 'viseme':
          _handleViseme(data);
          break;
      }
    });
  }
  
  void _handleViseme(Map<String, dynamic> data) {
    final viseme = data['value'] as String;
    final startMs = data['start_ms'] as int;
    final durationMs = (data['end_ms'] as int) - startMs;
    
    // Schedule Viseme-Animation (mit Server-PTS sync!)
    Future.delayed(Duration(milliseconds: startMs), () {
      _mixer?.setViseme(viseme, 1.0);
      
      // Fade out am Ende
      Future.delayed(Duration(milliseconds: durationMs), () {
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
    _mixer?.reset();
  }
  
  void dispose() {
    _channel?.sink.close();
  }
}
```

```dart
// avatar_chat_screen.dart (ERWEITERN)

LipsyncService? _lipsyncService;

@override
void initState() {
  super.initState();
  
  // Init Lipsync Service (wenn VisemeMixer vorhanden)
  if (_visemeMixer != null) {
    _lipsyncService = LipsyncService();
    _lipsyncService!.connect(_avatarData!.id, _visemeMixer!);
  }
}

// Bei TTS-Request:
void _sendMessage(String text) async {
  // ... existing LLM logic ...
  
  // Statt lokalem TTS-File:
  // _lipsyncService?.speak(llmResponse, voiceId);  ← REALTIME!
}

@override
void dispose() {
  _lipsyncService?.dispose();
  super.dispose();
}
```

---

## 🚀 **DEPLOYMENT:**

### 1. Orchestrator auf Cloud Run:

```yaml
# cloudbuild_orchestrator.yaml (NEU)
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/sunriza26/orchestrator:latest', './orchestrator']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/sunriza26/orchestrator:latest']
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'run'
      - 'deploy'
      - 'orchestrator'
      - '--image=gcr.io/sunriza26/orchestrator:latest'
      - '--platform=managed'
      - '--region=europe-west1'
      - '--allow-unauthenticated'
      - '--memory=512Mi'
      - '--cpu=1'
      - '--timeout=300'
```

```bash
# Deploy
gcloud builds submit --config=cloudbuild_orchestrator.yaml
```

### 2. Flutter App Config:

```dart
// lib/config.dart (erweitern)
const orchestratorUrl = 'wss://orchestrator-xyz.run.app';
```

---

## 💰 **KOSTEN:**

| Komponente | Kosten |
|------------|--------|
| ElevenLabs Streaming | **$0.12/min** (BEREITS einkalkuliert!) |
| Orchestrator (Cloud Run) | **$5-10/Monat** (512MB RAM, minimal Traffic) |
| WebSocket Bandwidth | ~50 KB/min → **negligible** |
| **TOTAL NEU** | **~$5-10/Monat** (fix) |

**KEINE zusätzlichen per-Request Kosten!** ✅

---

## ⏱️ **LATENZ:**

| Phase | Zeit |
|-------|------|
| LLM Response | ~500-1000ms |
| ElevenLabs First Audio | ~150-250ms |
| WebSocket → Flutter | ~20-50ms |
| Viseme Render | ~5-10ms |
| **Glass-to-glass** | **~700-1300ms** ← MEGA SCHNELL! ✅ |

---

## 🎯 **IMPLEMENTATION STEPS:**

### **Tag 1: Orchestrator**
1. ✅ `mapPhonemesToVisemes()` implementieren
2. ✅ WebSocket Server aufsetzen (`lipsync_handler.ts`)
3. ✅ ElevenLabs Streaming mit Phoneme-Alignment aktivieren
4. ✅ Lokal testen mit Test-Client

### **Tag 2: Flutter**
1. ✅ `LipsyncService` implementieren
2. ✅ WebSocket Connection zu Orchestrator
3. ✅ `VisemeMixer` Integration
4. ✅ Testen mit Avatar-Chat

### **Tag 3: Deployment & Testing**
1. ✅ Orchestrator auf Cloud Run deployen
2. ✅ Flutter App Config aktualisieren
3. ✅ End-to-End Testing
4. ✅ Latency & Qualität optimieren

**TOTAL: 3 Tage!** ✅

---

## 🔥 **WARUM DAS DIE RICHTIGE LÖSUNG IST:**

✅ **MEGA SCHNELL:** ~700-1300ms glass-to-glass  
✅ **KOSTEN GÜNSTIG:** Nur $5-10/Monat fix (ElevenLabs bereits kalkuliert!)  
✅ **STABIL:** WebSocket ist Standard, kein kompliziertes WebRTC nötig  
✅ **EINFACH:** Orchestrator ist BEREITS DA! Nur Viseme-Mapping hinzufügen!  
✅ **SKALIERBAR:** Cloud Run auto-scales, kein Problem  

---

## 📝 **NÄCHSTE SCHRITTE (SOFORT!):**

```bash
# 1. Orchestrator erweitern
cd orchestrator/src
# Implementiere mapPhonemesToVisemes() in eleven_adapter.ts
# Implementiere lipsync_handler.ts (WebSocket Server)

# 2. Deploy Orchestrator
gcloud builds submit --config=cloudbuild_orchestrator.yaml

# 3. Flutter: LipsyncService implementieren
cd lib/services
# Erstelle lipsync_service.dart

# 4. Test!
flutter run
```

---

**🚀 LOS GEHT'S!** Dies ist die **ECHTE** Lösung - nicht das Offline-Zeug!

**Latenz:** MEGA SCHNELL ✅  
**Kosten:** GÜNSTIG ✅  
**Stabilität:** ROBUST ✅  

**Letzte Aktualisierung:** 17.10.2025, 02:05 Uhr

