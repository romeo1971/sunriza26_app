# Beyond Presence (BP) – Integrationsleitfaden für Sunriza

Quelle: [Get Started – Beyond Presence](https://docs.bey.dev/get-started)

Weitere Quellen:
- Plattform/Dashboard: [app.bey.chat](https://app.bey.chat/)
- Integrationen (Managed Agents): [docs.bey.dev/integrations/managed-agents](https://docs.bey.dev/integrations/managed-agents)
- Recording Guide (Avatar‑Aufnahmen): [Notion Recording Guide](https://beyond-presence.notion.site/Beyond-Presence-Avatar-Recording-Guide-22203e3aad818018a577cf119e3967f2)

Dieser Leitfaden fasst die Kernkonzepte und den empfohlenen Integrationspfad zusammen und liefert direkt nutzbare Code‑Snippets (curl/TypeScript/Dart) für unsere App. Ziel: BP als primären Speech‑to‑Video/Lip‑Sync‑Provider nutzen; BitHuman bleibt Fallback.

## Kernkonzepte (aus der Doku)
- Agents: LLM‑gestützte Assistenten (Text/Voice/Video)
- Avatars: Videodarstellung (Lip‑Sync, Mimik, Gestik)
- Dashboard/API: Verwaltung/Programmatische Kontrolle

Siehe Einführungsseite der Doku: [docs.bey.dev/get-started](https://docs.bey.dev/get-started)

## Umgebungsvariablen (App)
Wir verwenden folgende Keys in `.env` (Flutter und Backend):

```
# Beyond Presence
BP_API_BASE_URL=https://api.bey.dev              # Beispiel; aus Dashboard/API beziehen
BP_API_KEY=xxxx                                  # Secret/API‑Key aus Dashboard

# Feature Toggle
BP_PRIMARY=1                                     # 1=BP primär, 0=aus
```

Flutter liest via `flutter_dotenv`, Backend via `python-dotenv`. Keys werden nicht im Client geleakt, wenn wir über Backend‑Proxy gehen (empfohlen).

## High‑Level Flow in Sunriza
1) Avatar anlegen (optional): Referenzbild/Video an BP hochladen, Avatar/Agent ID erhalten.
2) Chat: Begrüßungstext → TTS (entweder via ElevenLabs oder BP) → Speech‑to‑Video bei BP → MP4 Stream/Download → sofort lokal abspielen.
3) Fallback: Wenn BP fehlschlägt, BitHuman verwenden.

## API Workflows (schematisch)

Hinweis: Endpunkte/Namen bitte aus dem BP‑Dashboard/API‑Referenz finalisieren. Diese Beispiele zeigen die Integration abstrakt; sie werden im Backend‑Proxy hinterlegt, damit Keys nicht in Flutter landen.

### 1) Avatar/Asset anlegen (optional)
```bash
curl -X POST "$BP_API_BASE_URL/avatars" \
  -H "Authorization: Bearer $BP_API_KEY" \
  -F "image=@./avatar.png"
```

Response (Schema):
```json
{ "avatarId": "avtr_123", "status": "ready" }
```

### 2) Speech‑to‑Video (Text → Audio → Video Lip‑Sync)
Variante A – BP übernimmt TTS:
```bash
curl -X POST "$BP_API_BASE_URL/speech-to-video" \
  -H "Authorization: Bearer $BP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hallo! Schön, dich zu sehen.",
    "language": "de-DE",
    "avatarId": "avtr_123"
  }' --output out.mp4
```

Variante B – Wir liefern eigenes Audio (ElevenLabs):
```bash
curl -X POST "$BP_API_BASE_URL/speech-to-video" \
  -H "Authorization: Bearer $BP_API_KEY" \
  -F "audio=@./tts.mp3" \
  -F "avatarId=avtr_123"
  --output out.mp4
```

### 3) TypeScript (Backend‑Proxy Beispiel)
```ts
import fetch from "node-fetch";

export async function bpSpeechToVideo({
  baseUrl,
  apiKey,
  text,
  avatarId,
  audioPath,
}: {
  baseUrl: string;
  apiKey: string;
  text?: string;
  avatarId?: string;
  audioPath?: string;
}): Promise<Buffer> {
  const url = `${baseUrl}/speech-to-video`;
  const headers = { Authorization: `Bearer ${apiKey}` };
  if (audioPath) {
    const fd = new (await import("form-data")).default();
    fd.append("audio", (await import("fs")).createReadStream(audioPath));
    if (avatarId) fd.append("avatarId", avatarId);
    const res = await fetch(url, { method: "POST", headers, body: fd as any });
    if (!res.ok) throw new Error(`BP error ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  } else {
    const res = await fetch(url, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ text, avatarId, language: "de-DE" }),
    });
    if (!res.ok) throw new Error(`BP error ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  }
}
```

### 4) Dart (Flutter – ruft unseren Backend‑Proxy)
```dart
final uri = Uri.parse("$MEMORY_API_BASE_URL/bp/speech-to-video");
final res = await http.post(
  uri,
  headers: {"Content-Type": "application/json"},
  body: jsonEncode({
    "text": greetingText,
    "avatarId": avatarId,
  }),
);
if (res.statusCode == 200) {
  final dir = await getTemporaryDirectory();
  final f = File("${dir.path}/bp_${DateTime.now().millisecondsSinceEpoch}.mp4");
  await f.writeAsBytes(res.bodyBytes);
  await VideoStreamService().startStreamingFromUrl(f.path);
}
```

## Integration in Sunriza – Plan
1) Backend‑Proxy Endpunkt `/bp/speech-to-video` (FastAPI):
   - Input: `{ text, avatarId }` oder Multipart mit `audio`
   - Ruft BP API mit `BP_API_KEY` auf, liefert MP4 Bytes zurück
2) Flutter `BeyondPresenceService`:
   - Liest `BP_PRIMARY` und `MEMORY_API_BASE_URL`
   - Methode `generateLipsyncVideo(text|audioPath)` ruft Backend‑Proxy
3) Chat‑Flow Anpassung:
   - `_startLipsync()` prüft `BP_PRIMARY==1` → BP‑Service; sonst BitHuman
   - Video sofort lokal abspielen (kein Upload)
4) „Avatar generieren“:
   - Optional: UI lädt Referenzbild zu BP (Avatar/Asset) und speichert `avatarId`

## Managed Agents Hinweise
- Siehe [Managed Agents](https://docs.bey.dev/integrations/managed-agents): Ermöglicht vorkonfigurierte Agenten über das Dashboard zu steuern und per API aufzurufen.
- Für unsere App: `avatarId`/`agentId` in Firestore unter `training.beyondPresence.avatarId` speichern, der Proxy nutzt diese ID bevorzugt.

## Recording Guide (Qualität)
- Siehe [Recording Guide](https://beyond-presence.notion.site/Beyond-Presence-Avatar-Recording-Guide-22203e3aad818018a577cf119e3967f2) für optimale Referenzvideos/Bilder (Licht, framing, neutraler Hintergrund) zur Verbesserung von Lip‑Sync und Mimik.

## Fehlerbehandlung
- 4xx/5xx vom Proxy → Flutter zeigt Snack, fällt auf BitHuman zurück
- Zeitüberschreitung >60s → abbrechen und Fallback

## Tests
- Begrüßungstext → MP4 mit Audio, Dauer ≈ TTS
- Netzwerkausfall → Fallback greift

---

Siehe auch: [Get Started – Beyond Presence](https://docs.bey.dev/get-started)


