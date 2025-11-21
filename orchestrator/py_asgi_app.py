from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
room_to_agent: dict[str, str] = {}

# MuseTalk entfernt – keine globalen Forwarder mehr
ORCH_FORWARD_TO_MUSETALK = False
MUSETALK_WS_URL = ""
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
            # WICHTIG: AudioSource als MICROPHONE (nicht als screenshare/file) damit BitHuman es als User-Voice erkennt!
            self._source = rtc.AudioSource(rtc.AudioSourceOptions(echo_cancellation=False, noise_suppression=False))
            # Track als "microphone" publishen (Source.MICROPHONE)
            self._track = rtc.LocalAudioTrack.create_audio_track("user-voice", self._source)
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
                pcm_needed = bool(data.get("pcm", False))
                # Room speichern für Audio-Publishing
                global last_client_room
                room_from_client = data.get("room")
                if room_from_client and isinstance(room_from_client, str) and room_from_client.strip():
                    last_client_room = room_from_client.strip()
                # Einmalige TTS-Session ausführen und danach Verbindung schließen,
                # damit der Container skalieren kann.
                await stream_eleven(ws, voice_id, text, mp3_needed=mp3_needed, pcm_needed=pcm_needed)
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


# MuseTalk entfernt – Publisher Integration deaktiviert
MUSETALK_URL = ""
musetalk_audio_streams: dict[str, Any] = {}
musetalk_last_pcm_ts: dict[str, float] = {}
active_publisher_rooms: set[str] = set()

async def _stop_room_internal(room: str):
    """Stoppe alle Streams/Verbindungen für einen Room (automatischer Cleanup)."""
    global current_audio_room, _musetalk_ws, _musetalk_room_sent
    # MuseTalk entfernt – nur internen Zustand räumen
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
    # MuseTalk Session Stop entfällt
    # 3) LiveKit Audio Publisher trennen
    try:
        await lk_audio_pub.disconnect()
    except Exception:
        pass
    # Globale MuseTalk WS entfällt
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
    """Start LiveKit publisher und optional BitHuman-Agent (falls konfiguriert)."""
    body = await req.json()
    room = body.get("room")
    if not room:
        raise HTTPException(400, "room required")
    idle_video_url = body.get("idle_video_url")  # legacy, ignoriert
    frames_zip_url = body.get("frames_zip_url")  # legacy, ignoriert
    agent_id = (body.get("agent_id") or "").strip()
    
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
        
        # MuseTalk entfernt – hier nur LiveKit Audio vorbereiten
        print(f"🚀 Starting LiveKit publisher for room: {room}")
        
        # LiveKit-Audio vorbereiten (optional)
        global current_audio_room
        current_audio_room = room
        try:
            await lk_audio_pub.ensure_connected(room)
        except Exception:
            pass

        # Optional: BitHuman-Agent via externem Service starten
        try:
            bh_url = os.getenv("BITHUMAN_AGENT_START_URL", "").strip()
            if bh_url and agent_id:
                import httpx
                payload = {"room": room, "agent_id": agent_id}
                # Fire-and-forget (kein Await, kurzer Timeout)
                async def _fire():
                    try:
                        async with httpx.AsyncClient(timeout=5.0) as client:
                            await client.post(bh_url, json=payload)
                    except Exception:
                        pass
                asyncio.create_task(_fire())
        except Exception:
            pass

        # WICHTIG: HTTP Call SOFORT zurückgeben (verhindert hängende Container!)
        # Idle Watcher startet NACH dem Return (im Event Loop, nicht im Request-Context)
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
        # Agent-ID merken (für spätere speak-Calls)
        try:
            if agent_id:
                room_to_agent[room] = agent_id
        except Exception:
            pass


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
    finally:
        try:
            room_to_agent.pop(room, None)
        except Exception:
            pass

