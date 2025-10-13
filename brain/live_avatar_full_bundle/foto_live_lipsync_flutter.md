# 2D FOTO → LIVE LIPSYNC (Flutter + ElevenLabs) — **ohne 3D, natürliches Foto**

> **Ziel:** Ein **Hero-Foto** der Person bleibt **natürlich** (keine 3D-Avatare). Im **Live-Chat** spricht der Avatar in **Echtzeit** über **ElevenLabs Streaming**; die Lippen bewegen sich **live**. Kopf/Blinzeln läuft als **subtiler Idle-Loop**. **Latenz-Ziel:** *glass‑to‑glass* **< 400 ms**.

**Kernprinzip:** Wir trennen **Hintergrundbewegung** (vorgerenderter Idle‑Loop aus dem Foto) und **Lippen‑Overlay** (ROI‑Patch, live getrieben durch visemes/phonemes). So bleibt der Look *foto‑real* und die Pipeline ist **echtzeitfähig**.

---

## Architektur (High Level)

```text
[Flutter UI]
  ├─ Video-Layer: Idle-Loop (aus deinem Foto)  —  3–5 s, nahtlos
  └─ Overlay-Layer: Mund-ROI (alpha mask), live gerendert 30–60 FPS

[Realtime Backend]
  ├─ ElevenLabs Streaming TTS (Audio + timestamps)
  ├─ Viseme-Mapper (phoneme → viseme timeline, coarticulation)
  ├─ Lipsync Engine (eine von 3 Varianten, siehe unten)
  └─ WebSocket → Client: viseme events + (optional) tiny ROI-patches

[Transport]
  └─ WebRTC (Audio downlink optional) + WS (events)  → Flutter
```

---

## Komponenten

### 1) **Idle-Loop Builder** (einmalig pro Foto)
- **Input:** `hero.jpg`
- **Output:** `idle.mp4` (3–5 s), 25–30 FPS, **nahtlos loopbar**
- **Inhalt:** Mikro‑Kopfbewegung (±1–2°), leichte Parallaxe, **Augenblinzeln**
- **Technik (leichtgewichtig):**
  - Landmark-basierte 2D‑Warping‑Animation (MeshGrid, 68/468 Punkte)
  - Eye‑Blink via Keyframe (Lid-Warp) oder Sprite‑Swap
- **Warum nicht LivePortrait hier?** Wir verwenden es **nur offline** (einmalig) falls gewünscht — die Live-Latenz ist sonst zu hoch. Der Idle-Loop kann sehr subtil sein und wird wiederverwendet.

### 2) **Lipsync Engine (LIVE)** — *wähle genau EINE Variante*
**Variante A — Sprite‑Viseme (empfohlen für maximale Stabilität & Kostenkontrolle)**
- **Einmalige Asset‑Erstellung:** Aus `hero.jpg` extrahieren wir den **Mund‑ROI** und generieren **10–15 Viseme‑Sprites** (PNG mit Alpha), z. B. anhand einer Disney‑Viseme‑Tabelle (AIY, E, FV, L, MBP, O, U, WQ, Rest, etc.).
- **Laufzeit:** ElevenLabs‑Timestamps → **viseme timeline** → wir **faden/lerpen** zwischen Sprites pro Frame (**co‑articulation smoothing**). 
- **Vorteile:** Ultra‑schnell (shader‑only), **keine GPU‑Last im Backend**, 100 % deterministisch, **Foto‑Look** bleibt erhalten.
- **Anforderung:** Gute Masken (Zähne/Zunge optional), 1× Sprite‑Atlas pro Person.

**Variante B — ROI‑Warp (MeshDeform)**
- **Einmalig:** Erzeuge ein **Deform‑Mesh** (z. B. 16×16 Grid) nur über dem Mund. Definiere pro Viseme **Ziel‑Offsets**. 
- **Laufzeit:** Interpoliere Mesh‑Offsets je viseme‑Wert; rendere als **Shader** in Flutter (Impeller `FragmentProgram`) oder nativ (Metal/Vulkan) via Plugin.
- **Vorteile:** Keine Artefakt‑Kanten, **flüssiger** als Sprites, bleibt 2D‑Foto‑Look.
- **Anforderung:** Mehr Setup (Mesh‑Design), dafür **keine Zusatz‑Assets** pro viseme.

