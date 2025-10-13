# 2D FOTO → LIVE LIPSYNC (Flutter + ElevenLabs, WebRTC) — **ICE FINAL**
**Kein 3D. Kein Full-Frame-Renderer.** Ein Transport (**WebRTC**), ein Overlay-Renderer (Sprite‑Atlas), ein **Viseme‑Mapper mit Co‑Articulation** und ein **Prozedural‑Animator** (Kopf/Augen/Brauen). **Diese Datei ist die Referenz.**

## 0) Nutzererlebnis
1. **Hero‑Foto** hochladen → **Avatar aktivieren**.  
2. **Referenz‑Audio** hochladen → **Voice‑Clone** erstellen.  
3. **Live‑Chat** starten → **Echtzeit‑Sprache** mit **perfektem Lipsync**, natürliches Foto bleibt erhalten.

---

## 1) Architektur (eine Route, global skalierbar)

```text
[Flutter Client]
  ├─ WebRTC: empfängt AUDIO + DATA CHANNEL ("viseme")
  ├─ Layer0: Idle-Loop (3–5 s, loop, dezent: blinzeln, mikro-pose)
  ├─ Layer1: Mund-Overlay (Sprite-Atlas + Maske)
  └─ Prozedural-Animator: Augen, Brauen, Mikro-Nick anhand Prosodie

[Orchestrator (Node/TS)]
  ├─ /avatarize-2d (Tools): Idle-Loop + Atlas + Mask + ROI
  ├─ /voice-clone: ElevenLabs Voice aus Referenz-Audio
  ├─ /session-live: öffnet WebRTC-Session (SFU), startet ElevenLabs Streaming
  ├─ eleven_adapter: streamt Audio + Timestamps (phoneme/word)
  └─ viseme_mapper: phoneme→viseme, coarticulation + smoothing → DataChannel

[SFU]
  └─ LiveKit/Janus/Pion – Audio Downlink + DataChannel
```

**Latenz-Ziele (ICE):** First-Audio < **250 ms**, Glass-to-Glass **250–400 ms**.

---

## 2) Events & Daten

### 2.1 Viseme-Event (Server → Client, DataChannel `"viseme"`)
```json
{ "t_ms": 123456, "weights": { "Rest":0.1, "MBP":0.8, "O":0.2 } }
```

**Viseme-Klassen (12–15):** `["Rest","AI","E","U","O","MBP","FV","L","WQ","R","CH","TH"]`

### 2.2 Prosodie-Event (Server → Client, DataChannel `"prosody"`)
```json
{ "t_ms": 123460, "pitch": 212.3, "energy": 0.67, "speaking": true }
```

### 2.3 Overlay-Assets (vom /avatarize-2d)
```
idle.mp4, atlas.png, atlas.json, mask.png, roi.json
```

---

## 3) Prozedural-Animator (Client)
**Eingang:** prosody (pitch/energy/speaking), punctuation cues.  
**Ausgang:** Kopf‑Mikro‑Pose, Brauen‑Hebung, Sakkaden, Blink.

**Regeln (ICE):**
- **Blink**: Poisson(λ≈0.25 Hz), Refraktärzeit 3–5 s, Dauer ≈ 120–180 ms
- **Sakkaden**: 2–3/min im Stillen, 4–6/min beim Sprechen (10–20 ms jumps)
- **Brauen**: `browUp = clamp(α*energy + β*Δpitch, 0, 1)` (α≈0.6, β≈0.4)
- **Kopf-Nick**: bei `, . ? !` → sin‑Puls (±1° über 200 ms), Rate‑Limit 1/s

**Output (pro Frame)** an Overlay‑Renderer:
```json
{ "head": {"rx":0.6,"ry":-0.2}, "brow": {"L":0.3,"R":0.35}, "blink":0.0 }
```

---

## 4) APIs

```http
POST /avatarize-2d
  files: hero_image
  → { avatar_id, idle_url, atlas_url, atlas_meta_url, mask_url, roi }

POST /voice-clone
  body: { ref_audio_url | file, display_name }
  → { voice_id }

POST /session-live
  body: { avatar_id, voice_id }
  → { session_id, webrtc:{url,token}, labels:{viseme:"viseme",prosody:"prosody"} }

POST /session-live/{id}/speak
  body: { text, barge_in?: true }
  → { ok: true }

POST /session-live/{id}/stop → { ok: true }
```

---

## 5) Build-Plan (Sprint‑ready)
- **S1**: Tools `/avatarize-2d` → Assets generieren.  
- **S2**: `eleven_adapter` (Streaming + timestamps), `viseme_mapper` (coarticulation).  
- **S3**: `/session-live` mit SFU (LiveKit SDK), DataChannel‑Broadcast.  
- **S4**: Flutter Overlay `overlay_avatar.dart`, Prosodie‑Animator.  
- **S5**: Barge‑in, Drift‑Sync, Telemetrie, QA‑Suite.

---

## 6) Qualität (No‑Excuses)
- **Smoothing**: critically‑damped, nie „step“.  
- **Co‑Articulation**: ±80–120 ms Fenster, MBP/FV betonen.  
- **Masken**: feather 8–16 px, keine harten Kanten.  
- **Sprites**: konsistente Belichtung; Zähne/Zunge optional.  
- **Idle‑Loop**: dezent, niemals „Gummigesicht“.  
- **ROI**: sub‑pixel exakt; Stabilisierung beim Avatarize‑Step.

---

## 7) Code – wo starten?
- **server/orchestrator/src/index.ts** → REST, WebRTC Session, DataChannels
- **server/orchestrator/src/eleven_adapter.ts** → ElevenLabs‑Streaming‑Client
- **server/orchestrator/src/viseme_mapper.ts** → Mapping + Smoothing
- **client/flutter/lib/overlay_avatar.dart** → Overlay + DataChannel Bindings
- **client/flutter/lib/viseme_mixer.dart** → Filter/Mixer
- **tools/avatarize2d_cli.py** → Assets erzeugen
