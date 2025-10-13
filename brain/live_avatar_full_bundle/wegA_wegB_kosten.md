# Live-Chat Avatar – Weg A (empfohlen) & Weg B (später)

> **Ziel:** 1‑Klick vom **Hero-Foto** zum **animierbaren Avatar** für **echten Live‑Chat** mit **ElevenLabs Voice Clone**.  
> Diese Datei bündelt Architektur, APIs, Setup und **Kostenlogik** für **Weg A** und hält **Weg B** als Option für spätere Eigenentwicklung fest.

---

## Weg A — **ARKit‑Avatar API → NVIDIA Audio2Face (A2F) → UE5/WebRTC → Flutter**

### 1) High‑Level Flow
1. **Avatarize** (einmalig/Nutzer): `hero.jpg` → **Avatar‑API** (z. B. Didimo/AvatarSDK) → `avatar.glb` + `blendshape_map.json` (ARKit).
2. **Session** (live):  
   - **ElevenLabs**: *Streaming with timestamps* (Audio‑Chunks + Timings).  
   - **A2F**: nimmt Audio in Echtzeit → gibt **ARKit‑Blendshape‑Kurven** pro Frame aus.  
   - **UE5/MetaHuman**: wendet Kurven an, encodiert **WebRTC‑Video**.  
   - **Flutter**: zeigt WebRTC‑Stream; `/speak` triggert ElevenLabs; `/stop` = barge‑in.

### 2) API‑Skeleton (Backend)
```http
POST /avatarize (multipart/form-data)
 files: hero_image
 ret: { avatar_id, mesh_url, arkit_map_url }

POST /session
 body: { avatar_id, voice_id }
 ret:  { session_id, webrtc:{room,token}, a2f:{channel}, tts:{stream_id} }

POST /session/{id}/speak
 body: { text, barge_in?: true }
 ret:  { ok: true }

POST /session/{id}/stop
 ret: { ok: true }

DELETE /session/{id}
 ret: { ok: true }
```

### 3) Latenz‑Ziele (Richtwerte)
- First‑audio (LLM→TTS): **120–250 ms**
- Audio→A2F‑Curves: **20–60 ms**
- Curves→Render→Encode: **30–80 ms**
- SFU+Client Jitter: **80–150 ms**
- **Gesamt:** **250–450 ms** glass‑to‑glass

### 4) Minimal‑Implementierung (Module)
- **Orchestrator** (Node/TS): LiveKit‑Room, ElevenLabs Stream‑Client, A2F‑Channel, Pipes.  
- **UE5**: MetaHuman + ARKit‑Mapping (Blueprint), WebRTC Publisher.  
- **Flutter**: WebRTC Player + Chat‑UI (`/speak`, `/stop`).  
- **Storage**: `/static/avatars/<id>/avatar.glb`, `blendshape_map.json`.

---

## **Kosten – Weg A** (transparent & planbar)

> **Komponenten:** Avatar‑API + ElevenLabs (Streaming) + Transport (LiveKit Cloud **oder** self‑host) + GPU für A2F/Render.

### 1) Avatar‑API (einmalige Erstellung pro Nutzer)
- **Metrik:** Preis pro **generiertem Avatar**.  
- **Planung:** Einmalig bei Upload des Hero‑Bildes.  
- **Optimierung:** Cache/Reuse je Nutzer; Re‑Avatarisierung nur bei neuem Foto.

### 2) ElevenLabs (Streaming TTS)
- **Metrik:** **Zeichen‑basiert** (Credits). Streaming nutzt dieselbe Abrechnung.  
- **Daumenregel Text→Audio:** 1 Gesprächsminute ≈ **900–1 200 Zeichen** (Sprache & Tempo abhängig).  
- **Formel:** `EL_cost ≈ chars × (credits/char) × (€/credit)`  
- **Optimierung:** Kürzere Antworten, Prompt‑Kürzung, Re‑use von Standardphrasen.

### 3) Transport / SFU (LiveKit)
- **Option A:** **LiveKit Cloud** (minuten‑/session‑basiert).  
- **Option B:** **Self‑hosted LiveKit** (OSS → eigene Infra‑Kosten).  
- **Optimierung:** Simulcast/SVC, Bandbreiten‑Caps, nur Downlink für Nutzer.

### 4) A2F + Rendering (GPU)
- **Lizenz:** **A2F Open‑Source** → **keine Lizenzgebühr**.  
- **Kosten:** **GPU‑Zeit** (on‑prem oder Cloud) + Strom.  
- **Sizing:** Sessions × (FPS × Auflösung) → GPU‑Instanzen skalieren.  
- **Optimierung:** 720p/30fps reicht oft; Shared GPU über mehrere Sessions mit QoS.

#### **Beispiel‑Schätzung (Pseudocode)**
```text
per_minute_cost ≈ ( avatarize_once / expected_session_minutes )   +
                  ( elevenlabs_chars_per_min * price_per_char )   +
                  ( livekit_per_minute OR self_host_cost_per_min )+
                  ( gpu_cost_per_minute )
```
> Rechne mit **Szenarien** (Avg. 2 min / 5 min / 10 min), um den Korridor zu sehen.

---

## Weg B — **Self‑Hosted „Foto → 3D‑Kopf“** (Info für später)

**Wann sinnvoll?** DSGVO/Compliance, komplette Datenhoheit, IP‑Kontrolle, Kosten bei sehr hohem Volumen, Offline‑/Edge‑Betrieb.

