# 🚀 BitHuman + ElevenLabs + Pinecone - COMPLETE SETUP

## ✅ WAS WIR HABEN:

- **BitHuman Cloud**: Avatar Video + Lipsync
- **ElevenLabs**: Custom Voice Clones
- **Pinecone**: Primary Knowledge Base
- **OpenAI**: Fallback wenn Pinecone keine Antwort hat
- **LiveKit Cloud**: Real-time Communication
- **Modal.com**: Agent Hosting
- **Firebase**: Config + Voice ID Storage

---

## 📋 SETUP - SCHRITT FÜR SCHRITT:

### **SCHRITT 1: Modal CLI installieren**

```bash
pip install modal
modal setup
```

Folge den Anweisungen zum Login.

---

### **SCHRITT 2: Modal Secrets erstellen**

```bash
# 1. LiveKit Cloud
modal secret create livekit-cloud \
  LIVEKIT_URL="wss://sunriza-fkglxhd8.livekit.cloud" \
  LIVEKIT_API_KEY="APIfVjpxaNtEGxJ" \
  LIVEKIT_API_SECRET="IhrLivekitSecret"

# 2. BitHuman API
modal secret create bithuman-api \
  BITHUMAN_API_SECRET="sk_bh_IhrBithumanSecret"

# 3. OpenAI API
modal secret create openai-api \
  OPENAI_API_KEY="sk-proj_IhrOpenAIKey"

# 4. ElevenLabs API
modal secret create elevenlabs-api \
  ELEVENLABS_API_KEY="IhrElevenLabsKey" \
  ELEVEN_DEFAULT_VOICE_ID="pNInz6obpgDQGcFmaJgB"

# 5. Pinecone API
modal secret create pinecone-api \
  PINECONE_API_KEY="IhrPineconeKey" \
  PINECONE_INDEX_NAME="sunriza-knowledge"

# 6. Firebase Admin (WICHTIG: JSON als String!)
modal secret create firebase-admin \
  FIREBASE_CREDENTIALS='{"type":"service_account","project_id":"sunriza-26","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"firebase-adminsdk-...@sunriza-26.iam.gserviceaccount.com","client_id":"...","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-...%40sunriza-26.iam.gserviceaccount.com","universe_domain":"googleapis.com"}'
```

**⚠️ Firebase Credentials JSON holen:**
```bash
# Firebase Console → Project Settings → Service Accounts → Generate new private key
# Kopiere den kompletten JSON Content (alles zwischen { ... })
```

---

### **SCHRITT 3: Agent auf Modal deployen**

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
modal deploy modal_bithuman_final.py
```

**Output:**
```
✓ Created objects.
├── 🔨 Created mount /Users/hhsw/Desktop/sunriza/sunriza26/modal_bithuman_final.py
└── 🔨 Created function start_agent => bithuman-complete-agent-start-agent
└── 🔨 Created web function join => https://romeo1971--bithuman-complete-agent-join.modal.run
└── 🔨 Created web function health => https://romeo1971--bithuman-complete-agent-health.modal.run

✅ App deployed!
```

**Notiere die URL:** `https://romeo1971--bithuman-complete-agent-join.modal.run`

---

### **SCHRITT 4: Flutter .env anpassen**

Öffne `/Users/hhsw/Desktop/sunriza/sunriza26/.env`:

```env
# WICHTIG: Setze die Modal URL als Orchestrator
ORCHESTRATOR_URL=https://romeo1971--bithuman-complete-agent-join.modal.run

# Andere Settings bleiben
LIVEKIT_ENABLED=1
LIVEKIT_URL=wss://sunriza-fkglxhd8.livekit.cloud
```

**ODER** wenn ihr `AppConfig.orchestratorUrl` nutzt, ändert das in der Config.

---

### **SCHRITT 5: Test - Agent manuell starten**

```bash
# Health Check
curl https://romeo1971--bithuman-complete-agent-health.modal.run

# Agent für Test-Room starten
curl -X POST https://romeo1971--bithuman-complete-agent-join.modal.run \
  -H "Content-Type: application/json" \
  -d '{
    "room": "test-room-123",
    "agent_id": "A91XMB7113"
  }'
```

**Expected Response:**
```json
{
  "status": "started",
  "room": "test-room-123",
  "agent_id": "A91XMB7113"
}
```

---

### **SCHRITT 6: Firebase Daten prüfen**

Jeder Avatar braucht:

```javascript
// Firebase: avatars/{avatarId}
{
  liveAvatar: {
    agentId: "A91XMB7113"  // ← WICHTIG!
  },
  training: {
    voice: {
      elevenVoiceId: "pNInz6obpgDQGcFmaJgB",  // ← ElevenLabs Voice
      cloneVoiceId: "pNInz6obpgDQGcFmaJgB"     // ← Falls geklont
    }
  },
  userId: "user123",  // ← Für Pinecone Namespace
  name: "Mein Avatar",
  personality: "Du bist ein freundlicher Assistent..."  // ← Optional
}
```

