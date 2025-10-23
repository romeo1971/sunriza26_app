# bitHuman Integration - Vollständige Anleitung

## 📚 Dokumentation (1:1 aus PDFs)

- **[AGENT_GENERATION_API.md](./AGENT_GENERATION_API.md)** - REST API zum Erstellen von Agents
- **[LIVEKIT_CLOUD_PLUGIN.md](./LIVEKIT_CLOUD_PLUGIN.md)** - Python Plugin für LiveKit Integration
- **[ENV_SETUP.md](./ENV_SETUP.md)** - Environment Variables Setup
- **[IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)** - Technische Übersicht

## 🚀 Quick Start

### 1. API Credentials holen

Gehe zu https://imaginex.bithuman.ai und hole deinen **API Secret**

### 2. .env erweitern

```env
BITHUMAN_API_SECRET=your_secret_here
```

### 3. Flutter App - Agent erstellen

```dart
// In avatar_details_screen.dart - Dynamics → Live Avatar
// Klicke "Generieren" Button

final agentId = await BitHumanService.createAgent(
  imageUrl: heroImageUrl,
  audioUrl: heroAudioUrl,
  prompt: 'Du bist ...',
);
// → Agent ID wird in Firebase gespeichert
```

### 4. Python Backend - Agent in LiveKit starten

```bash
cd backend
source venv/bin/activate

# Agent mit ID aus Flutter starten
python bithuman_livekit_agent.py --agent-id A91XMB7113 --room my-room
```

### 5. Flutter App - Mit Room verbinden

```dart
// LiveKit Client (haben wir schon)
final room = Room();
await room.connect(livekitUrl, roomToken);

// → Video vom Avatar wird automatisch empfangen
```

## 📋 Was wurde implementiert

### ✅ Flutter (Client)

**Service:** `lib/services/bithuman_service.dart`
- `createAgent()` - Agent via REST API erstellen
- `getAgentStatus()` - Agent Status abfragen
- `waitForAgent()` - Auf Agent-Fertigstellung warten

**UI:** `lib/widgets/expansion_tiles/live_avatar_tile.dart`
- Toggle: essence / expression
- Button: Generieren
- Status-Anzeige: Agent ID

**Integration:** `lib/screens/avatar_details_screen.dart`
- `_generateLiveAvatar()` - Agent-Generierung starten
- `_loadLiveAvatarData()` - Agent ID aus Firebase laden
- Firebase: `liveAvatar` Collection

### ✅ Python Backend (Server)

**Script:** `backend/bithuman_livekit_agent.py`
- Verbindet bitHuman Agent mit LiveKit Room
- Verarbeitet Audio-Input
- Sendet Video-Output

**Setup:** `backend/README_BITHUMAN.md`
- Installation-Anleitung
- Usage-Beispiele
- Troubleshooting

### ✅ Dokumentation

Alle aus PDFs 1:1 übertragen:
- Agent Generation API
- LiveKit Cloud Plugin
- Environment Setup

## 🔄 Workflow

```
1. Flutter: Erstellt Agent    → POST /v1/agent/generate → agent_id
2. Flutter: Speichert in Firebase
3. Python:  Startet Agent     → bithuman.AvatarSession(agent_id)
4. Python:  Verbindet LiveKit → room.connect()
5. Flutter: Verbindet LiveKit → room.connect()
6. Flutter: ← Video vom Avatar
```

## 🛠 Installation

### Flutter (keine neuen Dependencies)

```bash
# Bereits vorhanden:
# - http
# - livekit_client
# - flutter_dotenv
```

### Python Backend

```bash
cd backend

# 1. venv erstellen
python3 -m venv venv
source venv/bin/activate

# 2. Dependencies
pip install livekit livekit-agents python-dotenv

# 3. bitHuman Plugin
uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman
```

## 📊 API Limits

**Free Tier:**
- 199 Credits / Monat
- Community Support

**Pro:**
- Unlimited Credits
- Priority Support
- Custom Training

## 🚨 Troubleshooting

### Agent erstellen schlägt fehl

```dart
// Check Logs:
// "❌ BitHuman API Secret fehlt" → .env prüfen
// "❌ BitHuman API Fehler: 401" → API Secret falsch
// "❌ BitHuman API Fehler: 429" → Rate Limit
```

### Python Agent startet nicht

```bash
# Check Installation:
python -c "import bithuman; print('OK')"

# Check Credentials:
echo $BITHUMAN_API_SECRET
echo $LIVEKIT_URL
```

### LiveKit Connection Failed

- Prüfe `LIVEKIT_URL` (muss `wss://` starten)
- Prüfe API Keys sind korrekt
- Teste mit `livekit-cli connect`

## 📖 Weiterführende Links

- **bitHuman Docs:** https://docs.bithuman.ai
- **imaginex Platform:** https://imaginex.bithuman.ai
- **LiveKit Docs:** https://docs.livekit.io

## ⚠️ WICHTIG

**Dies ist Server-Client Architektur:**
- Flutter App = Client (erstellt Agent, verbindet mit Room)
- Python Script = Server (steuert Agent in Room)
- Beide müssen gleichzeitig laufen!

**Für Production:**
- Python Agent als Service deployen (Systemd/Docker)
- Auto-Start beim Agent-Erstellen aus Flutter
- Health Checks implementieren
