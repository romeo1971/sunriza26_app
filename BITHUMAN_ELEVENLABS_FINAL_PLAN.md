# 🎯 BitHuman + ElevenLabs Integration - FINALER PLAN

## ✅ WAS IHR BEZAHLT / NUTZT:

- **BitHuman Cloud**: Avatar Video + Lipsync (Cloud Service!)
- **ElevenLabs**: Custom Voice Clone TTS
- **OpenAI Realtime**: LLM + STT
- **LiveKit Cloud**: Room Management
- **Modal.com**: Agent Hosting (oder euer Server)

---

## 🔥 DIE WAHRHEIT ÜBER BITHUMAN:

BitHuman ist **KEIN vollständiger Service**, sondern:

1. ✅ **Avatar Video Rendering** (Cloud)
2. ✅ **Lipsync** (Cloud)
3. ❌ **KEIN TTS** (muss selbst gebracht werden!)
4. ❌ **KEIN Agent Hosting** (muss selbst laufen!)

**IHR BRAUCHT:**
- Einen **laufenden Agent** (Modal/Server) der:
  - OpenAI für LLM/STT nutzt
  - ElevenLabs für TTS nutzt
  - BitHuman Cloud für Video/Lipsync nutzt
  - In LiveKit Room läuft

---

## 📋 IMPLEMENTIERUNG - SCHRITT FÜR SCHRITT:

### **1. Modal Secrets erstellen:**

```bash
# LiveKit Credentials
modal secret create livekit-cloud \
  LIVEKIT_URL="wss://your-project.livekit.cloud" \
  LIVEKIT_API_KEY="APIxxx" \
  LIVEKIT_API_SECRET="xxx"

# BitHuman API Secret
modal secret create bithuman-api \
  BITHUMAN_API_SECRET="sk_bh_xxx"

# OpenAI API Key
modal secret create openai-api \
  OPENAI_API_KEY="sk-proj_xxx"

# ElevenLabs API Key
modal secret create elevenlabs-api \
  ELEVENLABS_API_KEY="xxx" \
  ELEVEN_DEFAULT_VOICE_ID="pNInz6obpgDQGcFmaJgB"

# Firebase Admin (für Voice ID Lookup)
modal secret create firebase-admin \
  FIREBASE_CREDENTIALS='{"type":"service_account",...}'
```

### **2. Agent auf Modal deployen:**

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
modal deploy modal_bithuman_elevenlabs.py
```

**Ihr bekommt URL:**
```
https://your-workspace--bithuman-elevenlabs-agent-join.modal.run
```

### **3. Flutter anpassen:**

In `lib/screens/avatar_chat_screen.dart` (Zeile 553-563):

**VORHER:**
```dart
final orchUrl = AppConfig.orchestratorUrl
    .replaceFirst('wss://', 'https://')
    .replaceFirst('ws://', 'http://');
final agentUrl = orchUrl.endsWith('/')
    ? '${orchUrl}agent/join'
    : '$orchUrl/agent/join';
```

**NACHHER:**
```dart
// Modal Agent URL
final agentUrl = 'https://your-workspace--bithuman-elevenlabs-agent-join.modal.run';
```

**ODER** in `.env`:
```env
ORCHESTRATOR_URL=https://your-workspace--bithuman-elevenlabs-agent-join.modal.run
```

### **4. Firebase Voice ID sicherstellen:**

Jeder Avatar braucht:
```
avatars/{id}/liveAvatar/agentId = "A91XMB7113"
avatars/{id}/training/voice/elevenVoiceId = "pNInz6obpgDQGcFmaJgB"
```

### **5. ElevenLabs Plugin installieren (falls existiert):**

```bash
pip install livekit-plugins-elevenlabs
```

**Falls NICHT existiert:**
- Agent nutzt OpenAI Voice als Fallback
- **IHR MÜSST Custom TTS Wrapper bauen!**

---

## 🎬 ABLAUF WENN USER KLICKT:

```
1. Flutter: "Gespräch starten" Button
   ↓
2. Flutter → Backend: POST /livekit/token
   ← Token, Room Name
   ↓
3. Flutter → LiveKit: Room Join
   ✅ Connected
   ↓
4. Flutter → Modal: POST /join
   Body: {
     "room": "room-abc123",
     "agent_id": "A91XMB7113"
   }
   ↓