**Variante C — Wav2Lip‑ONNX (ROI‑Only)**
- **Laufzeit‑Modell** (ONNX Runtime, GPU/CPU) rendert nur den **Mund‑Patch** (64‑128 px), restliches Bild = Idle‑Loop.
- **Vorteile:** Automatisch korrekte Koartikulation, robust bei „schwierigen“ Lauten.
- **Trade‑off:** Höherer Compute‑Aufwand; achte auf **FP16**, **IO‑Batching**, ROI‑Cropping und ggf. TensorRT. Nur empfehlen, wenn GPU‑Headroom gesichert ist.

> **Empfehlung:** **Variante A** starten (Sprites), **B** evaluieren (schöner Flow), **C** als Option für „High‑Accuracy‑Kundendemos“. Alle drei sind **ohne 3D** und halten den Foto‑Look.

### 3) **Viseme‑Mapper** (Server)
- **Input:** ElevenLabs **timestamps** (pro Wort/Phonem).
- **Mapping:** Phonem → Viseme (z. B. 12–15 Klassen). 
- **Co‑articulation:** Overlap‑Fenster (±60–120 ms), Smoothing (exp. decay).
- **Output:** Stream `{ t_ms, {viseme: weight}[] }` per WebSocket.

### 4) **Flutter‑Client**
- **Layer 0:** `video_player` (Idle‑Loop, Autoplay, Loop).
- **Layer 1:** `CustomPainter` **oder** `FragmentProgram` (Shader) für **Sprite‑Atlas** / **Mesh‑Warp** (Var. A/B).
- **Events:** WS‑Listener → (t, viseme) anwenden; **Clock‑Sync** via Server‑PTS oder NTP.
- **Barge‑in:** `STOP` → sofortige Ramp‑down der visemes (100–200 ms), audio fade.

---

## API‑Contracts

```http
# Avatar (einmalig pro Nutzer)
POST /avatarize-2d
  files: hero_image
  ret: { avatar_id, idle_url, lipsync_assets: { type: "sprites"|"mesh"|"onnx",
                                               atlas_url?: "...",
                                               meshdef_url?: "...",
                                               mask_url: "...",
                                               roi: {x,y,w,h} } }

# Live Session
POST /session-2d
  body: { avatar_id, voice_id }   # ElevenLabs voice_id
  ret:  { session_id, ws_url, (optional) webrtc_audio_url }

# Sprechen
POST /session-2d/{id}/speak
  body: { text, barge_in?: true }
  ret:  { ok: true }

# WebSocket Events (Server → Client)
{
  "type": "viseme",
  "pts_ms": 123456,
  "weights": { "MBP":0.8, "O":0.2 }
}
```

---

## Daten & Assets

### 1) **Sprite‑Atlas** (Variante A)
- `atlas.png` (RGBA, z. B. 2048×1024), Zellen: 4×4 (bis 16 visemes)
- `atlas.json`:
```json
{
  "grid": {"cols": 4, "rows": 4},
  "classes": ["Rest","AI","E","U","O","MBP","FV","L","WQ","R","CH","TH"],
  "mask": "mask_mouth.png",
  "roi": {"x":620,"y":830,"w":360,"h":220}
}
```

### 2) **Mesh‑Definition** (Variante B)
```json
{
  "grid": {"cols":16,"rows":12},
  "roi": {"x":620,"y":830,"w":360,"h":220},
  "targets": {
    "AI": [[dx,dy]... per control point],
    "MBP": [...],
    "...": "..."
  }
}
```

---

## Latenz-Budget (Richtwerte)

- **ElevenLabs first‑audio:** 120–250 ms
- **WS‑Event bis Render (Client):** 10–25 ms
- **Frame render (Shader):** 2–8 ms auf mobilen GPUs
- **Glass‑to‑glass:** 250–400 ms (realistisch)