async def stream_eleven(ws: WebSocket, voice_id: str, text: str, mp3_needed: bool = True, pcm_needed: bool = False):
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

    # PCM‑Verbindung nur bei Bedarf öffnen (Kosten sparen)
    if mp3_needed or pcm_needed:
        ew_pcm = None
        try:
            if pcm_needed:
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
        if pcm_needed and ew_pcm:
            await ew_pcm.send(json.dumps({"text": text}))
        # EOS
        if ew_mp3:
            await ew_mp3.send(json.dumps({"text": ""}))
        if pcm_needed and ew_pcm:
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
                        # Optional: in LiveKit als Audio-Track publizieren (48k mono)
                        # Auto-connect beim ersten PCM, falls noch nicht verbunden
                        room_for_audio = current_audio_room or last_client_room
                        if ORCH_PUBLISH_AUDIO and room_for_audio:
                            try:
                                if not lk_audio_pub._connected_room:
                                    current_audio_room = room_for_audio
                                    await lk_audio_pub.ensure_connected(room_for_audio)
                                audio_b64 = msg["audio"]
                                audio_bytes = base64.b64decode(audio_b64)
                                audio_bytes = _ensure_int16_le(audio_bytes)
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
                        
                    if msg.get("isFinal"):
                        break
                except Exception:
                    continue

        # Starte Loops parallel (PCM nur wenn benötigt)
        await asyncio.gather(loop_mp3(), loop_pcm())
        
        # ElevenLabs WS schließen (wichtig für Container scale-down!)
        if ew_mp3:
            try:
                await ew_mp3.close()
            except Exception:
                pass
        if pcm_needed and ew_pcm:
            try:
                await ew_pcm.close()
            except Exception:
                pass
        
        # MuseTalk entfernt – keine WS zu schließen


@app.post("/avatar/tts")
async def avatar_tts(req: Request):
    """TTS Endpoint für Flutter (POST) - gibt MP3 als base64 zurück"""
    if not ELEVEN_KEY:
        raise HTTPException(status_code=500, detail="ELEVENLABS_API_KEY missing")
    
    try:
        body = await req.json()
        text = body.get("text", "").strip()
        voice_id = body.get("voice_id", "").strip()
        stability = body.get("stability", 0.5)
        similarity = body.get("similarity_boost", 0.8)
        
        if not text:
            raise HTTPException(status_code=400, detail="text required")
        if not voice_id:
            raise HTTPException(status_code=400, detail="voice_id required")
        
        import httpx
        url = f"https://{ELEVEN_BASE}/v1/text-to-speech/{voice_id}"
        headers = {"xi-api-key": ELEVEN_KEY, "Content-Type": "application/json"}
        payload = {
            "text": text,
            "model_id": ELEVEN_MODEL,
            "voice_settings": {
                "stability": stability,
                "similarity_boost": similarity
            }
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            audio_bytes = resp.content
            audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
            return {"audio_b64": audio_b64}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


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
@app.post("/agent/join")
async def agent_join(req: Request):
    """Proxy: BitHuman Agent in Room joinen lassen"""
    try:
        body = await req.json()
        room = (body.get("room") or "").strip()
        agent_id = (body.get("agent_id") or "").strip()
        if not (room and agent_id):
            return {"status": "error", "message": "room und agent_id erforderlich"}

        bh_join_url = os.getenv("BITHUMAN_AGENT_JOIN_URL", "").strip()
        if not bh_join_url:
            return {"status": "ignored", "reason": "BITHUMAN_AGENT_JOIN_URL not set"}

        import httpx
        payload = {"room": room, "agent_id": agent_id}
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(bh_join_url, json=payload)
            return resp.json()
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.post("/speak")
async def speak(req: Request):
    """Triggert optional einen BitHuman-Agenten für Lipsync im Raum."""
    try:
        body = await req.json()
        text = (body.get("text") or "").strip()
        room = (body.get("room") or last_client_room or current_audio_room or "").strip()
        agent_id = (body.get("agent_id") or room_to_agent.get(room) or "").strip()
        if not (text and room and agent_id):
            return {"status": "ignored", "reason": "missing text/room/agent_id"}

        bh_url = os.getenv("BITHUMAN_AGENT_SPEAK_URL", "").strip()
        if not bh_url:
            return {"status": "ignored", "reason": "BITHUMAN_AGENT_SPEAK_URL not set"}

        import httpx
        payload = {"text": text, "room": room, "agent_id": agent_id}
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.post(bh_url, json=payload)
        return {"status": "ok"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


# MuseTalk Debug-Endpoint entfernt


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


# ==================== ELEVENLABS PROXY (Flutter SSL-Workaround) ====================
@app.get("/api/elevenlabs/voices")
async def elevenlabs_voices_proxy():
    """Proxy für ElevenLabs Voices API - umgeht Flutter SSL-Problem"""
    if not ELEVEN_KEY:
        raise HTTPException(status_code=500, detail="ELEVENLABS_API_KEY not configured")
    
    try:
        import httpx
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                f"https://{ELEVEN_BASE}/v1/voices",
                headers={"xi-api-key": ELEVEN_KEY}
            )
            resp.raise_for_status()
            return resp.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"ElevenLabs API error: {str(e)}")