**Bausteine:**
1. **Foto → 3D‑Head**: z. B. **KeenTools FaceBuilder Cloud API** → erzeugt Head‑Mesh.  
2. **Rig/Retargeting**: ARKit‑Blendshapes ableiten (Custom/Helper‑Tools).  
3. **Pipeline**: A2F Realtime → UE5/Renderer → WebRTC (wie Weg A).

**Trade‑offs:** Mehr Setup/Dev‑Zeit, volle Verantwortung für Qualität (Likeness, Retopo, UVs, Materials).

---

## TODO‑Checkliste (Projektstart)

- [ ] `/avatarize` Endpoint + Provider (Weg A) integrieren.  
- [ ] LiveKit (Cloud oder Self‑host) + Token‑Issuer.  
- [ ] ElevenLabs **Streaming with timestamps** in Orchestrator.  
- [ ] A2F Realtime Service anbinden (Audio→ARKit Curves).  
- [ ] UE5/MetaHuman Mapping + Publisher.  
- [ ] Flutter WebRTC Player + Chat‑UI (`/speak`, `/stop`).  
- [ ] Metriken: First‑audio, Curve‑Latency, Glass‑to‑Glass, GPU‑Util.  
- [ ] Kosten‑Dashboard: chars/min, sessions/min, GPU‑min, SFU‑min.

---

### Notizen
- 1 Foto liefert „sehr ähnlich“. Für echtes 1:1 ist **Multi‑Foto** empfehlenswert.  
- `blendshape_map.json` hält dein ARKit→Morph‑Target Mapping (pro Avatar anders).  
- **Barge‑in** immer implementieren (UX & Kosten!).


---

## Kosten – konkrete Zahlen (Weg A)

> **Währung:** USD (für einfache Vergleichbarkeit). Setze unten deine realen EUR‑Werte ein.

### Fixpunkte (Stand: aktuelle Anbieterangaben/öffentliche Pläne)
- **ElevenLabs** (Streaming TTS, Voice Clone): Minutenpreise je Plan  
  – *Pro* ≈ **$0.12/min**, *Scale* ≈ **$0.09/min**, *Business* ≈ **$0.06/min** (Mehrverbrauch, jenseits Inklusivkontingent).  
- **Avatar‑API (Avatar SDK Beispiel)**: **$800/Monat** inkl. **6,000 Avatare** → **$0.133/Avatar** im Kontingent; **$0.03** je **zusätzlichem** Avatar (einmalig je Nutzerfoto).  
- **LiveKit**: **Self‑host** = 0 $ Lizenz (eigene Infra). **Cloud** = nutzungsbasiert (Participant‑Minutes).  
- **NVIDIA Audio2Face**: **Open‑Source** → 0 $ Lizenz. Kosten = **GPU‑Zeit**.

> **GPU‑Daumenwert für Rechnungen:** **€2.00/Stunde** Vollkosten (~ **$0.036/min**). Ersetze durch deinen realen €/h.

### Beispielrechnung pro Live‑Sitzung (ohne Avatar-Erstellung)

| Dauer | ElevenLabs TTS (Pro $0.12/min) | GPU (A2F+Render, $0.036/min) | **Summe** |
|---:|---:|---:|---:|
| **2 min**  | $0.24 | $0.07 | **$0.31** |
| **5 min**  | $0.60 | $0.18 | **$0.78** |
| **10 min** | $1.20 | $0.36 | **$1.56** |

**Interpretation:** Mit Pro‑Plan liegst du bei ca. **$0.15–$0.16 pro Gesprächsminute** (TTS dominiert).  
Wechsel auf **Business** ($0.06/min) halbiert fast den TTS‑Anteil → Gesamt **≈ $0.13–$0.14/min**.

### Einmalig pro Nutzer (Avatar-Erstellung)
- **$0.133/Avatar** (im Kontingent) oder **$0.03** pro **zusätzlichem** Avatar.  
- Auf Sessions umgelegt (z. B. 10 Chats/Nutzer): **$0.013/Sitzung** → vernachlässigbar.

### Wenn du LiveKit **Cloud** nutzt
- Addiere **Participant‑Minutes** je Gespräch (z. B. 2 Teilnehmer × 5 min = 10 PM).  
- Trage deinen Cloud‑Minutenpreis als **`livekit_cost_per_min`** in die Formel unten ein.

### Formeln (einsetzen & in Grafana/Sheets nutzen)
```text
# Variablen
minutes                 = Gesprächsdauer in Minuten
tts_price_per_min       = 0.12   # Pro, oder 0.09 (Scale), 0.06 (Business)
gpu_price_per_min       = 0.036  # aus €/h oder $/h ableiten
livekit_cost_per_min    = 0.00   # 0 bei self-host, sonst Cloud-Wert einsetzen
avatar_cost_one_time    = 0.133  # oder 0.03 bei Zusatz-Avatar

# Kosten pro Sitzung (ohne Avatar)
session_cost = minutes * (tts_price_per_min + gpu_price_per_min + livekit_cost_per_min)

# Avatar-Kosten auf N Sessions umgelegt
avatar_cost_per_session = avatar_cost_one_time / N_sessions_per_user

# Gesamtkosten
total_cost = session_cost + avatar_cost_per_session
```

> **Optimierungshebel:**  
> – Kürzere Antworten (weniger TTS‑Minuten) • Wiederverwendbare Phrasen • 720p/30 statt 1080p/60 • Self‑hosted LiveKit • GPU‑Bündelung (QoS).

