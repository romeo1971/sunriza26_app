# Live 2D Foto‑Avatar – **Komplettpaket**

**Stack:** Flutter/Dart · Firebase (Hosting/Functions/Storage) · LiveKit Cloud (WebRTC) · ElevenLabs (Voice Clone)  
**Ziel:** Foto bleibt natürlich. Live‑Chat mit perfektem Lipsync. Ein Transport (WebRTC). Sub‑Sekunden Latenz.

---

## 0) Inhalt des Pakets
```
ice_pack/
infra_pack/
  functions/
    src/index.ts
    package.json
    tsconfig.json
ONE_SHOT_firebase_livekit_eleven.md
ICE_foto_live_lipsync_SYSTEM_FULL.md
foto_live_lipsync_flutter.md
wegA_wegB_kosten.md
tools/avatarize2d_cli.py
client/flutter/lib/overlay_avatar.dart
client/flutter/lib/viseme_mixer.dart
```

> Alles Nötige ist drin. Nichts nachladen.

---

## 1) Voraussetzungen
- Node 18+, Python 3.10+, Flutter SDK
- Firebase CLI: `npm i -g firebase-tools`
- LiveKit Cloud Account (URL/Key/Secret)
- ElevenLabs API Key

---

## 2) Firebase initialisieren
```bash
firebase login
firebase init # Hosting + Functions + Storage
```
- Hosting = TLS/HTTPS out of the box. Custom Domain → im Hosting‑Dashboard verbinden (Zertifikate automatisch).

---

## 3) Secrets/Config setzen (Functions)
```bash
cd infra_pack/functions
firebase functions:config:set \
  livekit.url="wss://<your>.livekit.cloud" \
  livekit.key="<LIVEKIT_API_KEY>" \
  livekit.secret="<LIVEKIT_API_SECRET>" \
  eleven.api_key="<ELEVEN_API_KEY>"
```

Installieren & deployen:
```bash
npm i
npm run build
firebase deploy --only functions
```

---

## 4) Avatar‑Assets generieren (einmalig pro Nutzerfoto)
```bash
python tools/avatarize2d_cli.py \
  --photo hero.jpg \
  --out ./avatars/user123 \
  --roi 620,830,360,220 \
  --visemes "Rest,AI,E,U,O,MBP,FV,L,WQ,R,CH,TH"
```
Erzeugt: `idle.mp4`, `atlas.png`, `atlas.json`, `mask.png`, `roi.json`

Upload in Firebase Storage:
```bash
gsutil -m cp -r ./avatars/user123 gs://<your-project>.appspot.com/avatars/
```

**Storage‑Regeln (Beispiel, public read):**
```js
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /avatars/{avatarId}/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

---

## 5) LiveKit Cloud
- Projekt anlegen → `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` erhalten (oben bereits in Functions gesetzt).
- TURN/STUN ist **inklusive**. Kein eigener TURN nötig.

---

## 6) Flutter Projekt – Dependencies
`pubspec.yaml`:
```yaml
dependencies:
  livekit_client: ^1.5.7
  video_player: ^2.8.5
```
Binde ein:
- `client/flutter/lib/overlay_avatar.dart`
- `client/flutter/lib/viseme_mixer.dart`

---

## 7) Client: Join + DataChannel
```dart
final room = Room();
await room.connect(livekitUrl, token); // von /session-live
room.onDataReceived = (participant, buf, kind, topic) {
  final msg = utf8.decode(buf);
  if (topic == "viseme")   onVisemeMessage(msg, mixer);
  if (topic == "prosody")  onProsodyMessage(msg, prosodyState);
};
```
Lade `idle.mp4`, `atlas.png/json`, `mask.png`, `roi.json` aus Firebase Storage (oder Hosting‑URL) und rendere das Overlay (siehe Dateien).

---

## 8) Backend‑Endpoints (Functions)
- `POST /session-live { avatar_id, voice_id }` → gibt `url/token` für LiveKit und DataChannel‑Labels zurück.  
- `POST /speak { text, barge_in?: true }` → triggert ElevenLabs Streaming (Audio + Timestamps) → DataChannels `"viseme"`/`"prosody"`.  
- `POST /stop` → Barge‑in abbrechen.

> Die mitgelieferte `infra_pack/functions/src/index.ts` enthält das Gerüst. Fülle dort die ElevenLabs‑Streaming‑Anbindung/Room‑Publishing.

---

## 9) Qualität (No‑Excuses)
- Smoothing: **critically damped**, keine harten Sprünge
- Koartikulation: ±80–120 ms, **MBP/FV betonen**
- Maske: feather 8–16 px
- Idle‑Loop: dezent (Blinzeln, Mikro‑Pose)
- Latenz: First‑Audio < 250 ms, Glass‑to‑Glass 250–400 ms

---

## 10) Start‑Test (End‑to‑End)
1. Assets generieren & in Storage laden.  
2. Functions deployen.  
3. Flutter App: `/session-live` aufrufen → connect → `idle.mp4` läuft.  
4. `/speak` mit Text → **Audio** + **Viseme/Prosody** kommen live → Lipsync + Mikro‑Mimik sichtbar.  
5. `/stop` → sofortiger Abbruch.

Fertig. Alles in diesem Paket. Keine weiteren Abhängigkeiten außer deinen Keys.
