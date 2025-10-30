# Environment Variables Setup

## Flutter App (.env in Root)

```env
# bitHuman API
BITHUMAN_API_SECRET=your_api_secret_from_imaginex.bithuman.ai

# Existing LiveKit (bleibt unverändert)
LIVEKIT_URL=wss://your-livekit-server.com
LIVEKIT_API_KEY=your_livekit_key
LIVEKIT_API_SECRET=your_livekit_secret

# Existing (andere Services)
FIREBASE_WEB_API_KEY=...
ELEVENLABS_API_KEY=...
# ... rest bleibt gleich
```

## Python Backend (backend/.env)

```env
# bitHuman API
BITHUMAN_API_SECRET=your_api_secret_from_imaginex.bithuman.ai

# LiveKit
LIVEKIT_URL=wss://your-livekit-server.com
LIVEKIT_API_KEY=your_livekit_key
LIVEKIT_API_SECRET=your_livekit_secret
```

## Wo bekomme ich die Credentials?

### 1. BITHUMAN_API_SECRET

1. Gehe zu https://imaginex.bithuman.ai
2. Melde dich an / erstelle Account
3. Klicke auf "Developer Settings" (oben rechts)
4. Unter "API Secrets" → "Reveal" klicken
5. Secret kopieren

### 2. LiveKit Credentials

Du hast diese bereits in deiner aktuellen .env!

```dart
// lib/services/env_service.dart zeigt sie an:
LIVEKIT_URL
LIVEKIT_API_KEY  
LIVEKIT_API_SECRET
```

## Installation Check

### Flutter App

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
flutter run
# Check Logs für: "✅ BitHuman Service initialisiert"
```

### Python Backend

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26/backend
source venv/bin/activate
python -c "import bithuman; print('✅ bitHuman installed')"
```

## Troubleshooting

### "BITHUMAN_API_SECRET nicht in .env gefunden"

- Prüfe ob `.env` Datei im Root existiert
- Prüfe ob `BITHUMAN_API_SECRET=...` Zeile vorhanden ist
- Keine Leerzeichen um `=`
- Kein `;` am Ende

### "ModuleNotFoundError: No module named 'bithuman'"

```bash
cd backend
source venv/bin/activate
uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman
```

### LiveKit Connection Failed

- Prüfe `LIVEKIT_URL` (muss mit `wss://` starten)
- Prüfe `LIVEKIT_API_KEY` und `LIVEKIT_API_SECRET`
- Teste mit: `livekit-cli connect --url $LIVEKIT_URL --api-key $LIVEKIT_API_KEY --api-secret $LIVEKIT_API_SECRET`

