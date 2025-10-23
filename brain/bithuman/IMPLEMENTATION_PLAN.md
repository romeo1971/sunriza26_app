# bitHuman Implementation Plan

## Was wir brauchen:

### 1. Flutter App (Client)
- ✅ REST API Call: Agent erstellen
- ✅ Agent ID in Firebase speichern  
- ✅ LiveKit Room beitreten (haben wir schon)
- ✅ Video/Audio vom Avatar empfangen

### 2. Python Backend (Server)
- ❌ Python Agent mit LiveKit Plugin
- ❌ Verbindet Agent mit LiveKit Room
- ❌ Steuert bitHuman Avatar

### 3. LiveKit Server
- ✅ Haben wir bereits (Credentials in .env)

## Implementation:

### Phase 1: Flutter - Agent Generation (FERTIG ✅)
```dart
// REST API Call
POST https://public.api.bithuman.ai/v1/agent/generate
Header: api-secret: YOUR_SECRET
Body: {"image": "URL", "audio": "URL", "prompt": "..."}
Response: {"agent_id": "A91XMB7113"}
```

### Phase 2: Python Backend - LiveKit Agent (NEU ❌)
```python
import bithuman
from livekit import agents

bithuman_avatar = bithuman.AvatarSession(
    avatar_id="A91XMB7113",  # von Flutter API
    api_secret="YOUR_SECRET",
    model="expression"  # oder "essence"
)

# Agent in LiveKit Room starten
```

### Phase 3: Flutter - LiveKit Integration (TEILWEISE ✅)
```dart
// Room beitreten (haben wir schon)
// Video Track vom Agent empfangen
// Anzeigen im Chat
```

## Terminal Befehle:

### Python Backend Setup:
```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26/backend
python3 -m venv venv
source venv/bin/activate
pip install livekit livekit-agents
uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman
```

### Flutter bleibt unverändert
- Keine neuen Dependencies
- Nur API Calls anpassen

