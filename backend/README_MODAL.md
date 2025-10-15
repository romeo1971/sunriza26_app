# Backend-Dateien Status

## ⚠️ WICHTIG

Die Dateien in diesem Verzeichnis (`main.py`, `generate_dynamics_endpoint.py`) werden **NICHT MEHR** für Production genutzt!

**Production läuft jetzt auf Modal.com** (siehe `/modal_dynamics.py`)

## Was noch hier ist:

### Noch benötigt:
- `app/main.py` - Memory Backend (Pinecone/OpenAI) - läuft separat
- `avatar_backend.py` - BitHuman Service - läuft lokal
- `requirements.txt` - Dependencies für lokale Entwicklung

### Nicht mehr benötigt (für Dynamics):
- ~~`main.py`~~ → Ersetzt durch `/modal_dynamics.py`
- ~~`generate_dynamics_endpoint.py`~~ → Ersetzt durch `/modal_dynamics.py`

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

