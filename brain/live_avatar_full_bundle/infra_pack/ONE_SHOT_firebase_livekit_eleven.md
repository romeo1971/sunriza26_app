# **ONE SHOT** Setup — Live 2D Foto‑Avatar mit **Flutter + Firebase + ElevenLabs + LiveKit Cloud** (inkl. TURN/TLS/Hosting/Observability)

> Diese Anleitung ist **end‑to‑end**. Kein „später“. Alles exakt für **dein Setup**: Cursor/GPT‑5, **Firebase**, **Flutter/Dart**, **Pinecone** (RAG, unabhängig), **ElevenLabs**, **LiveKit Cloud**.  
> Ergebnis: **WebRTC** (Audio + DataChannel) weltweit, Idle‑Loop + Mund‑Overlay (2D), sub‑Sekunden Latenz.

---

## 0) Architektur in deiner Umgebung

```text
[Flutter Client (Android/iOS/Web)]
   ├─ WebRTC via LiveKit SDK → Audio (Downlink) + DataChannel ("viseme","prosody")
   ├─ Idle-Loop Video + Sprite-Overlay (ROI) – alles lokal gerendert
   └─ HTTPS → Firebase Functions (token mint, /session-live, /speak)

[Firebase]
   ├─ Hosting (TLS, CDN, Custom Domain)
   ├─ Storage (Assets: idle.mp4, atlas.png/json, mask.png, roi.json)
   └─ Cloud Functions (Node/TS): LiveKit Token, ElevenLabs Adapter, Viseme Mapper

[LiveKit Cloud]
   └─ SFU (weltweit, TURN/STUN inklusive, keine eigene TURN-Instanz nötig)

[ElevenLabs]
   └─ Streaming TTS + Timestamps (Voice Clone)
```

**Wichtig:** Mit **LiveKit Cloud** brauchst du **keinen eigenen TURN‑Server**. TURN/STUN ist inklusive und global. Eigener coturn ist nur relevant, wenn du komplett self‑hosten willst (nicht erforderlich hier).

---

## 1) Accounts & Keys (einmalig)

1. **Firebase Projekt** (Console)  
   - Aktiv: **Hosting**, **Functions**, **Storage**.
2. **LiveKit Cloud**  
   - Projekt anlegen → **Cloud URL**, **API Key/Secret** notieren.
3. **ElevenLabs**  
   - Account → **API Key**; Voice Clone anlegen.

> Alle Keys in **Firebase Functions** als **Umgebungsvariablen** speichern (nicht im Client!).

---

## 2) Firebase — Projekt initialisieren

```bash
npm i -g firebase-tools
firebase login
firebase init # Hosting, Functions, Storage auswählen (TypeScript für Functions)
```

- **Hosting**: Prod‑URL via Firebase CDN **inkl. TLS** out of the box.  
- **Custom Domain**: Im Hosting‑Dashboard Domain hinzufügen → DNS CNAME setzen → Firebase stellt Zertifikate (Let’s Encrypt) **automatisch** aus. **Fertig**.

---

## 3) LiveKit Cloud — Projekt & API

- In der LiveKit Cloud Console: **Project erstellen** → du erhältst:  
  - `LIVEKIT_URL` (z. B. `wss://<your>.livekit.cloud`)  
  - `LIVEKIT_API_KEY` & `LIVEKIT_API_SECRET`  
- Diese **in Firebase Functions** als **Config** setzen:

```bash
firebase functions:config:set livekit.url="wss://<your>.livekit.cloud" \
  livekit.key="<LIVEKIT_API_KEY>" livekit.secret="<LIVEKIT_API_SECRET>"
```

---

## 4) ElevenLabs — API Key in Functions setzen

```bash
firebase functions:config:set eleven.api_key="<ELEVEN_API_KEY>"
```

---

## 5) Firebase Storage — Assets der Avatare

Ja, **Firebase Storage reicht aus** (mit Hosting/CDN).  
- Bucket: `gs://<your-project>.appspot.com`  
- **Upload**: `idle.mp4`, `atlas.png`, `atlas.json`, `mask.png`, `roi.json` unter `/avatars/<avatar_id>/...`  
- **Security Rules (Beispiel, public read)**:
```java
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /avatars/{avatarId}/{allPaths=**} {
      allow read: if true;         // öffentlich ausliefern
      allow write: if request.auth != null; // nur eingeloggte Nutzer oder Server
    }
  }
}
```
> Für private Auslieferung generiere **signed URLs** in Functions.

---

## 6) Firebase Functions — **Token Mint + Session + Speak**

