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
import struct
from typing import Optional, Any
import time

try:
    from livekit import rtc
except Exception:
    rtc = None

app = FastAPI()

ELEVEN_BASE = os.getenv("ELEVENLABS_BASE", "api.elevenlabs.io")
ELEVEN_MODEL = os.getenv("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
ELEVEN_KEY = os.getenv("ELEVENLABS_API_KEY")

# --- PCM Utils ---
def _pcm_float32_to_int16le(data: bytes) -> bytes:
    """Convert little-endian float32 PCM [-1,1] to int16 LE."""
    if not data:
        return data
    if len(data) % 4 != 0:
        return data
    try:
        sample_count = len(data) // 4
        floats = struct.unpack('<' + 'f' * sample_count, data)
        ints = [
            32767 if x >= 1.0 else (-32768 if x <= -1.0 else int(x * 32767.0))
            for x in floats
        ]
        return struct.pack('<' + 'h' * sample_count, *ints)
    except Exception:
        return data

def _ensure_int16_le(data: bytes) -> bytes:
    """Heuristically ensure PCM is int16 LE; if it looks like float32, convert."""
    if not data:
        return data
    if len(data) >= 4 and (len(data) % 4 == 0):
        try:
            first = struct.unpack('<f', data[:4])[0]
            if -2.0 <= first <= 2.0:
                converted = _pcm_float32_to_int16le(data)
                if len(converted) == (len(data) // 2):
                    return converted
        except Exception:
            pass
    return data

def _upsample_16k_to_48k_int16le(data: bytes) -> bytes:
    """Naiver 3x-Upsampler (ZOH) 16k → 48k mono int16."""
    if not data:
        return data
    if len(data) % 2 != 0:
        return data
    try:
        samples = struct.unpack('<' + 'h' * (len(data) // 2), data)
        out = []
        for s in samples:
            out.extend((s, s, s))
        return struct.pack('<' + 'h' * len(out), *out)
    except Exception:
        return data

# --- LiveKit Audio Publisher (optional) ---
# Default: aktiv (kein Secret/Flag nötig)
ORCH_PUBLISH_AUDIO = os.getenv("ORCH_PUBLISH_AUDIO", "1").strip() not in ("0", "false", "False")
current_audio_room: Optional[str] = None
last_client_room: Optional[str] = None  # Fallback: letzter room aus speak-Request
_audio48k_buf = bytearray()  # Frames für LiveKit in 20ms Stücken puffern

# --- MuseTalk PCM Forwarder (deaktiviert – wir nutzen pro-Room-Verbindung) ---
ORCH_FORWARD_TO_MUSETALK = os.getenv("ORCH_FORWARD_TO_MUSETALK", "0").strip() not in ("0", "false", "False")
MUSETALK_WS_URL = os.getenv("MUSETALK_WS_URL", "wss://romeo1971--musetalk-lipsync-asgi.modal.run/audio").strip()
_musetalk_ws: Optional[Any] = None
_musetalk_room_sent = False

class _LkAudioPub:
    def __init__(self):
        self._room: Optional["rtc.Room"] = None
        self._source: Optional["rtc.AudioSource"] = None
        self._track: Optional["rtc.LocalAudioTrack"] = None
        self._connected_room: Optional[str] = None

    async def ensure_connected(self, room_name: str):
        if not ORCH_PUBLISH_AUDIO or rtc is None:
            return
        if self._room and self._connected_room == room_name:
            return
        try:
            url = LIVEKIT_URL
            token = None
            token_url = os.getenv("LIVEKIT_TOKEN_URL", "").strip()
            if token_url:
                import httpx
                async with httpx.AsyncClient(timeout=10.0) as client:
                    r = await client.post(token_url, json={"room": room_name, "identity": "orchestrator-audio"})
                    r.raise_for_status()
                    j = r.json()
                    token = j.get("token")
                    url = j.get("url", url)
            else:
                now = dt.datetime.utcnow()
                exp = now + dt.timedelta(hours=1)
                payload = {
                    "iss": LIVEKIT_API_KEY,
                    "sub": "orchestrator-audio",
                    "nbf": int(now.timestamp()),
                    "exp": int(exp.timestamp()),
                    "audio": {"room": room_name, "roomJoin": True},
                }
                token = jwt.encode(payload, LIVEKIT_API_SECRET, algorithm="HS256")

            self._room = rtc.Room(room_options=rtc.RoomOptions(auto_subscribe=True))
            await self._room.connect(url, token)
            self._source = rtc.AudioSource(rtc.AudioSourceOptions())
            self._track = rtc.LocalAudioTrack.create_audio_track("tts", self._source)
            await self._room.local_participant.publish_track(self._track)
            self._connected_room = room_name
            print(f"✅ LiveKit audio publisher connected: room={room_name}")
        except Exception:
            self._room = None
            self._source = None
            self._track = None
            self._connected_room = None

    def publish_pcm16_48k_mono(self, data: bytes):
        if not ORCH_PUBLISH_AUDIO or rtc is None:
            return
        if not self._source or not data:
            return
        samples = len(data) // 2
        try:
            frame = rtc.AudioFrame(
                data=data,
                sample_rate=48000,
                num_channels=1,
                samples_per_channel=samples,
            )
            self._source.capture_frame(frame)
        except Exception:
            return

lk_audio_pub = _LkAudioPub()

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
        # Timeout: WS schließen nach 5 Min Inaktivität
        while True:
            try:
                msg = await asyncio.wait_for(ws.receive_text(), timeout=300.0)
            except asyncio.TimeoutError:
                await ws.close(code=1000, reason="Idle timeout")
                return
            data = json.loads(msg)
            if data.get("type") == "speak":
                voice_id = data.get("voice_id")
                text = data.get("text", "")
                mp3_needed = data.get("mp3", True)
                # Room speichern für Audio-Publishing
                global last_client_room
                room_from_client = data.get("room")
                if room_from_client and isinstance(room_from_client, str) and room_from_client.strip():
                    last_client_room = room_from_client.strip()
                # Einmalige TTS-Session ausführen und danach Verbindung schließen,
                # damit der Container skalieren kann.
                await stream_eleven(ws, voice_id, text, mp3_needed=mp3_needed)
                try:
                    await ws.close(code=1000)
                except Exception:
                    pass
                return
            elif data.get("type") == "stop":
                await _safe_send(ws, {"type": "done"})
                try:
                    await ws.close(code=1000)
                except Exception:
                    pass
                return
    except WebSocketDisconnect:
        return


@app.post("/livekit/token")
async def mint_livekit_token(req: Request):
    if not (LIVEKIT_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET):
        raise HTTPException(status_code=500, detail="LiveKit env missing")
    body = await req.json()
    # room optional: wenn nicht gesetzt, generieren wir einen eindeutigen
    room = (body.get("room") or "").strip()
    if not room:
        uid = (body.get("user_id") or "anon").strip()
        short = uid[:8] if uid else "anon"
        import time
        room = f"mt-{short}-{int(time.time()*1000)}"
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

@app.get("/livekit/token")
async def mint_livekit_token_get(room: Optional[str] = None, user_id: Optional[str] = None, avatar_id: Optional[str] = None):
    if not (LIVEKIT_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET):
        raise HTTPException(status_code=500, detail="LiveKit env missing")
    room = (room or "").strip()
    if not room:
        uid = (user_id or "anon").strip()
        short = uid[:8] if uid else "anon"
        import time
        room = f"mt-{short}-{int(time.time()*1000)}"
    identity = f"{(user_id or 'anon').strip()}-{(avatar_id or 'avatar').strip()}"
    now = dt.datetime.utcnow()
    exp = now + dt.timedelta(hours=1)
    payload = {
        "iss": LIVEKIT_API_KEY,
        "sub": identity,
        "name": (avatar_id or 'avatar').strip(),
        "nbf": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "video": {"room": room, "roomJoin": True}
    }
    token = jwt.encode(payload, LIVEKIT_API_SECRET, algorithm="HS256")
    return {"url": LIVEKIT_URL, "room": room, "token": token}


# --- MuseTalk Publisher Integration ---
# Default auf die produktive, konsolidierte App (ohne -v2)
MUSETALK_URL = os.getenv("MUSETALK_URL", "https://romeo1971--musetalk-lipsync-asgi.modal.run")

# Active audio streams to MuseTalk (room → websocket)
musetalk_audio_streams: dict[str, Any] = {}
# Last time (epoch seconds) we forwarded PCM for a room
musetalk_last_pcm_ts: dict[str, float] = {}
active_publisher_rooms: set[str] = set()

async def _stop_room_internal(room: str):
    """Stoppe alle Streams/Verbindungen für einen Room (automatischer Cleanup)."""
    global current_audio_room, _musetalk_ws, _musetalk_room_sent
    # 1) MuseTalk WS pro Room schließen
    try:
        ws = musetalk_audio_streams.pop(room, None)
        if ws:
            try:
                await ws.close()
            except Exception:
                pass
    except Exception:
        pass
    musetalk_last_pcm_ts.pop(room, None)
    # 2) MuseTalk Session stoppen (best-effort)
    try:
        import httpx
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.post(f"{MUSETALK_URL}/session/stop", json={"room": room})
    except Exception:
        pass
    # 3) LiveKit Audio Publisher trennen
    try:
        await lk_audio_pub.disconnect()
    except Exception:
        pass
    # 4) Globale MuseTalk WS schließen (falls verwendet)
    try:
        if _musetalk_ws:
            await _musetalk_ws.close()
    except Exception:
        pass
    _musetalk_ws = None
    _musetalk_room_sent = False
    # 5) Room-Status zurücksetzen
    current_audio_room = None

async def _mt_idle_watcher(room: str, ws: Any, idle_seconds: int = 20):
    """Close MuseTalk WS when no PCM has been forwarded for idle_seconds."""
    try:
        while True:
            await asyncio.sleep(5)
            last = musetalk_last_pcm_ts.get(room, 0.0)
            if last <= 0:
                # No activity tracked yet → wait a bit more
                continue
            if time.time() - last > idle_seconds:
                try:
                    await ws.close()
                except Exception:
                    pass
                musetalk_audio_streams.pop(room, None)
                musetalk_last_pcm_ts.pop(room, None)
                break
            # If ws already closed externally, clean up
            if getattr(ws, "closed", False):
                musetalk_audio_streams.pop(room, None)
                musetalk_last_pcm_ts.pop(room, None)
                break
    except Exception:
        # Best-effort cleanup
        musetalk_audio_streams.pop(room, None)
        musetalk_last_pcm_ts.pop(room, None)

@app.post("/publisher/start")
async def publisher_start(req: Request):
    """Start MuseTalk Real-Time Lipsync"""
    body = await req.json()
    room = body.get("room")
    if not room:
        raise HTTPException(400, "room required")
    idle_video_url = body.get("idle_video_url")  # URL to idle.mp4
    frames_zip_url = body.get("frames_zip_url")  # optional: URL to frames.zip
    
    if not idle_video_url:
        raise HTTPException(status_code=400, detail="idle_video_url required")
    
    # Idempotenz: Room bereits gestartet → keine Doppelstarts
    if room in active_publisher_rooms:
        return {"status": "already_running", "room": room}

    active_publisher_rooms.add(room)
    try:
        import httpx
        
        # Bevorzugt: URL-Weitergabe an MuseTalk (vermeidet riesige Base64-Bodies)
        video_b64 = None
        frames_zip_b64 = None
        
        # Warmup/Healthcheck (Modal kalter Start)
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                await client.get(f"{MUSETALK_URL}/health")
        except Exception:
            pass

        # Start MuseTalk session (mit Retry/Warmup)
        print(f"🚀 Starting MuseTalk session for room: {room}")
        started = False
        last_exc = None
        for attempt in range(3):
            try:
                async with httpx.AsyncClient(timeout=180.0) as client:
                    # 1) URL-Modus zuerst versuchen (leichtgewichtig)
                    payload_url = {"room": room, "connect_livekit": True}
                    if frames_zip_url:
                        payload_url["frames_zip_url"] = frames_zip_url
                    else:
                        payload_url["idle_video_url"] = idle_video_url
                    # LiveKit Infos an MuseTalk weitergeben
                    lk_url = LIVEKIT_URL
                    lk_key = LIVEKIT_API_KEY
                    lk_secret = LIVEKIT_API_SECRET
                    token_url = os.getenv("LIVEKIT_TOKEN_URL", "").strip()
                    if token_url:
                        payload_url["livekit_token_url"] = token_url
                    elif lk_url and lk_key and lk_secret:
                        payload_url.update({
                            "livekit_url": lk_url,
                            "livekit_api_key": lk_key,
                            "livekit_api_secret": lk_secret,
                        })

                    resp = await client.post(f"{MUSETALK_URL}/session/start", json=payload_url)
                    if resp.status_code == 200:
                        print(f"✅ MuseTalk session started")
                        started = True
                        break
                    else:
                        # 2) Fallback: Einmalig Base64 versuchen (kompatibel zu älteren Backends)
                        error_detail = resp.text
                        print(f"⚠️ MuseTalk URL start failed (try {attempt+1}/3): {resp.status_code} - {error_detail}")
                        if frames_zip_b64 is None and frames_zip_url:
                            # nur bei Bedarf herunterladen (Lazy)
                            try:
                                print(f"📥 Downloading frames.zip (fallback b64): {frames_zip_url[:100]}...")
                                z = await client.get(frames_zip_url, timeout=60.0)
                                z.raise_for_status()
                                frames_zip_b64 = base64.b64encode(z.content).decode()
                                print(f"✅ frames.zip downloaded: {len(z.content)} bytes")
                            except Exception as de:
                                print(f"⚠️ frames.zip download failed: {de}")
                        if video_b64 is None and not frames_zip_url:
                            try:
                                print(f"📥 Downloading idle video (fallback b64): {idle_video_url[:100]}...")
                                v = await client.get(idle_video_url, timeout=60.0)
                                v.raise_for_status()
                                video_b64 = base64.b64encode(v.content).decode()
                                print(f"✅ Video downloaded: {len(v.content)} bytes")
                            except Exception as de:
                                print(f"⚠️ idle video download failed: {de}")

                        payload_b64 = {"room": room, "connect_livekit": True}
                        if token_url:
                            payload_b64["livekit_token_url"] = token_url
                        elif lk_url and lk_key and lk_secret:
                            payload_b64.update({
                                "livekit_url": lk_url,
                                "livekit_api_key": lk_key,
                                "livekit_api_secret": lk_secret,
                            })
                        if frames_zip_b64:
                            payload_b64["frames_zip_b64"] = frames_zip_b64
                        elif video_b64:
                            payload_b64["video_b64"] = video_b64
                        else:
                            last_exc = HTTPException(status_code=500, detail="No media available for MuseTalk start")
                            continue

                        resp2 = await client.post(f"{MUSETALK_URL}/session/start", json=payload_b64)
                        if resp2.status_code == 200:
                            print(f"✅ MuseTalk session started (b64 fallback)")
                            started = True
                            break
                        else:
                            error_detail = resp2.text
                            print(f"⚠️ MuseTalk b64 start failed (try {attempt+1}/3): {resp2.status_code} - {error_detail}")
                            last_exc = HTTPException(status_code=500, detail=f"MuseTalk failed: {error_detail}")
            except Exception as e:
                last_exc = e
                print(f"⚠️ MuseTalk start error (try {attempt+1}/3): {e}")
            # kleiner Backoff
            await asyncio.sleep(0.6)
        if not started:
            raise HTTPException(status_code=500, detail=str(last_exc))
        
        # Open WebSocket for audio streaming
        print(f"🔌 Opening audio WebSocket...")
        import websockets
        ws_url = f"{MUSETALK_URL.replace('https://', 'wss://')}/audio"
        # Close previous if any for the same room (avoid duplicates)
        try:
            old = musetalk_audio_streams.get(room)
            if old:
                await old.close()
        except Exception:
            pass
        ws = await websockets.connect(ws_url)
        await ws.send(room.encode())  # Send room name first
        musetalk_audio_streams[room] = ws
        musetalk_last_pcm_ts[room] = time.time()
        # Start idle watcher (auto close when no PCM)
        asyncio.create_task(_mt_idle_watcher(room, ws))
        print(f"✅ Audio stream connected")
        
        # LiveKit-Audio vorbereiten (optional)
        global current_audio_room
        current_audio_room = room
        try:
            await lk_audio_pub.ensure_connected(room)
        except Exception:
            pass

        return {"status": "started", "room": room}
        
    except Exception as e:
        import traceback
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print(f"❌ Publisher start error: {error_msg}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Falls kein aktiver WS eingetragen wurde, Cleanup aus Idempotenz-Set
        if room not in musetalk_audio_streams:
            active_publisher_rooms.discard(room)


@app.post("/publisher/stop")
async def publisher_stop(req: Request):
    """Stop MuseTalk Real-Time Lipsync"""
    body = await req.json()
    room = body.get("room")
    if not room:
        raise HTTPException(400, "room required")
    
    try:
        import httpx
        
        await _stop_room_internal(room)
        active_publisher_rooms.discard(room)
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
                        # Robust: akzeptiere Float32 und wandle zu int16 LE
                        audio_bytes = _ensure_int16_le(audio_bytes)
                        
                        # Kein globaler MuseTalk-Forwarder mehr – nur pro-Room WS wird genutzt
                        
                        # Optional: in LiveKit als Audio-Track publizieren (48k mono)
                        # Auto-connect beim ersten PCM, falls noch nicht verbunden
                        room_for_audio = current_audio_room or last_client_room
                        if ORCH_PUBLISH_AUDIO and room_for_audio:
                            try:
                                if not lk_audio_pub._connected_room:
                                    current_audio_room = room_for_audio
                                    await lk_audio_pub.ensure_connected(room_for_audio)
                                up = _upsample_16k_to_48k_int16le(audio_bytes)
                                # 20ms @ 48kHz mono int16 => 960 samples => 1920 bytes
                                _audio48k_buf.extend(up)
                                frame_bytes = 960 * 2
                                while len(_audio48k_buf) >= frame_bytes:
                                    chunk = _audio48k_buf[:frame_bytes]
                                    del _audio48k_buf[:frame_bytes]
                                    lk_audio_pub.publish_pcm16_48k_mono(bytes(chunk))
                            except Exception:
                                pass
                        
                        # Send to all active MuseTalk streams
                        for room, musetalk_ws in list(musetalk_audio_streams.items()):
                            try:
                                await musetalk_ws.send(audio_bytes)
                                musetalk_last_pcm_ts[room] = time.time()
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
        
        # ElevenLabs WS schließen (wichtig für Container scale-down!)
        if ew_mp3:
            try:
                await ew_mp3.close()
            except Exception:
                pass
        if ew_pcm:
            try:
                await ew_pcm.close()
            except Exception:
                pass
        
        # MuseTalk WS schließen nach Stream-Ende
        global _musetalk_ws, _musetalk_room_sent
        if _musetalk_ws:
            try:
                await _musetalk_ws.close()
                _musetalk_ws = None
                _musetalk_room_sent = False
            except Exception:
                pass


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


@app.get("/debug/musetalk")
async def debug_musetalk():
    """Proxy: Liefert Debug-Infos vom MuseTalk-Dienst (Assets/Weights/Health)."""
    try:
        import httpx
        async with httpx.AsyncClient(timeout=8.0) as client:
            # 1) bevorzugt: /debug/assets
            r = await client.get(f"{MUSETALK_URL}/debug/assets")
            if r.status_code == 200:
                return r.json()
            # 2) fallback: /debug/weights
            r2 = await client.get(f"{MUSETALK_URL}/debug/weights")
            if r2.status_code == 200:
                return r2.json()
            # 3) health als Minimalinfo
            r3 = await client.get(f"{MUSETALK_URL}/health")
            return {"status": r3.status_code, "body": r3.text}
    except Exception as e:
        return {"error": str(e)}


@app.get("/debug/audio")
async def debug_audio():
    try:
        return {
            "orch_publish_audio": ORCH_PUBLISH_AUDIO,
            "rtc_available": rtc is not None,
            "current_audio_room": current_audio_room,
            "last_client_room": last_client_room,
            "connected_room": getattr(lk_audio_pub, "_connected_room", None),
            "has_source": bool(getattr(lk_audio_pub, "_source", None)),
            "buf_bytes": len(_audio48k_buf),
        }
    except Exception as e:
        return {"error": str(e)}