---

## Kosten (realistisch, 2D‑Pipeline)

- **TTS (ElevenLabs Streaming):** dominiert; z. B. $0.12/min im Pro‑Plan.  
- **Backend‑Compute:** minimal (Var. A/B). **Var. C** braucht GPU‑Zeit (ROI‑Inference).  
- **Transport:** WebSocket‑Events (Bytes‑klein). Kein Video‑SFU nötig (nur wenn du Audio runterlinken willst).  
- **Asset‑Erstellung:** einmalig pro Foto (Sprites/Mesh), automatisierbar.

**Daumenregel pro Live‑Minute:** **$0.12–$0.16** (hauptsächlich TTS).

---

## Implementierungs-Plan (Sprint‑tauglich)

**S1 – Assets/Idle:**
- [ ] Landmark‑Detection + Idle‑Loop‑Renderer (Python CLI).  
- [ ] Sprite‑Atlas‑Generator **oder** Mesh‑Deformer‑Generator.  
- [ ] Masken‑Tool (Feather, Zahn-/Zungen‑Optional).

**S2 – Backend Live:**
- [ ] ElevenLabs Streaming‑Client (WS/gRPC) → Phonem‑Timestamps.  
- [ ] Viseme‑Mapper + Co‑articulation.  
- [ ] WS‑Broadcaster (events) + `/speak`, `/stop` Endpoints.

**S3 – Flutter Client:**
- [ ] Video‑Loop Layer.  
- [ ] Overlay‑Renderer (Sprite/Mesh) mit Clock‑Sync.  
- [ ] Barge‑in/Interrupt + Audio‑Fade.

**S4 – Qualität:**
- [ ] Smoothing‑Filter (exp. decay), clamped lerp.  
- [ ] ROI‑Stabilisierung (sub‑pixel drift).  
- [ ] Optional: Teeth/Tongue detail sprites.

**S5 – Option „High Accuracy“:**
- [ ] Variante C (Wav2Lip‑ONNX‑ROI) Feature‑Flag + GPU‑Benchmark.  

---

## Flutter – Overlay (Sprite‑Atlas) Beispiel (Kurz)

```dart
class VisemeOverlayPainter extends CustomPainter {
  final Image atlas; final Map<String, Rect> cells;
  final String current; final double alpha;
  final Rect roi; // Zielrechteck auf dem Video

  VisemeOverlayPainter(this.atlas, this.cells, this.current, this.alpha, this.roi);

  @override
  void paint(Canvas c, Size s) {
    final src = cells[current] ?? cells["Rest"]!;
    final dst = roi;
    final p = Paint()..isAntiAlias = true..filterQuality = FilterQuality.high;
    c.drawImageRect(atlas, src, dst, p..color = Color.fromRGBO(255,255,255,alpha));
  }
  @override bool shouldRepaint(covariant VisemeOverlayPainter old) =>
      old.current != current || old.alpha != alpha;
}
```

---

## FAQ (für dein Team)

**„Warum kein 3D?“**  
Nicht nötig. Foto‑Look bleibt mit Idle‑Loop + Overlay **fotoreal** und **live‑fähig**.

**„Warum nicht LivePortrait live?“**  
Renderzeit pro Clip (Sekunden) → ungeeignet für sub‑Sekunden‑Dialog.

**„Was, wenn Phil‑Lauten schlecht aussehen?“**  
Sprite‑Atlas um 2–3 Klassen erweitern (TH, CH) und Koartikulation‑Smoothing rauf.

**„Brauchen wir WebRTC?“**  
Nur wenn der Client **Audio** vom Server bekommen soll. Für reine Lippen‑Events reicht **WebSocket**. (Audio spielt lokal mit ElevenLabs? Dann WS + lokales Audio‑Play.)

**„Wie skalieren wir?“**  
Events sind leichtgewichtig; der Flaschenhals ist TTS. Horizontal über Sessions skalieren. Variante C benötigt GPU‑Pools.