> Der Server erstellt **AccessTokens** für LiveKit, ruft **ElevenLabs Streaming** und pusht **Viseme/Prosodie** Events in den **LiveKit DataChannel**.

### 6.1 env setzen & deploy
```bash
cd functions
npm i livekit-server-sdk axios ws
firebase deploy --only functions
```

### 6.2 Code (TypeScript) — `functions/src/index.ts`
- Enthält: `/session-live`, `/speak`, `/stop` + Token Mint  
- Nutzt **LiveKit Server SDK**

*(siehe Datei unten im Pack)*

---

## 7) Flutter Client — LiveKit Join + Overlay

**Dependencies in `pubspec.yaml`:**
```yaml
dependencies:
  livekit_client: ^1.5.7
  video_player: ^2.8.5
```

**Join & DataChannel (kondensiert):**
```dart
final room = Room();
await room.connect(livekitUrl, token); // von /session-live

room.onDataReceived = (participant, data, kind, topic) {
  final msg = utf8.decode(data);
  if (topic == "viseme")   onVisemeMessage(msg, mixer);
  if (topic == "prosody")  onProsodyMessage(msg, prosodyState);
};
```

**Overlay‑Renderer**: Nutze die bereits gelieferte `overlay_avatar.dart` (Sprite‑Mix mit Maske im ROI) + `viseme_mixer.dart`.  
**Idle‑Loop**: `video_player` lädt `idle.mp4` aus Firebase Storage (oder Hosting‑URL).

---

## 8) Prozedural‑Animator

- **Prosodie‑Events** (pitch, energy) steuern **Brauen/Backen/Kopfnicken**;  
- **Blink/Sakkaden** als lokale Scheduler im Client;  
- Events kommen über LiveKit **DataChannel** `"prosody"`.

> In `overlay_avatar.dart` Hooks ergänzen: `prosody → eyebrow shader offsets`, `saccade scheduler`, `blink timer`.

---

## 9) TLS / HTTPS / WSS

- **Flutter Web / Browser**: WebRTC verlangt **Secure Context** → deine App muss über **HTTPS** ausgeliefert werden. **Firebase Hosting** erledigt TLS automatisch.  
- **LiveKit URL** ist **WSS** (bereitgestellt von LiveKit Cloud).  
- **TURN**: LiveKit Cloud bringt **STUN/TURN** mit → keine extra Aktion nötig.

*(Nur falls self‑host später: coturn installieren, `turnserver.conf` setzen, DNS `turn.yourdomain.com`, TLS via certbot. Für dich aktuell **nicht nötig**.)*

---

## 10) Observability (ohne Overhead)

- **Firebase**: Cloud Logging & Monitoring (Google Cloud) aktiviert → siehst **Functions‑Logs, Latenz, Fehler**.  
- **Sentry (optional)**: Flutter & Node SDK integrieren → Crash/JS errors.  
- **LiveKit Cloud**: Metrics & Room Stats im Dashboard.

---

## 11) End‑to‑End Test

1) **Avatarize** (lokal/CI) → Assets in **Firebase Storage** hochladen.  
2) **/session-live** aufrufen → erhält **token + url**.  
3) Flutter Client **connect** → `Idle.mp4` läuft, DataChannel gebunden.  
4) **/speak { text }** → ElevenLabs streamt Audio + Timestamps → DataChannel `"viseme"`/`"prosody"` → **Lippen + Mikro‑Mimik** laufen live.  
5) **/stop** → sofortiger Barge‑in.

---

## 12) Qualitäts-Check (ICE)

- First‑Audio < 250 ms, Glass‑to‑Glass 250–400 ms.  
- Keine harten Kanten an der Maske; Lerp smooth; Koartikulation ±80–120 ms.  
- Blinzeln 2–6 s, Sakkaden 4–6/min, Nikker bei Interpunktion.

---

## 13) Security

- **Keys nur in Functions‑Config**, nie im Client.  
- **Tokens** kurzlebig (≤ 10 min), scope: subscribe‑only für Besucher.  
- **Storage‑Rules** restriktiv, ggf. signed URLs.

---

## 14) Was bereits als Code beiliegt (in diesem Pack)

- **Firebase Functions** (TS): `/session-live`, Token Mint, Adapter‑Stubs
- **Flutter**: Overlay Renderer + DataChannel Handler (Sprite‑Mix)
- **Avatarize‑Tool** (Python): Idle‑Loop + Atlas/ROI/Masken

Das ist die **100 %** Vorlage — baubar *sofort*.
