# bitHuman LiveKit Cloud Plugin

## Übersicht

Das bitHuman LiveKit Cloud Plugin ermöglicht die Integration von bitHuman Agents in LiveKit Rooms für Echtzeit-Interaktion.

## Voraussetzungen

- Generierter bitHuman Agent (agent_id)
- LiveKit Server Setup
- LiveKit SDK Integration in der App

## Integration Flow

1. Agent erstellen via Agent Generation API
2. Agent-ID erhalten
3. LiveKit Room erstellen
4. Agent in Room einladen
5. Audio-Stream an Agent senden
6. Video-Stream vom Agent empfangen

## LiveKit Room Setup

### 1. Room Token Generierung

```dart
import 'package:livekit_client/livekit_client.dart';

Future<String> generateRoomToken({
  required String roomName,
  required String participantName,
  required String apiKey,
  required String apiSecret,
}) async {
  // Token wird server-seitig generiert
  // Siehe LiveKit Server SDK Dokumentation
}
```

### 2. Room Connection

```dart
final room = Room();

await room.connect(
  url: 'wss://your-livekit-server.com',
  token: roomToken,
);
```

## Agent in Room einbinden

### API Endpoint

```
POST https://api.bithuman.ai/v1/agents/{agent_id}/join-room
```

### Request Body

```json
{
  "room_url": "wss://your-livekit-server.com",
  "room_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "participant_name": "BitHuman Agent"
}
```

### Response

```json
{
  "success": true,
  "participant_id": "PA_AgentXYZ",
  "status": "connected"
}
```

## Audio/Video Handling

### Audio Input (zu Agent)

```dart
// Mikrofon-Track publishen
await room.localParticipant?.publishAudioTrack(
  LocalAudioTrack.create(),
);
```

### Video Output (von Agent)

```dart
// Agent Video Track empfangen
room.remoteParticipants.forEach((participant) {
  if (participant.name == 'BitHuman Agent') {
    participant.videoTracks.forEach((track) {
      // Video Track rendern
      final videoTrack = track.track as RemoteVideoTrack;
      // Widget mit videoTrack.renderer verwenden
    });
  }
});
```

## Flutter Widget Beispiel

```dart
class BitHumanAvatarWidget extends StatelessWidget {
  final RemoteVideoTrack videoTrack;
  
  @override
  Widget build(BuildContext context) {
    return VideoTrackRenderer(
      videoTrack,
      fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}
```

## Lifecycle Management

### Agent Aktivierung

```dart
// Agent beginnt zu "sprechen" wenn Audio empfangen wird
// Automatische Lipsync-Animation basierend auf Audio
```

### Agent Deaktivierung

```dart
// Agent verlässt Room automatisch nach Inaktivität
// Oder manuell:
POST /v1/agents/{agent_id}/leave-room
```

## Performance Optimierungen

- Agent rendert mit 25-30 FPS
- Niedrige Latenz: ~100-200ms
- Adaptive Bitrate für verschiedene Netzwerke

## Kosten

- Agent-Generierung: Einmalig
- LiveKit Room Time: Pro Minute
- Bandwidth: Pro GB

## Fehlerbehandlung

```dart
room.addListener(() {
  if (room.connectionState == ConnectionState.disconnected) {
    // Reconnect Logic
  }
});
```

## Best Practices

1. **Agent-Wiederverwendung**: Einen Agent für mehrere Sessions nutzen
2. **Graceful Degradation**: Fallback auf Audio-only bei schlechter Verbindung
3. **Monitoring**: Connection State und Latency überwachen
4. **Cleanup**: Agent aus Room entfernen wenn nicht mehr benötigt

## Unterschied zu Modal.com Services

bitHuman übernimmt:
- ✅ Avatar-Generierung (statt LivePortrait)
- ✅ Lipsync-Animation (statt MuseTalk)
- ✅ Real-time Rendering
- ✅ LiveKit Integration

Nicht mehr benötigt:
- ❌ modal_liveportrait_ws.py
- ❌ modal_musetalk.py
- ❌ modal_dynamics.py (teilweise)

## Troubleshooting

### Agent verbindet nicht

- API Credentials überprüfen
- Room Token validieren
- Network Connectivity prüfen

### Schlechte Video-Qualität

- Bandbreite erhöhen
- Codec-Einstellungen anpassen
- Auflösung reduzieren

### Audio-Sync Issues

- Buffer-Größe anpassen
- Latency Settings optimieren

## Weitere Ressourcen

- [LiveKit Documentation](https://docs.livekit.io)
- [bitHuman API Reference](https://docs.bithuman.ai)
- [Flutter LiveKit SDK](https://pub.dev/packages/livekit_client)

