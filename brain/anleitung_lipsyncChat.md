### ✅ LIVE System - Bithuman Avatar im Chat

**Architektur:**
1. **lipsync-orchestrator (Modal)** → ElevenLabs Audio → LiveKit Room
2. **bithuman-agent (Modal)** → Bithuman Video → LiveKit Room
3. **Flutter App** → Empfängt Audio + Video

**Deployment:**
```bash
# 1. Secret erstellen
modal secret create bithuman-api BITHUMAN_API_SECRET=your_secret

# 2. Agent deployen
modal deploy modal_bithuman_agent.py

# 3. URL in Orchestrator .env setzen
BITHUMAN_AGENT_JOIN_URL=https://romeo1971--bithuman-agent-join.modal.run/join

# 4. Orchestrator neu deployen
modal deploy orchestrator/modal_app.py
```

**Workflow:**
- Flutter App → Join Room → `/agent/join` Call
- Orchestrator → Proxy zu Bithuman Agent (Modal)
- Agent startet → Publisht Video → Flutter empfängt

**Dokumentation:**
- **Deploy:** brain/bithuman/DEPLOY.md
- **Cloud API:** brain/bithuman/LIVEKIT_CLOUD_PLUGIN.md
- **Orchestrator:** MODAL_DEPLOYMENT.md
