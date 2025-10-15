# Video-Trimming Fix (Oktober 2024)

## Problem
Video-Trimming hat mit `ProcessException: Operation not permitted` fehlgeschlagen, weil ffmpeg direkt auf dem Client ausgeführt wurde (macOS Sandboxing-Problem).

## Lösung
Video-Trimming wurde ins Backend verschoben.

### Backend-Änderungen

**Datei:** `backend/avatar_backend.py`

- ✅ Neues Endpoint: `POST /trim-video`
- ✅ Nimmt `video_url`, `start_time`, `end_time` entgegen
- ✅ Lädt Video herunter, trimmt es mit ffmpeg, gibt getrimmtes Video zurück
- ✅ Port auf 8001 korrigiert

### Flutter-Änderungen

**Datei:** `lib/screens/avatar_details_screen.dart`

- ✅ `_trimAndSaveHeroVideo()` nutzt jetzt Backend-Endpoint
- ✅ Sendet Request an `http://127.0.0.1:8001/trim-video`
- ✅ Lädt getrimmtes Video herunter
- ✅ Lädt es zu Firebase Storage hoch

## Backend starten

```bash
cd backend
source ../venv/bin/activate
uvicorn avatar_backend:app --host 0.0.0.0 --port 8001 --reload
```

Oder mit dem Skript:

```bash
./backend/start_avatar_backend.sh
```

## Anforderungen

- ✅ ffmpeg muss auf dem Backend-Server installiert sein
- ✅ Backend muss auf Port 8001 laufen
- ✅ Backend muss vom Flutter-Client erreichbar sein

## API Docs

Nach dem Start: http://localhost:8001/docs

## Testen

```bash
# Health Check
curl http://127.0.0.1:8001/health

# Trim-Video Test (mit echter URL)
curl -X POST http://127.0.0.1:8001/trim-video \
  -H "Content-Type: application/json" \
  -d '{
    "video_url": "https://example.com/video.mp4",
    "start_time": 0.0,
    "end_time": 10.0
  }'
```

## Deployment auf Google Cloud

1. Backend-Image builden:
```bash
docker build -f backend/Dockerfile.avatar -t gcr.io/PROJECT_ID/avatar-backend .
```

2. Zu GCR pushen:
```bash
docker push gcr.io/PROJECT_ID/avatar-backend
```

3. Cloud Run deployen:
```bash
gcloud run deploy avatar-backend \
  --image gcr.io/PROJECT_ID/avatar-backend \
  --platform managed \
  --region europe-west1 \
  --allow-unauthenticated
```

4. Flutter-App mit Cloud Run URL konfigurieren (.env):
```
AVATAR_BACKEND_URL=https://avatar-backend-xxx.run.app
```

## Fehlerbehebung

**Problem:** "ffmpeg ist nicht installiert"
```bash
# macOS
brew install ffmpeg

# Linux
apt-get install ffmpeg
```

**Problem:** "Backend nicht erreichbar"
- Prüfe ob Backend läuft: `curl http://127.0.0.1:8001/health`
- Prüfe Port: Backend sollte auf 8001 laufen
- Prüfe Firewall-Regeln

**Problem:** "Video konnte nicht geladen werden"
- Prüfe ob Video-URL öffentlich zugänglich ist
- Prüfe Backend-Logs für Details

## Status

✅ Backend implementiert  
✅ Flutter-Client angepasst  
✅ Backend läuft auf Port 8001  
✅ ffmpeg installiert auf Server  
🚀 Bereit für Deployment!

