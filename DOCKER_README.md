# BitHuman Avatar App mit Docker + OrbStack

Diese App kombiniert BitHuman SDK, LiveKit, ElevenLabs TTS und Flutter in Docker-Containern.

## Voraussetzungen

### 1. OrbStack installieren (empfohlen für macOS)
```bash
# OrbStack von https://orbstack.dev herunterladen und installieren
# OrbStack ist ein Docker Desktop Ersatz mit besserer Performance
```

### 2. API Keys konfigurieren
Erstelle eine `.env` Datei im Projektverzeichnis:

```bash
# BitHuman API Keys
BITHUMAN_API_SECRET=DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ
BITHUMAN_API_TOKEN=your_bithuman_token_here

# OpenAI API Key
OPENAI_API_KEY=your_openai_key_here

# ElevenLabs API Keys
ELEVENLABS_API_KEY=your_elevenlabs_api_key_here
ELEVENLABS_VOICE_ID=pNInz6obpgDQGcFmaJgB

# LiveKit Configuration
LIVEKIT_URL=ws://localhost:17880
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=UPivas8PQvWiYhubkqxqfkY8kfB9TgGj
```

### 3. Avatar Modelle hinzufügen
Lade `.imx` Modelle von BitHuman herunter und platziere sie in `./models/`:

```bash
models/
└── YourModel.imx
```

## Starten der Anwendung

### Mit OrbStack (empfohlen)
```bash
# Alle Services starten
docker compose up

# Im Hintergrund starten
docker compose up -d

# Logs anzeigen
docker compose logs -f

# Stoppen
docker compose down
```

### Mit Docker Desktop
```bash
# Gleiche Befehle wie oben
docker compose up
```

## Services

Die App läuft mit folgenden Services:

1. **LiveKit** (Port 17880-17881) - WebRTC Kommunikation
2. **Agent** - BitHuman Avatar + OpenAI Integration
3. **Frontend** (Port 4202) - Flutter Web App
4. **Redis** - Message Broker

## Zugriff

- **Flutter App**: http://localhost:4202
- **LiveKit API**: ws://localhost:17880

## Entwicklung

### Agent Code bearbeiten
```bash
# Agent Code bearbeiten
vim agent.py

# Service neu starten
docker compose restart agent
```

### Logs anzeigen
```bash
# Alle Logs
docker compose logs -f

# Nur Agent Logs
docker compose logs -f agent

# Nur Frontend Logs
docker compose logs -f frontend
```

### Clean Restart
```bash
# Alles stoppen und Volumes löschen
docker compose down -v

# Neu bauen und starten
docker compose up --build
```

## Troubleshooting

### Services starten nicht?
- Prüfe `.env` Datei mit gültigen API Keys
- Stelle sicher, dass `models/` Verzeichnis `.imx` Dateien enthält
- Führe `docker compose logs [service]` aus um Fehler zu sehen

### Port Konflikte?
- Frontend: Port 4202
- LiveKit: Ports 17880-17881 und UDP 50700-50720

### Performance Probleme?
- Verwende OrbStack statt Docker Desktop für bessere Performance
- OrbStack ist speziell für Apple Silicon optimiert

## BitHuman Integration

Diese App verwendet das offizielle BitHuman Docker-Beispiel:
- https://github.com/bithuman-prod/public-docker-example
- LiveKit für WebRTC Kommunikation
- BitHuman SDK für Avatar-Animation
- OpenAI für Sprachverarbeitung
