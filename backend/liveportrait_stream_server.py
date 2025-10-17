#!/usr/bin/env python3
"""
LivePortrait WebSocket Streaming Server

Empfängt:
- Hero Image (einmalig)
- Audio Chunks (PCM 16kHz)

Sendet:
- Video Frames (JPEG) mit Timestamps
"""

import asyncio
import json
import base64
from pathlib import Path
import cv2
import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
import tempfile
import os

app = FastAPI()

# TODO: LivePortrait Integration
# from liveportrait import LivePortraitPipeline

@app.get("/health")
async def health():
    return {"status": "OK", "service": "liveportrait-stream"}

@app.websocket("/stream")
async def websocket_stream(websocket: WebSocket):
    """
    WebSocket Endpoint für LivePortrait Streaming
    
    Protocol:
    Client → Server:
    {
        "type": "init",
        "hero_image": "base64...",  # Hero-Image (einmalig)
        "voice_id": "..."           # Optional
    }
    {
        "type": "audio",
        "data": "base64...",        # PCM chunk
        "pts_ms": 123               # Timestamp
    }
    {
        "type": "stop"
    }
    
    Server → Client:
    {
        "type": "frame",
        "data": "base64...",        # JPEG frame
        "pts_ms": 123,              # Timestamp
        "format": "jpeg"
    }
    {
        "type": "done"
    }
    """
    await websocket.accept()
    print("🎭 LivePortrait client connected")
    
    hero_image = None
    frame_count = 0
    
    try:
        async for message in websocket.iter_text():
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "init":
                # Hero Image laden
                hero_b64 = data.get("hero_image")
                if hero_b64:
                    hero_bytes = base64.b64decode(hero_b64)
                    hero_array = np.frombuffer(hero_bytes, dtype=np.uint8)
                    hero_image = cv2.imdecode(hero_array, cv2.IMREAD_COLOR)
                    print(f"✅ Hero Image loaded: {hero_image.shape}")
                    
                    # TODO: LivePortrait Pipeline initialisieren
                    # self.lp_pipeline = LivePortraitPipeline(hero_image)
                    
                    await websocket.send_json({
                        "type": "ready",
                        "width": hero_image.shape[1],
                        "height": hero_image.shape[0]
                    })
            
            elif msg_type == "audio":
                # Audio Chunk → LivePortrait Frame generieren
                audio_b64 = data.get("data")
                pts_ms = data.get("pts_ms", 0)
                
                if audio_b64 and hero_image is not None:
                    # TODO: LivePortrait Frame generieren
                    # audio_bytes = base64.b64decode(audio_b64)
                    # frame = self.lp_pipeline.generate_frame(audio_bytes)
                    
                    # DUMMY: Hero-Image zurückschicken (für Testing)
                    _, jpeg_bytes = cv2.imencode('.jpg', hero_image, [cv2.IMWRITE_JPEG_QUALITY, 85])
                    frame_b64 = base64.b64encode(jpeg_bytes.tobytes()).decode()
                    
                    await websocket.send_json({
                        "type": "frame",
                        "data": frame_b64,
                        "pts_ms": pts_ms,
                        "format": "jpeg"
                    })
                    
                    frame_count += 1
                    if frame_count % 10 == 0:
                        print(f"📹 Frames sent: {frame_count}")
            
            elif msg_type == "stop":
                print(f"🛑 Stream stopped (sent {frame_count} frames)")
                await websocket.send_json({"type": "done"})
                break
    
    except WebSocketDisconnect:
        print(f"🔌 Client disconnected ({frame_count} frames sent)")
    except Exception as e:
        print(f"❌ Error: {e}")
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except:
            pass

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8002"))
    print(f"🚀 LivePortrait Stream Server starting on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)

