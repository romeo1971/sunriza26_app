# MuseTalk Realtime Lipsync – Support Request

Hi MuseTalk Team,

we are integrating MuseTalk realtime lipsync into our production stack and need assistance to get audio‑conditioned lipsync reliably working. Below is our setup and current behavior.

## Our Architecture (high level)

- Client: Flutter app (iOS/macOS dev), joins a LiveKit Cloud room. The app streams ElevenLabs TTS prompts and shows an idle.mp4 (or pre‑extracted frames.zip) for the avatar.
- Orchestrator (FastAPI on Modal):
  - Mints LiveKit tokens.
  - Starts a MuseTalk session via `/session/start` (URL-first: `frames_zip_url` preferred, fallback `idle_video_url`).
  - Opens a persistent WS `/audio` to MuseTalk and forwards PCM (from ElevenLabs streaming) to MuseTalk.
  - Also publishes a server-side LiveKit audio track (48 kHz) for low-latency remote playback (no client HTTP buffering).
- MuseTalk service (on Modal): loads weights and runs realtime inference, connects to the same LiveKit room or streams via RTMP fallback if needed.

## Media Inputs

- Preferred: `frames_zip_url` (PNG frames) hosted on Firebase Storage (public URL with token).
- Fallback: `idle_video_url` (mp4) if frames.zip is not provided.

## Models/Configs (inside the container)

- UNet v1.5: `/root/MuseTalk/models/musetalkV15/unet.pth` (exists, ~3.4 GB)
- UNet config JSON: `/root/MuseTalk/models/musetalkV15/musetalk.json` (exists)
- VAE: `/root/MuseTalk/models/sd-vae-ft-mse/*` (exists)
- Inference YAML: `/root/MuseTalk/configs/inference/test.yaml` (used for IO paths only; we understand that UNet config is in JSON, not YAML)

Debug endpoint shows (example):
```json
{
  "config_path": "/root/MuseTalk/configs/inference/test.yaml",
  "config_has_unet_config": false,
  "files": {
    "unet.pth": {"exists": true},
    "musetalk.json": {"exists": true},
    "sd-vae-ft-mse/*": {"exists": true}
  }
}
```

## Audio Conditioning Path

- ElevenLabs WS streaming provides PCM (nominally 16 kHz). Orchestrator normalizes to int16 LE; MuseTalk `/audio` WS receives raw PCM bytes.
- We also provide the LiveKit room info so MuseTalk can publish its video to the same room.

## Current Behavior

- LiveKit connect and room join are fast (~1.5s), stable.
- MuseTalk `/session/start` returns 200 and connects to LiveKit.
- We see PCM messages flowing end-to-end.
- The server-side audio publisher (Orchestrator) is active; however, we still do not see lipsync movement published by MuseTalk, and the audience hears no speech from the avatar side (video track present or missing depending on run).

## What We Tried

1. Verified model asset presence (UNet, JSON config, VAE).
2. URL-first startup for MuseTalk with `frames_zip_url` (avoids large base64 bodies).
3. PCM normalization (float32→int16) and ensured consistent sample rate toward MuseTalk.
4. Implemented RTMP fallback for MuseTalk when WebRTC fails.
5. Ensured `auto_subscribe=false` on MuseTalk’s own room connection and correct token passing.
6. Client-side: no local HTTP audio playback; we rely on server-side WebRTC audio track and PCM to MuseTalk.

## Questions

1. What exact PCM format does the MuseTalk realtime `/audio` endpoint expect (sample rate, channels, bit depth, framing)? Is raw int16 mono at 16 kHz correct, or do you expect float32/other framing?
2. Is there any required warm-up or minimum PCM duration before MuseTalk starts outputting lipsync frames?
3. Are there constraints on `frames_zip_url` (image size, count, ordering) we should enforce to guarantee lipsync output?
4. For LiveKit: should MuseTalk connect and publish the video track itself, or is there an official recommended RTMP path? Any SDK version constraints for the Python client?
5. Does the UNet v1.5 path require any specific JSON fields beyond those in `musetalk.json`? Any version pinning you recommend?
6. Known causes when `/session/start` returns 200 and PCM flows, but no lipsync frames are published (silent/idle output)? Any diagnostic switches to enable detailed logs?

## Minimal Repro Steps

1. Join LiveKit room from the client.
2. Orchestrator calls MuseTalk `/session/start` with `{ room, frames_zip_url, connect_livekit:true }`.
3. Orchestrator opens `/audio` WS and forwards ElevenLabs PCM immediately.
4. Expectation: MuseTalk publishes a video track with lips moving (conditioned by PCM).

Thanks a lot for any guidance. We can provide additional logs on request (Modal app logs, MuseTalk service logs).

## Fast start / Deployment settings (Modal)

- Orchestrator kept warm for instant joins:
  - `min_containers=1`, `scaledown_window=300` in `orchestrator/modal_app.py`.
  - Health endpoints to verify: `/health` (orchestrator), MuseTalk `/health`.
- Do not redeploy during sessions (avoids cold starts). After deploy, joins stabilize at ~1–2 s.

## Debug endpoints

- Orchestrator: `/debug/audio` → shows publisher status (connected room, source presence, buffer).
- Orchestrator→MuseTalk: `/debug/musetalk` → shows model assets and config (weights present).


