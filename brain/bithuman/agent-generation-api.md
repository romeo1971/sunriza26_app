# bitHuman Agent Generation API

## Übersicht

Die bitHuman Agent Generation API ermöglicht die Erstellung von lebensechten digitalen Avataren (Agents), die auf Audio in Echtzeit reagieren.

## Endpoint

```
POST https://api.bithuman.ai/v1/agents
```

## Authentifizierung

Die API erfordert zwei Authentifizierungs-Header:

```
X-API-Key: {BITHUMAN_API_KEY}
X-API-Secret: {BITHUMAN_API_SECRET}
```

## Request Body

### Multipart Form Data

| Parameter | Typ | Erforderlich | Beschreibung |
|-----------|-----|--------------|--------------|
| `image` | File (JPEG/PNG) | Ja | Das Hero-Image des Avatars |
| `audio` | File (MP3/WAV) | Ja | Das Hero-Audio des Avatars |
| `model` | String | Ja | Modell-Typ: `essence` oder `expression` |
| `name` | String | Optional | Name des Agents (für Referenz) |

### Modell-Typen

- **essence** (default): Optimiert für natürliche, subtile Bewegungen
- **expression**: Optimiert für expressivere, lebhaftere Bewegungen

## Response

### Erfolg (200 OK)

```json
{
  "success": true,
  "agent_id": "agent_abc123xyz",
  "status": "processing",
  "estimated_completion_time": 120
}
```

### Fehler (4xx/5xx)

```json
{
  "success": false,
  "error": "Invalid API credentials",
  "code": "AUTH_ERROR"
}
```

## Status Codes

| Code | Bedeutung |
|------|-----------|
| 200 | Erfolgreich |
| 400 | Ungültige Anfrage (z.B. fehlendes Bild/Audio) |
| 401 | Ungültige Authentifizierung |
| 413 | Datei zu groß |
| 429 | Rate Limit überschritten |
| 500 | Server Fehler |

## Rate Limits

- 10 Requests pro Minute
- 100 Requests pro Tag (Standard-Plan)

## Beispiel-Code (Dart/Flutter)

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<String?> createBitHumanAgent({
  required String imageUrl,
  required String audioUrl,
  required String model,
  required String apiKey,
  required String apiSecret,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.bithuman.ai/v1/agents'),
  );
  
  request.headers['X-API-Key'] = apiKey;
  request.headers['X-API-Secret'] = apiSecret;
  
  request.files.add(await http.MultipartFile.fromPath('image', imageUrl));
  request.files.add(await http.MultipartFile.fromPath('audio', audioUrl));
  request.fields['model'] = model;
  
  final response = await request.send();
  
  if (response.statusCode == 200) {
    final body = await response.stream.bytesToString();
    final data = json.decode(body);
    return data['agent_id'];
  }
  
  return null;
}
```

## Hinweise

- Das Hero-Image sollte idealerweise ein Frontalportrait sein (mindestens 512x512px)
- Das Hero-Audio sollte klar und gut verständlich sein (max. 30 Sekunden)
- Die Agent-Generierung dauert in der Regel 1-3 Minuten
- Die agent_id kann für LiveKit-Integration verwendet werden

## Nächste Schritte

Nach erfolgreicher Agent-Generierung kann der Agent in einen LiveKit Room integriert werden. Siehe: [LiveKit Cloud Plugin](./livekit-cloud-plugin.md)

