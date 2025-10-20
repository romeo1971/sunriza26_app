# 🚀 Modal.com Deployment - Sunriza26

## Aktuelle Modal Apps (Stand: Oktober 2025)

### Produktiv-Apps (deployed, scale-to-zero)

| App | Funktion | GPU | Config | Kosten (idle) |
|-----|----------|-----|--------|---------------|
| **lipsync-orchestrator** | ElevenLabs TTS + LiveKit Audio Publisher | ❌ CPU | `min_containers=0` | **0€** |
| **musetalk-lipsync** | MuseTalk Real-time Lipsync | ✅ T4 | `min_containers=0` | **0€** |
| **liveportrait-ws** | LivePortrait Viseme-Animation | ✅ T4 | `min_containers=0` | **0€** |
| **sunriza-dynamics** | LivePortrait Dynamics Videos | ✅ T4 | `min_containers=0` | **0€** |

**Wichtig:** Alle Apps mit `min_containers=0` → **keine Kosten wenn idle!** [[memory:8273210]]

---

## 📦 1. lipsync-orchestrator

**Datei:** `orchestrator/modal_app.py`  
**URL:** `https://romeo1971--lipsync-orchestrator-asgi.modal.run`

### Funktion
- ElevenLabs TTS Streaming
- LiveKit Token Minting
- MuseTalk Publisher Start/Stop
- LiveKit Audio Publishing (ElevenLabs → LiveKit Room)

### Config
```python
min_containers=0            # scale-to-zero
scaledown_window=60         # 60s Inaktivität → Container stoppt
timeout=1800                # max. 30 Min. pro Session
```

### Secrets (Modal.com)
```bash
modal secret set lipsync-eleven \
  ELEVENLABS_API_KEY=sk_...

modal secret set liveportrait-ws \
  LIVEPORTRAIT_WS_URL=wss://romeo1971--liveportrait-ws-asgi.modal.run/stream

modal secret set livekit-cloud \
  LIVEKIT_URL=wss://sunriza26-g5a1is22.livekit.cloud \
  LIVEKIT_API_KEY=APIz9m... \
  LIVEKIT_API_SECRET=KwDln... \
  LIVEKIT_TEST_ROOM=sunriza26 \
  LIVEKIT_RTMP_URL=rtmps://sunriza26-g5a1is22.rtmp.livekit.cloud/x \
  LIVEKIT_RTMP_KEY=KQYut...
```

### Deploy
```bash
source venv/bin/activate
modal deploy orchestrator/modal_app.py
```

### Test
```bash
curl https://romeo1971--lipsync-orchestrator-asgi.modal.run/health
# → {"ok":true}
```

---

## 🎭 2. musetalk-lipsync

**Datei:** `modal_musetalk.py`  
**URL:** `https://romeo1971--musetalk-lipsync-asgi.modal.run`

### Funktion
- MuseTalk Real-time Lipsync
- Audio-conditioned Frame Generation
- LiveKit Video Publishing (WebRTC oder RTMP Fallback)
- PCM Audio Stream → Lip Movement

### Config
```python
gpu="T4"                    # Tesla T4 für 30 FPS
min_containers=0            # scale-to-zero
scaledown_window=60         # 60s → stop
timeout=3600                # max. 60 Min.
```

### Models (im Image)
- `/root/MuseTalk/models/musetalkV15/unet.pth` (3.4 GB)
- `/root/MuseTalk/models/musetalkV15/musetalk.json` (UNet config)
- `/root/MuseTalk/models/sd-vae-ft-mse/` (VAE)
- `/root/MuseTalk/models/whisper/` (optional, Audio Encoder)

### Deploy
```bash
source venv/bin/activate
modal deploy modal_musetalk.py
```

### Test
```bash
# Health Check
curl https://romeo1971--musetalk-lipsync-asgi.modal.run/health
# → {"status":"ok","service":"musetalk-lipsync","gpu":"cuda"}

# Session Start (benötigt frames_zip_url + LiveKit room)
curl -X POST https://romeo1971--musetalk-lipsync-asgi.modal.run/session/start \
  -H "Content-Type: application/json" \
  -d '{
    "room": "mt-test-123",
    "frames_zip_url": "https://firebasestorage.googleapis.com/.../frames.zip?alt=media&token=...",
    "livekit_token_url": "https://romeo1971--lipsync-orchestrator-asgi.modal.run/livekit/token"
  }'
```

---

## 👤 3. liveportrait-ws

**Datei:** `modal_liveportrait_ws.py`  
**URL:** `wss://romeo1971--liveportrait-ws-asgi.modal.run/stream`

### Funktion
- LivePortrait Viseme-Animation (Realtime)
- WebSocket Streaming
- Viseme → Frame Transformation

### Config
```python
gpu="T4"                    # Tesla T4
min_containers=0            # scale-to-zero (FIX von 1→0!)
scaledown_window=60         # 60s → stop
timeout=3600                # max. 60 Min.
```

### Deploy
```bash
source venv/bin/activate
modal deploy modal_liveportrait_ws.py
```