---

### **SCHRITT 7: Pinecone Index prüfen**

```bash
# Pinecone Console: https://app.pinecone.io
# Index Name: sunriza-knowledge
# Dimension: 1536 (für text-embedding-ada-002)
# Metric: cosine
```

**Namespace Format:** `{userId}_{avatarId}` (z.B. `user123_abc456`)

---

### **SCHRITT 8: Flutter App testen**

```bash
# Flutter App starten
cd /Users/hhsw/Desktop/sunriza/sunriza26
flutter run

# Im App:
1. Wähle Avatar
2. Klicke "Gespräch starten"
3. Warte auf LiveKit Connection
4. Agent startet automatisch
5. Spreche mit Avatar!
```

---

## 🎬 ABLAUF WENN USER KLICKT:

```
1. Flutter: User klickt "Gespräch starten"
   ↓
2. Flutter → Backend: POST /livekit/token
   Response: {token, room, url}
   ↓
3. Flutter → LiveKit: Room Join
   ✅ Connected to room-abc123
   ↓
4. Flutter → Modal: POST /join
   Body: {room: "room-abc123", agent_id: "A91XMB7113"}
   ↓
5. Modal Agent startet:
   ├── Lädt Firebase Config (Voice ID, Namespace)
   ├── Initialisiert Pinecone (mit Namespace)
   ├── Initialisiert ElevenLabs TTS
   ├── Joined LiveKit Room
   ├── Startet BitHuman Avatar
   └── Bereit für Conversation
   ↓
6. User spricht → Agent antwortet:
   ├── STT: User Audio → Text
   ├── Pinecone: Query Knowledge Base
   ├── LLM: Falls Pinecone keine Antwort → OpenAI
   ├── TTS: Text → ElevenLabs Voice
   ├── BitHuman: Audio → Lipsync Video
   └── User sieht/hört Avatar
```

---

## 🔍 TROUBLESHOOTING:

### **Agent startet nicht:**

```bash
# Modal Logs checken
modal app logs bithuman-complete-agent

# Oder real-time
modal run modal_bithuman_final.py::start_agent --room test --agent-id A91XMB7113
```

### **Keine Voice / Falshe Voice:**

1. Prüfe Firebase: `training.voice.elevenVoiceId`
2. Prüfe Modal Secret: `ELEVEN_DEFAULT_VOICE_ID`
3. Prüfe ElevenLabs API Key

### **Pinecone antwortet nicht:**

1. Prüfe Namespace: `{userId}_{avatarId}`
2. Prüfe ob Daten im Index: Pinecone Console
3. Prüfe Embedding Model: `text-embedding-ada-002`

### **BitHuman Avatar zeigt nicht:**

1. Prüfe `BITHUMAN_API_SECRET`
2. Prüfe `liveAvatar.agentId` in Firebase
3. Prüfe BitHuman Credits

---

## 💰 KOSTEN PRO CONVERSATION (ca. 10 Min):

- **Modal Agent**: ~$0.09 (CPU + Memory)
- **BitHuman Cloud**: ~$X (eure Credits)
- **ElevenLabs TTS**: ~$0.30 (Character-based)
- **OpenAI Realtime**: ~$0.60 (Audio Minuten)
- **Pinecone Query**: ~$0.01 (Queries)

**Total**: ~$1.00 - $2.00 pro 10-Min Conversation

**Optimization:**
- Modal `keep_warm=1` → Schnellere Starts
- Pinecone Cache → Weniger OpenAI Calls
- Agent Auto-Shutdown nach Inaktivität

---

## ✅ SUCCESS CHECKLIST:

- [ ] Modal CLI installiert
- [ ] Alle 6 Modal Secrets erstellt
- [ ] Agent deployed (URL notiert)
- [ ] Flutter .env aktualisiert
- [ ] Firebase Daten geprüft (`liveAvatar.agentId`, `training.voice`)
- [ ] Pinecone Index existiert
- [ ] Test Agent Start funktioniert
- [ ] Flutter App startet
- [ ] Conversation funktioniert!

---

## 🎯 ERFOLG = WENN:

1. ✅ User klickt "Gespräch starten"
2. ✅ Flutter connected zu LiveKit
3. ✅ Modal Agent startet automatisch
4. ✅ User sieht BitHuman Avatar Video
5. ✅ User hört ElevenLabs Custom Voice
6. ✅ Agent nutzt Pinecone Knowledge Base
7. ✅ Falls Pinecone leer → OpenAI Fallback
8. ✅ Lipsync ist perfekt synchron
9. ✅ Conversation ist natürlich und flüssig

---

**NEXT STEP:** Modal Secrets erstellen und deployen! 🚀

