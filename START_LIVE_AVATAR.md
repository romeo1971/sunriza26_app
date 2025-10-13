# 🎭 Live Avatar - Start Anleitung

## ✅ Was wurde integriert:

1. **Assets für Schatzy**: `avatars/schatzy/` (idle.mp4, atlas.png, mask.png, roi.json, atlas.json)
2. **Flutter Widgets**: `lib/widgets/avatar_overlay.dart`, `lib/widgets/viseme_mixer.dart`
3. **Chat-Screen erweitert**: Video + Overlay-Layer statt statischem Bild
4. **Node Orchestrator**: `orchestrator/` (ElevenLabs Streaming + Viseme Mapping)
5. **WebSocket Integration**: Client ↔ Server kommunizieren

---

## 🚀 **STARTEN:**

### 1. Orchestrator starten (Terminal 1):
```bash
cd orchestrator
npm run dev
```
→ Läuft auf `http://localhost:8787`

### 2. Flutter App starten (Terminal 2):
```bash
flutter run
```

### 3. Im Chat testen:
- Öffne einen Avatar-Chat (idealerweise Schatzy)
- Du solltest das **Video** (idle.mp4) sehen statt statischem Bild
- Sende eine Nachricht
- Schau ob der **Mund animiert** wird!

---

## 🔍 **DEBUG:**

### Orchestrator Logs:
```bash
cd orchestrator
npm run dev
```
→ Zeigt WebSocket-Verbindungen und Viseme-Events

### Flutter Logs:
```bash
flutter run --verbose
```
→ Suche nach:
- ✅ Live Avatar initialisiert
- ✅ Orchestrator verbunden
- 🗣️ Live Speak gestartet

---

## ⚙️ **Konfiguration:**

### orchestrator/.env:
```env
ELEVENLABS_API_KEY=your_key_here
ELEVENLABS_VOICE_ID=your_voice_id
ORCHESTRATOR_PORT=8787
```

---

## 📝 **Was noch fehlt:**

1. **Echtes ElevenLabs Streaming** (aktuell Simulation)
2. **Assets in Firebase Storage** (aktuell lokal hardcoded)
3. **LiveKit statt WebSocket** (für Production)
4. **Prozedural-Animator** (Blinzeln, Augenbrauen, etc.)

---

## 🎯 **Nächste Schritte:**

1. **Test:** Video + Mund-Animation funktioniert?
2. **ElevenLabs:** Echtes Streaming mit Timestamps integrieren
3. **Firebase:** Assets dynamisch laden
4. **Polish:** Smoothing, Koartikulation, Prosody

---

**Status:** 🟢 READY FOR TEST!

