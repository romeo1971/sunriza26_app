from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from starlette.websockets import WebSocketState
import os
import json
import base64
import asyncio
import websockets
import datetime as dt
import jwt

app = FastAPI()

ELEVEN_BASE = os.getenv("ELEVENLABS_BASE", "api.elevenlabs.io")
ELEVEN_MODEL = os.getenv("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
ELEVEN_KEY = os.getenv("ELEVENLABS_API_KEY")

@app.get("/health")
async def health():
    return {"ok": True}

LIVEPORTRAIT_WS_URL = os.getenv("LIVEPORTRAIT_WS_URL")  # e.g. wss://.../stream
LIVEKIT_URL = os.getenv("LIVEKIT_URL", "").strip()
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "").strip()
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "").strip()

@app.websocket("/")
async def ws_root(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            msg = await ws.receive_text()
            data = json.loads(msg)
            if data.get("type") == "speak":
                voice_id = data.get("voice_id")
                text = data.get("text", "")
                await stream_eleven(ws, voice_id, text)
            elif data.get("type") == "stop":
                await _safe_send(ws, {"type": "done"})
    except WebSocketDisconnect:
        return


@app.post("/livekit/token")
async def mint_livekit_token(req: Request):
    if not (LIVEKIT_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET):
        raise HTTPException(status_code=500, detail="LiveKit env missing")
    body = await req.json()
    room = (body.get("room") or "sunriza26").strip()
    uid = (body.get("user_id") or "anon").strip()
    avatar_id = (body.get("avatar_id") or "avatar").strip()
    identity = f"{uid}-{avatar_id}"
    now = dt.datetime.utcnow()
    exp = now + dt.timedelta(hours=1)
    payload = {
        "iss": LIVEKIT_API_KEY,
        "sub": identity,
        "name": avatar_id,
        "nbf": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "video": {"room": room, "roomJoin": True}
    }
    token = jwt.encode(payload, LIVEKIT_API_SECRET, algorithm="HS256")
    return {"url": LIVEKIT_URL, "room": room, "token": token}


# --- Simple Publisher control stubs (wire-up) ---
@app.post("/publisher/start")
async def publisher_start(req: Request):
    body = await req.json()
    # Here we would start the real renderer/publisher into LiveKit
    # using LIVEKIT_URL/KEY/SECRET and ElevenLabs stream-input.
    # For now, acknowledge so the client flow works end-to-end.
    return {"status": "started", "room": body.get("room", "sunriza26")}


@app.post("/publisher/stop")
async def publisher_stop(req: Request):
    body = await req.json()
    return {"status": "stopped", "room": body.get("room", "sunriza26")}

async def stream_eleven(ws: WebSocket, voice_id: str, text: str):
    if not ELEVEN_KEY:
        await _safe_send(ws, {"type": "error", "message": "ELEVENLABS_API_KEY missing"})
        return
    url_mp3 = (
        f"wss://{ELEVEN_BASE}/v1/text-to-speech/{voice_id}/stream-input"
        f"?model_id={ELEVEN_MODEL}&output_format=mp3_44100_128"
    )
    url_pcm = (
        f"wss://{ELEVEN_BASE}/v1/text-to-speech/{voice_id}/stream-input"
        f"?model_id={ELEVEN_MODEL}&output_format=pcm_16000"
    )
    headers = [("xi-api-key", ELEVEN_KEY)]  # websockets>=11 erwartet additional_headers
    # Öffne zwei parallele Verbindungen: MP3 (Playback) und PCM (für LivePortrait)
    async with websockets.connect(url_mp3, additional_headers=headers) as ew_mp3:
        # PCM‑Verbindung IMMER öffnen (unabhängig vom LP‑WS); Flutter erhält 'pcm'‑Chunks
        ew_pcm = None
        try:
            ew_pcm = await websockets.connect(url_pcm, additional_headers=headers)
            await ew_pcm.send(json.dumps({
                "text": " ",
                "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "speed": 1},
            }))
        except Exception:
            ew_pcm = None
        # INIT
        await ew_mp3.send(json.dumps({"text": " ", "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "speed": 1}}))
        # TEXT
        await ew_mp3.send(json.dumps({"text": text}))
        if ew_pcm:
            await ew_pcm.send(json.dumps({"text": text}))
        # EOS
        await ew_mp3.send(json.dumps({"text": ""}))
        if ew_pcm:
            await ew_pcm.send(json.dumps({"text": ""}))

        async def loop_mp3():
            async for raw in ew_mp3:
                try:
                    msg = json.loads(raw)
                    if msg.get("audio"):
                        await _safe_send(ws, {
                            "type": "audio",
                            "data": msg["audio"],
                            "format": "mp3_44100_128",
                        })
                    if msg.get("alignment"):
                        al = msg["alignment"]
                        chars = al.get("chars", [])
                        starts = al.get("charStartTimesMs", [])
                        durs = al.get("charDurationsMs", [])
                        for i, ch in enumerate(chars):
                            await _safe_send(ws, {
                                "type": "viseme",
                                "value": ch,
                                "pts_ms": starts[i] if i < len(starts) else 0,
                                "duration_ms": durs[i] if i < len(durs) else 100,
                            })
                    if msg.get("isFinal"):
                        await _safe_send(ws, {"type": "done"})
                        break
                except Exception:
                    continue

        async def loop_pcm():
            if not ew_pcm:
                return
            # PCM‑Chunks direkt an den Flutter‑Client weiterleiten
            async for raw in ew_pcm:
                try:
                    msg = json.loads(raw)
                    if msg.get("audio"):
                        await _safe_send(ws, {
                            "type": "pcm",
                            "data": msg["audio"],
                            "pts_ms": 0,
                        })
                    if msg.get("isFinal"):
                        break
                except Exception:
                    continue

        # Starte beide Loops parallel
        await asyncio.gather(loop_mp3(), loop_pcm())


async def _safe_send(ws: WebSocket, obj: dict):
    """Sendet nur, wenn die Verbindung noch offen ist."""
    try:
        if ws.client_state == WebSocketState.CONNECTED:
            await ws.send_text(json.dumps(obj))
    except Exception:
        # Client bereits weg – ignorieren
        pass
