# bitHuman Integration - Übersicht

Diese Integration ermöglicht die Erstellung von Live Avataren mit bitHuman AI.

## Dateien

- `agent-generation-api.md` - Dokumentation der Agent Generation API
- `livekit-cloud-plugin.md` - Dokumentation des LiveKit Cloud Plugins

## Setup

### 1. API Keys

Füge in deiner `.env` Datei hinzu:

```env
BITHUMAN_API_KEY=your_api_key_here
BITHUMAN_API_SECRET=your_api_secret_here
```

### 2. Flutter Integration

Die Integration ist bereits vollständig implementiert:

- **Service**: `lib/services/bithuman_service.dart`
- **UI Widget**: `lib/widgets/expansion_tiles/live_avatar_tile.dart`
- **Integration**: `lib/screens/avatar_details_screen.dart`

## Verwendung

1. Öffne einen Avatar in der `avatar_details_screen`
2. Scrolle zu **Dynamics** → **Live Avatar**
3. Stelle sicher, dass **Hero-Image** und **Hero-Audio** hochgeladen sind
4. Wähle das Modell: **essence** (natürlich) oder **expression** (expressiv)
5. Klicke auf **Generieren**
6. Die **Agent ID** wird automatisch in Firebase gespeichert

## Agent ID Speicherung

Die Agent ID wird in Firestore unter dem Avatar gespeichert:

```json
{
  "liveAvatar": {
    "agentId": "agent_abc123xyz",
    "model": "essence",
    "createdAt": "2025-01-23T12:00:00Z"
  }
}
```

## Nächste Schritte

Nach erfolgreicher Agent-Generierung:

1. Agent ID kann für LiveKit Room Integration verwendet werden
2. Siehe `livekit-cloud-plugin.md` für Room-Integration
3. Chat-Screen kann Agent via LiveKit einbinden

## Modal.com Services

Die folgenden Modal.com Services könnten durch bitHuman ersetzt werden:

- `modal_liveportrait_ws.py` (Avatar-Generierung)
- `modal_musetalk.py` (Lipsync-Animation)
- Teile von `modal_dynamics.py`

## Vorteile

✅ Einfachere Integration  
✅ Bessere Performance  
✅ Real-time Lipsync  
✅ Keine eigene Infrastruktur  
✅ Skalierbar  
✅ Niedrigere Latenz  

## Support

- [bitHuman Docs](https://docs.bithuman.ai)
- [LiveKit Docs](https://docs.livekit.io)