5. Modal Agent:
   ├── Lädt Voice ID aus Firebase
   ├── Joined LiveKit Room
   ├── Startet BitHuman Avatar (Video)
   ├── Startet ElevenLabs TTS (Audio)
   └── Startet OpenAI (LLM/STT)
   ↓
6. Flutter: Sieht Avatar Video ✅
   Hört ElevenLabs Voice ✅
```

---

## ⚠️ KRITISCHE PUNKTE:

### **1. ElevenLabs Plugin für LiveKit Agents:**

**PRÜFEN:**
```bash
pip search livekit-plugins-elevenlabs
```

**Falls NICHT existiert:**
Ihr müsst Custom TTS Wrapper schreiben:

```python
from livekit.agents import tts

class ElevenLabsTTS(tts.TTS):
    def __init__(self, voice_id: str, api_key: str):
        self.voice_id = voice_id
        self.api_key = api_key
    
    async def synthesize(self, text: str) -> bytes:
        # HTTP Request zu ElevenLabs API
        import aiohttp
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice_id}",
                headers={"xi-api-key": self.api_key},
                json={"text": text, "model_id": "eleven_monolingual_v1"},
            ) as resp:
                return await resp.read()
```

### **2. BitHuman TTS vs. Custom TTS:**

Im Beispiel-Repo gibt es **KEIN** `tts=` Parameter in `AgentSession`!

**Das bedeutet:**
- BitHuman handled TTS automatisch (mit OpenAI Voice)
- **ABER:** Ihr wollt ElevenLabs!

**LÖSUNG:**
`AgentSession` **MIT** `tts=` Parameter nutzen:

```python
session = AgentSession(
    llm=openai.realtime.RealtimeModel(...),
    vad=silero.VAD.load(),
    tts=elevenlabs.TTS(voice_id=...) # ← HIER!
)
```

### **3. Agent Kosten:**

Modal Pricing:
- **CPU**: ~$0.0001/s = ~$0.36/hour
- **Memory (4GB)**: ~$0.00005/GB/s = ~$0.18/hour
- **Total**: ~$0.54/hour pro aktive Conversation

**Optimization:**
- `keep_warm=1` für schnellere Starts
- Agent automatisch beenden nach Inaktivität

---

## 🚀 NÄCHSTE SCHRITTE:

1. **Modal Secrets erstellen** (siehe oben)
2. **Agent deployen**: `modal deploy modal_bithuman_elevenlabs.py`
3. **Flutter URL anpassen**: `.env` ORCHESTRATOR_URL setzen
4. **Testen**: 
   ```bash
   # Health Check
   curl https://your-workspace--bithuman-elevenlabs-agent-join.modal.run/health
   
   # Agent starten
   curl -X POST https://your-workspace--bithuman-elevenlabs-agent-join.modal.run/join \
     -H "Content-Type: application/json" \
     -d '{"room":"test-room","agent_id":"A91XMB7113"}'
   ```
5. **Flutter App testen**: Gespräch starten!

---

## 📊 ZUSAMMENFASSUNG:

### **WAS FUNKTIONIERT:**
✅ LiveKit Room Join  
✅ Token Generierung  
✅ BitHuman Cloud Avatar  
✅ Firebase Voice ID Storage  

### **WAS FEHLT:**
❌ Agent läuft nirgendwo → **LÖSUNG: Modal Deployment**  
❌ ElevenLabs Integration → **LÖSUNG: Custom TTS oder Plugin**  
❌ Voice ID → Agent Connection → **LÖSUNG: Firebase Lookup**  

### **FINALE LÖSUNG:**
```
Flutter → LiveKit Room
         ↓
       Modal Agent:
       - BitHuman (Video)
       - ElevenLabs (Audio)
       - OpenAI (LLM)
```

---

## 🎯 ERFOLG = WENN:

1. ✅ User klickt "Gespräch starten"
2. ✅ Flutter connected zu LiveKit
3. ✅ Modal Agent started automatisch
4. ✅ User sieht BitHuman Avatar Video
5. ✅ User hört ElevenLabs Custom Voice
6. ✅ Conversation funktioniert natürlich
7. ✅ Lipsync ist synchron mit Audio

---

**STATUS:** 
- Agent Code: ✅ Geschrieben
- Modal Deployment: ⏳ Bereit zum Deployen
- Flutter Integration: ✅ Bereits vorhanden (nur URL ändern)
- Testing: ⏳ Nach Deployment

**NEXT:** Modal Secrets erstellen + `modal deploy` ausführen!

