# Backend Produktion Setup

## Umgebungsvariablen

Für die Produktion müssen folgende Umgebungsvariablen gesetzt werden:

### LivePortrait
```bash
# Pfad zum LivePortrait inference.py Script
export LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
```

**Standard (lokal):**
- `/Users/hhsw/Desktop/sunriza/LivePortrait/inference.py`

**Produktion (Docker/Cloud):**
- `/opt/liveportrait/inference.py` oder
- `/app/LivePortrait/inference.py`

### Python Interpreter

Das Backend verwendet automatisch `sys.executable`, also das Python aus dem aktivierten venv:
- **Lokal:** `/Users/hhsw/Desktop/sunriza/sunriza26/venv/bin/python`
- **Produktion:** Das Python aus dem Container/VM venv

## Start-Scripte

### Lokal (Development)

```bash
# Port 8002 (main.py - Dynamics + Video Trimming)
cd backend
./start_main_backend.sh

# Port 8001 (avatar_backend.py - BitHuman)
./start_avatar_backend.sh
```

### Produktion (Docker)

```dockerfile
# Dockerfile für Backend
FROM python:3.13-slim

# System-Dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /app

# Python Dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# LivePortrait installieren
RUN git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait
WORKDIR /opt/liveportrait
RUN pip install -r requirements.txt

# Pretrained Weights herunterladen (siehe LivePortrait Docs)
# ...

# Backend Code kopieren
WORKDIR /app
COPY backend/ ./backend/

# Umgebungsvariablen
ENV LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
ENV PYTORCH_ENABLE_MPS_FALLBACK="1"

# Port freigeben
EXPOSE 8002

# Backend starten
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8002"]
```

### Produktion (Google Cloud Run / Cloud Functions)

```yaml
# cloudbuild.yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - 'gcr.io/$PROJECT_ID/sunriza-backend:$COMMIT_SHA'
      - '-f'
      - 'backend/Dockerfile'
      - '.'

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - 'gcr.io/$PROJECT_ID/sunriza-backend:$COMMIT_SHA'

  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - 'sunriza-backend'
      - '--image'
      - 'gcr.io/$PROJECT_ID/sunriza-backend:$COMMIT_SHA'
      - '--region'
      - 'europe-west1'
      - '--platform'
      - 'managed'
      - '--allow-unauthenticated'
      - '--set-env-vars'
      - 'LIVEPORTRAIT_PATH=/opt/liveportrait/inference.py'
```

## Abhängigkeiten

### System-Pakete
- `ffmpeg` (für Video-Trimming)
- `git` (für LivePortrait Installation)

### Python-Pakete
Siehe `requirements.txt`:
- `fastapi`
- `uvicorn`
- `torch` (mit CUDA für GPU-Support)
- `opencv-python`
- `tyro` (für LivePortrait)
- `numpy`
- `pillow`
- etc.

## Verzeichnisstruktur (Produktion)

```
/app/
├── backend/
│   ├── main.py                    # Port 8002
│   ├── avatar_backend.py          # Port 8001
│   ├── generate_dynamics_endpoint.py
│   └── requirements.txt
├── LivePortrait/                   # → /opt/liveportrait/
│   ├── inference.py
│   ├── pretrained_weights/
│   └── ...
└── tmp/                           # Temporäre Videos
```

## Wichtige Hinweise

1. **venv aktivieren**: Alle Start-Scripte aktivieren automatisch das venv
2. **sys.executable**: Verwendet immer das Python aus dem aktivierten venv
3. **Umgebungsvariablen**: `LIVEPORTRAIT_PATH` überschreibt den lokalen Pfad
4. **GPU-Support**: Für schnelle Dynamics-Generierung ist CUDA/NVIDIA GPU empfohlen
5. **Temporäre Dateien**: `/tmp` sollte genug Speicher haben (Videos können groß werden)

## Debugging

### Python-Version prüfen
```bash
source venv/bin/activate
python --version
which python
```

### Module prüfen
```bash
python -c "import tyro; print('✅ tyro OK')"
python -c "import torch; print('✅ torch OK')"
python -c "import cv2; print('✅ opencv OK')"
```

### LivePortrait testen
```bash
export LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
python "$LIVEPORTRAIT_PATH" --help
```

