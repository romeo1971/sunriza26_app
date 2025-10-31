# Backend-Dateien Status

## ⚠️ WICHTIG

**Production läuft NICHT MEHR über lokale Backend-Services!**

Alle Production-Services laufen jetzt auf:
- **Firebase Cloud Functions** (Memory API, Chat)
- **Modal.com** (Dynamics, BitHuman, Orchestrator)

## Production Services:

### Cloud Functions (Firebase):
- `functions/src/memoryApi.ts` → `avatarMemoryInsert` 
- `functions/src/avatarChat.ts` → `avatarChat`
- URL: `https://us-central1-sunriza26.cloudfunctions.net/`

### Modal Apps:
- Dynamics → `modal_dynamics.py`
- BitHuman Worker → `modal_bithuman_worker.py`
- Orchestrator → `orchestrator/modal_app.py`
- LivePortrait WS → `modal_liveportrait_ws.py`

## Lokale Backend-Dateien (NUR für Entwicklung):

### Deprecated / Nicht mehr für Production:
- ~~`app/main.py`~~ → Ersetzt durch Cloud Functions
- ~~`avatar_backend.py`~~ → Ersetzt durch Modal BitHuman Worker
- ~~`main.py`~~ → Ersetzt durch `/modal_dynamics.py`
- ~~`generate_dynamics_endpoint.py`~~ → Ersetzt durch `/modal_dynamics.py`
- ~~`start_avatar_backend.sh`~~ (Port 8001)
- ~~`start_main_backend.sh`~~ (Port 8002)

### Noch für lokale Tests:
- `requirements.txt` - Dependencies für lokale Entwicklung

## Lokale Tests

Für lokale Dynamics-Tests können Sie weiterhin nutzen:
```bash
cd tools
python generate_idle_from_hero_video.py
```

Das nutzt LivePortrait direkt ohne Backend.

## Production

Production Dynamics laufen auf **Modal.com**:
- Code: `/modal_dynamics.py`
- Setup: `/MODAL_SETUP.md`
- Deploy: `modal deploy modal_dynamics.py`

**URL:** Siehe `modal app show sunriza-dynamics`

