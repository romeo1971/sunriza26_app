from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from fastapi.responses import StreamingResponse
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
                mp3_needed = data.get("mp3", True)
                await stream_eleven(ws, voice_id, text, mp3_needed=mp3_needed)
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


# --- MuseTalk Publisher Integration ---
MUSETALK_URL = os.getenv("MUSETALK_URL", "https://romeo1971--musetalk-lipsync-v2-asgi.modal.run")

# Active audio streams to MuseTalk (room → websocket)
musetalk_audio_streams = {}

@app.post("/publisher/start")
async def publisher_start(req: Request):
    """Start MuseTalk Real-Time Lipsync"""
    body = await req.json()
    room = body.get("room", "sunriza26")
    idle_video_url = body.get("idle_video_url")  # URL to idle.mp4
    
    if not idle_video_url:
        raise HTTPException(status_code=400, detail="idle_video_url required")
    
    try:
        import httpx
        
        # Download idle video
        print(f"📥 Downloading idle video: {idle_video_url[:100]}...")
        async with httpx.AsyncClient(timeout=60.0) as client:
            video_resp = await client.get(idle_video_url)
            video_resp.raise_for_status()
            video_b64 = base64.b64encode(video_resp.content).decode()
            print(f"✅ Video downloaded: {len(video_resp.content)} bytes")
        
        # Warmup/Healthcheck (Modal kalter Start)
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                await client.get(f"{MUSETALK_URL}/health")
        except Exception:
            pass

        # Start MuseTalk session (mit Retry/Warmup)
        print(f"🚀 Starting MuseTalk session for room: {room}")
        last_exc = None
        for attempt in range(3):
            try:
                async with httpx.AsyncClient(timeout=180.0) as client:
                    resp = await client.post(
                        f"{MUSETALK_URL}/session/start",
                        json={"room": room, "video_b64": video_b64},
                    )
                    if resp.status_code == 200:
                        print(f"✅ MuseTalk session started")
                        break
                    else:
                        error_detail = resp.text
                        print(f"⚠️ MuseTalk start failed (try {attempt+1}/3): {resp.status_code} - {error_detail}")
                        last_exc = HTTPException(status_code=500, detail=f"MuseTalk failed: {error_detail}")
            except Exception as e:
                last_exc = e
                print(f"⚠️ MuseTalk start error (try {attempt+1}/3): {e}")
            # kleiner Backoff
            await asyncio.sleep(0.6)
        if last_exc and '✅' not in locals():
            raise HTTPException(status_code=500, detail=str(last_exc))
        
        # Open WebSocket for audio streaming
        print(f"🔌 Opening audio WebSocket...")
        import websockets
        ws_url = f"{MUSETALK_URL.replace('https://', 'wss://')}/audio"
        ws = await websockets.connect(ws_url)
        await ws.send(room.encode())  # Send room name first
        musetalk_audio_streams[room] = ws
        print(f"✅ Audio stream connected")
        
        return {"status": "started", "room": room}
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print(f"❌ Publisher start error: {error_msg}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/publisher/stop")
async def publisher_stop(req: Request):
    """Stop MuseTalk Real-Time Lipsync"""
    body = await req.json()
    room = body.get("room", "sunriza26")
    
    try:
        import httpx
        
        # Close audio stream (best effort)
        try:
            if room in musetalk_audio_streams:
                await musetalk_audio_streams[room].close()
                del musetalk_audio_streams[room]
        except Exception:
            pass
        
        # Stop session (best effort, nicht blockierend)
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                await client.post(
                    f"{MUSETALK_URL}/session/stop",
                    json={"room": room},
                )
        except Exception:
            pass
        
        return {"status": "stopped", "room": room}
        
    except Exception:
        # Niemals 500 beim Stop zurückgeben – Client-Fluss muss stabil bleiben
        return {"status": "stopped", "room": room}

async def stream_eleven(ws: WebSocket, voice_id: str, text: str, mp3_needed: bool = True):
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
    # Optional MP3‑Stream (für HTTP-Streaming verwenden wir separaten Endpoint)
    ew_mp3 = None
    if mp3_needed:
        ew_mp3 = await websockets.connect(url_mp3, additional_headers=headers)

    # PCM‑Verbindung IMMER öffnen (unabhängig vom LP‑WS); Flutter erhält 'pcm'‑Chunks
    if True:
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
        if ew_mp3:
            await ew_mp3.send(json.dumps({"text": " ", "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "speed": 1}}))
        # TEXT
        if ew_mp3:
            await ew_mp3.send(json.dumps({"text": text}))
        if ew_pcm:
            await ew_pcm.send(json.dumps({"text": text}))
        # EOS
        if ew_mp3:
            await ew_mp3.send(json.dumps({"text": ""}))
        if ew_pcm:
            await ew_pcm.send(json.dumps({"text": ""}))

        async def loop_mp3():
            if not ew_mp3:
                return
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
                        # Sende an Flutter
                        await _safe_send(ws, {
                            "type": "pcm",
                            "data": msg["audio"],
                            "pts_ms": 0,
                        })
                        
                        # Stream audio to MuseTalk (for lipsync)
                        audio_b64 = msg["audio"]
                        audio_bytes = base64.b64decode(audio_b64)
                        
                        # Send to all active MuseTalk streams
                        for room, musetalk_ws in list(musetalk_audio_streams.items()):
                            try:
                                await musetalk_ws.send(audio_bytes)
                            except Exception as e:
                                print(f"⚠️ MuseTalk stream error: {e}")
                                # Remove broken connection
                                del musetalk_audio_streams[room]
                        
                    if msg.get("isFinal"):
                        break
                except Exception:
                    continue

        # Starte beide Loops parallel
        await asyncio.gather(loop_mp3(), loop_pcm())


@app.get("/tts/stream")
async def tts_stream(voice_id: str, text: str):
    if not ELEVEN_KEY:
        raise HTTPException(status_code=500, detail="ELEVENLABS_API_KEY missing")
    url_mp3 = (
        f"wss://{ELEVEN_BASE}/v1/text-to-speech/{voice_id}/stream-input"
        f"?model_id={ELEVEN_MODEL}&output_format=mp3_44100_128"
    )

    headers = [("xi-api-key", ELEVEN_KEY)]

    async def gen():
        try:
            async with websockets.connect(url_mp3, additional_headers=headers) as ew_mp3:
                # init
                await ew_mp3.send(json.dumps({"text": " ", "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "speed": 1}}))
                # text
                await ew_mp3.send(json.dumps({"text": text}))
                # eos
                await ew_mp3.send(json.dumps({"text": ""}))

                async for raw in ew_mp3:
                    try:
                        msg = json.loads(raw)
                        if msg.get("audio"):
                            yield base64.b64decode(msg["audio"])
                        if msg.get("isFinal"):
                            break
                    except Exception:
                        continue
        except Exception as e:
            # end stream on error
            return

    return StreamingResponse(gen(), media_type="audio/mpeg")


async def _safe_send(ws: WebSocket, obj: dict):
    """Sendet nur, wenn die Verbindung noch offen ist."""
    try:
        if ws.client_state == WebSocketState.CONNECTED:
            await ws.send_text(json.dumps(obj))
    except Exception:
        # Client bereits weg – ignorieren
        pass
