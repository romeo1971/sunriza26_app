# 🚀 Bithuman Agent - Live Deployment

## 1. Modal Secret erstellen

```bash
modal secret create bithuman-api \
  BITHUMAN_API_SECRET=your_secret_from_imaginex
```

## 2. Agent deployen

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
source venv/bin/activate
modal deploy modal_bithuman_agent.py
```

✅ URL: `https://romeo1971--bithuman-agent-join.modal.run`

## 3. Orchestrator konfigurieren

In `.env` (oder Modal Secret `lipsync-orchestrator`):

```env
BITHUMAN_AGENT_JOIN_URL=https://romeo1971--bithuman-agent-join.modal.run/join
```

## 4. Test

```bash
# Health Check
curl https://romeo1971--bithuman-agent-join.modal.run/health

# Agent starten
curl -X POST https://romeo1971--bithuman-agent-join.modal.run/join \
  -H "Content-Type: application/json" \
  -d '{"room": "test-room-123", "agent_id": "A91XMB7113"}'
```

## Workflow

```
1. Flutter App   → Joined LiveKit Room
2. Flutter App   → POST orchUrl/agent/join {"room": "...", "agent_id": "..."}
3. Orchestrator  → POST BITHUMAN_AGENT_JOIN_URL
4. Modal Agent   → Startet Container mit Bithuman Plugin
5. Agent         → Joined Room + Publisht Video Track automatisch
6. Flutter App   → Empfängt Video Track
7. Flutter App   → ✅ Bithuman Avatar sichtbar!
```

## Kosten

- **Idle**: 0€ (min_containers=0)
- **Aktiv**: CPU ~$0.0008/min
- **Timeout**: 60 Min max

## Fertig!

Der Agent läuft jetzt **komplett Live** auf Modal.com mit scale-to-zero.

