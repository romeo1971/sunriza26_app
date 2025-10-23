# bitHuman Backend Setup

## Installation

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26/backend

# Python venv erstellen
python3 -m venv venv
source venv/bin/activate

# Dependencies installieren
pip install livekit livekit-agents python-dotenv

# bitHuman LiveKit Plugin installieren
uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman
```

## Environment Variables

Erstelle `.env` in `/backend/`:

```env
BITHUMAN_API_SECRET=your_api_secret_from_imaginex.bithuman.ai
LIVEKIT_URL=wss://your-livekit-server.com
LIVEKIT_API_KEY=your_livekit_key
LIVEKIT_API_SECRET=your_livekit_secret
```

## Usage

### 1. Agent starten

```bash
cd backend
source venv/bin/activate

# Mit Agent ID (von Flutter API erstellt)
python bithuman_livekit_agent.py --agent-id A91XMB7113 --room my-room --model essence
```

### 2. Flutter App verbinden

Flutter App verbindet sich mit demselben Room:

```dart
final room = Room();
await room.connect(
  'wss://your-livekit-server.com',
  roomToken,
);
```

## Workflow

1. **Flutter**: Erstellt Agent via REST API → bekommt `agent_id`
2. **Python**: Startet Agent mit `agent_id` in LiveKit Room
3. **Flutter**: Verbindet sich mit Room
4. **Python**: Avatar reagiert auf Audio aus Room
5. **Flutter**: Empfängt Video vom Avatar

## Troubleshooting

### "No module named 'bithuman'"

```bash
uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman
```

### "No module named 'uv'"

```bash
pip install uv
```

### LiveKit Connection Failed

- Prüfe `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- Teste mit LiveKit CLI: `livekit-cli connect`

## Production Deployment

Für Production sollte der Agent als Service laufen:

```bash
# Systemd Service (Linux)
sudo cp backend/bithuman-agent.service /etc/systemd/system/
sudo systemctl enable bithuman-agent
sudo systemctl start bithuman-agent
```

Oder Docker:

```bash
cd backend
docker build -t sunriza-bithuman-agent .
docker run -d --env-file .env sunriza-bithuman-agent
```