---

## 🎬 4. sunriza-dynamics

**Datei:** `modal_dynamics.py`  
**URL:** `https://romeo1971--sunriza-dynamics-api-generate-dynamics.modal.run`

### Funktion
- LivePortrait Dynamics Video Generierung
- Firebase Storage Upload
- Avatar Base Image → Dynamics Video

### Config
```python
gpu="T4"
min_containers=0
timeout=600                 # max. 10 Min. pro Video
```

### Secret
```bash
modal secret set firebase-credentials \
  FIREBASE_CREDENTIALS=@service-account-key.json
```

### Deploy
```bash
source venv/bin/activate
modal deploy modal_dynamics.py
```

---

## 🔧 Deployment Checkliste

### Alle Apps deployen
```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
source venv/bin/activate

# 1. Orchestrator (zuerst, da andere Apps davon abhängen)
modal deploy orchestrator/modal_app.py

# 2. MuseTalk
modal deploy modal_musetalk.py

# 3. LivePortrait
modal deploy modal_liveportrait_ws.py

# 4. Dynamics
modal deploy modal_dynamics.py
```

### Secrets prüfen
```bash
modal secret list
# → lipsync-eleven
# → liveportrait-ws
# → livekit-cloud
# → firebase-credentials
```

### Apps Status prüfen
```bash
modal app list
# → Alle "deployed" mit "0" Containern (idle)
```

---

## 💰 Kosten-Optimierung

### Aktuelle Konfiguration (scale-to-zero)
- **Idle:** 0€ (keine Container laufen)
- **Aktiv:** nur Nutzung wird berechnet
  - GPU T4: $0.60/h ≈ $0.01/min
  - CPU: $0.05/h ≈ $0.0008/min

### Beispiel-Rechnung (1 Chat-Session)
1. **Orchestrator** (Audio): 2 Min × $0.0008 = $0.0016
2. **MuseTalk** (Lipsync): 2 Min × $0.01 = $0.02
3. **LivePortrait** (Viseme): 2 Min × $0.01 = $0.02

**Gesamt:** ~$0.04 pro 2-Minuten-Chat

### ⚠️ Alte Fehler (BEHOBEN)
- ❌ `liveportrait-ws` hatte `min_containers=1` → $14/Tag permanent
- ✅ Jetzt: `min_containers=0` → 0€ wenn idle

---

## 🚨 Troubleshooting

### "modal-http: app for invoked web endpoint is stopped"
→ App ist gestoppt, neu deployen:
```bash
modal deploy <app-file>.py
```

### "Secret not found"
→ Secret fehlt, neu setzen:
```bash
modal secret set <secret-name> KEY=value
```

### "GPU quota exceeded"
→ Modal kontaktieren oder auf nächste Stunde warten

### Container läuft permanent (Kosten!)
→ `min_containers` in Code prüfen:
```bash
grep -n "min_containers" modal_*.py orchestrator/modal_app.py
# → alle müssen "0" sein!
```

### Logs anschauen
```bash
# Alte CLI (wenn vorhanden)
modal app logs <app-name> --follow

# Neuere CLI
modal app logs | grep <app-name>

# Oder direkt auf modal.com
# https://modal.com/apps/romeo1971/main/deployed/<app-name>
```

---

## 📊 Monitoring

### Modal Dashboard
https://modal.com/apps/romeo1971/main

Zeigt:
- Deployed Apps
- Container Status (live/stopped)
- Request Count
- GPU Nutzung
- Kosten (aktuell + historisch)

### Health Checks
```bash
# Orchestrator
curl https://romeo1971--lipsync-orchestrator-asgi.modal.run/health

# MuseTalk
curl https://romeo1971--musetalk-lipsync-asgi.modal.run/health

# Dynamics
curl https://romeo1971--sunriza-dynamics-health.modal.run
```

---

## 🔄 Update-Prozess

### Code-Änderung → Deploy
1. Code in lokalem File ändern (z.B. `modal_musetalk.py`)
2. Git commit (optional, aber empfohlen)
3. `modal deploy <file>.py`
4. Modal baut neues Image und deployed automatisch

### Image-Änderung (neue Dependencies)
Modal cached Images → nur neu bauen bei Änderung des `image = modal.Image...` Blocks.

---

## ✅ Fast-Start Optimierung

Siehe separate Doku: `brain/FAST_START_MODAL.md`

**Kurz:**
- Orchestrator warm halten (optional)
- Externe Pings alle 5 Min (optional)
- Aktuell: scale-to-zero → kalter Start ~2-3s (akzeptabel)

---

## 📚 Weitere Dokumentation

- **MuseTalk Integration:** `brain/customer_support_musetalk.md`
- **Fast Start:** `brain/FAST_START_MODAL.md`
- **Lipsync Architektur:** `brain/lipsync_ARCHITECTURE_switchable.md`
- **Modal.com Docs:** https://modal.com/docs

---

**Erstellt:** 2025-10-20  
**Status:** Alle Apps deployed, scale-to-zero, 0€ idle  
**Maintainer:** @romeo1971