@app.post("/api/elevenlabs/clone")
async def elevenlabs_clone_proxy(req: Request):
    """Proxy für ElevenLabs Voice Clone API - umgeht Flutter SSL-Problem"""
    if not ELEVEN_KEY:
        raise HTTPException(status_code=500, detail="ELEVENLABS_API_KEY not configured")
    
    try:
        body = await req.json()
        import httpx
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"https://{ELEVEN_BASE}/v1/voices/add",
                headers={
                    "xi-api-key": ELEVEN_KEY,
                    "Content-Type": "application/json"
                },
                json=body
            )
            resp.raise_for_status()
            return resp.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"ElevenLabs API error: {str(e)}")


@app.post("/avatar/voice/create")
async def create_eleven_voice(req: Request):
    """Voice Cloning Endpoint - lädt Audio von URLs und erstellt ElevenLabs Stimme"""
    if not ELEVEN_KEY:
        raise HTTPException(status_code=400, detail="ELEVENLABS_API_KEY fehlt")
    
    try:
        body = await req.json()
        user_id = body.get("user_id")
        avatar_id = body.get("avatar_id")
        audio_urls = body.get("audio_urls", [])
        name = body.get("name")
        voice_id = body.get("voice_id")
        dialect = body.get("dialect")
        tempo = body.get("tempo")
        stability = body.get("stability")
        similarity = body.get("similarity")
        
        if not (user_id and avatar_id and audio_urls):
            raise HTTPException(status_code=400, detail="user_id, avatar_id und audio_urls erforderlich")
        
        import httpx
        async with httpx.AsyncClient(timeout=120.0) as client:
            # Lade Audios herunter (max 3)
            files = []
            for i, url in enumerate(audio_urls[:3]):
                resp = await client.get(url, timeout=60.0)
                resp.raise_for_status()
                ctype = resp.headers.get('content-type', 'application/octet-stream')
                ext = '.wav' if 'wav' in ctype else ('.m4a' if ('mp4' in ctype or 'm4a' in ctype) else '.mp3')
                files.append(("files", (f"sample_{i}{ext}", resp.content, ctype)))
            
            voice_name = name or f"avatar_{avatar_id}"
            canonical_name = f"avatar_{avatar_id}"
            headers_eleven = {"xi-api-key": ELEVEN_KEY}
            
            # Alte Stimme löschen falls vorhanden
            if voice_id and voice_id.strip() and voice_id != "__CLONE__":
                try:
                    del_resp = await client.delete(
                        f"https://{ELEVEN_BASE}/v1/voices/{voice_id.strip()}",
                        headers=headers_eleven,
                        timeout=30.0
                    )
                    if 200 <= del_resp.status_code < 300:
                        print(f"✅ Alte Stimme gelöscht: {voice_id}")
                except Exception:
                    pass
            
            # Labels für Metadaten
            labels = {}
            if dialect:
                labels["dialect"] = str(dialect)
            if tempo is not None:
                labels["tempo"] = f"{float(tempo):.2f}"
            if stability is not None:
                labels["stability"] = f"{float(stability):.2f}"
            if similarity is not None:
                labels["similarity"] = f"{float(similarity):.2f}"
            
            # Neue Stimme erstellen
            data = {"name": canonical_name}
            if labels:
                import json as json_lib
                data["labels"] = json_lib.dumps(labels)
            
            # Multipart Request
            create_resp = await client.post(
                f"https://{ELEVEN_BASE}/v1/voices/add",
                headers={**headers_eleven, "Accept": "application/json"},
                data=data,
                files=files,
                timeout=120.0
            )
            create_resp.raise_for_status()
            res_data = create_resp.json()
            new_voice_id = res_data.get("voice_id") or res_data.get("id")
            result_name = res_data.get("name") or canonical_name
            
            if not new_voice_id:
                raise HTTPException(status_code=500, detail="ElevenLabs: voice_id fehlt in Antwort")
            
            return {"voice_id": new_voice_id, "name": result_name}
            
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=f"ElevenLabs: {e.response.text}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice Create Fehler: {str(e)}")
