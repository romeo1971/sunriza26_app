from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import os
import json
import base64
import asyncio
import websockets

app = FastAPI()

ELEVEN_BASE = os.getenv("ELEVENLABS_BASE", "api.elevenlabs.io")
ELEVEN_MODEL = os.getenv("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
ELEVEN_KEY = os.getenv("ELEVENLABS_API_KEY")

@app.get("/health")
async def health():
    return {"ok": True}

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
                await ws.send_text(json.dumps({"type": "done"}))
    except WebSocketDisconnect:
        return

async def stream_eleven(ws: WebSocket, voice_id: str, text: str):
    if not ELEVEN_KEY:
        await ws.send_text(json.dumps({"type": "error", "message": "ELEVENLABS_API_KEY missing"}))
        return
    url = (
        f"wss://{ELEVEN_BASE}/v1/text-to-speech/{voice_id}/stream-input"
        f"?model_id={ELEVEN_MODEL}&output_format=mp3_44100_128"
    )
    headers = [("xi-api-key", ELEVEN_KEY)]  # websockets>=11 erwartet additional_headers
    async with websockets.connect(url, additional_headers=headers) as ew:
        # INIT
        await ew.send(json.dumps({"text": " ", "voice_settings": {"stability": 0.5, "similarity_boost": 0.8, "speed": 1}}))
        # TEXT
        await ew.send(json.dumps({"text": text}))
        # EOS
        await ew.send(json.dumps({"text": ""}))
        async for raw in ew:
            try:
                msg = json.loads(raw)
                if msg.get("audio"):
                    await ws.send_text(json.dumps({
                        "type": "audio",
                        "data": msg["audio"],
                        "format": "mp3_44100_128",
                    }))
                if msg.get("alignment"):
                    al = msg["alignment"]
                    chars = al.get("chars", [])
                    starts = al.get("charStartTimesMs", [])
                    durs = al.get("charDurationsMs", [])
                    for i, ch in enumerate(chars):
                        await ws.send_text(json.dumps({
                            "type": "viseme",
                            "value": ch,
                            "pts_ms": starts[i] if i < len(starts) else 0,
                            "duration_ms": durs[i] if i < len(durs) else 100,
                        }))
                if msg.get("isFinal"):
                    await ws.send_text(json.dumps({"type": "done"}))
                    break
            except Exception:
                continue
