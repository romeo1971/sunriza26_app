#!/usr/bin/env python3
"""
Kleiner, eigenständiger Modal‑ASGI‑WS für LivePortrait.

Vorteil: Keine lokalen Verzeichnisse werden gemountet → kein Mount‑Limit.

Deploy:
  modal deploy modal_apps/liveportrait_ws/app.py
"""

import modal

image = (
    modal.Image.debian_slim()
    .pip_install(
        "fastapi",
        "uvicorn",
        "websockets>=11",
        "opencv-python-headless",
        "numpy",
    )
)

app = modal.App("liveportrait-ws", image=image)


@app.function(timeout=3600, min_containers=1, scaledown_window=300)
@modal.asgi_app()
def asgi():
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect
    import json
    import base64
    import numpy as np
    import cv2

    web = FastAPI()

    @web.get("/health")
    async def health():
        return {"status": "OK", "service": "liveportrait-ws"}

    @web.websocket("/stream")
    async def websocket_stream(ws: WebSocket):
        await ws.accept()
        hero_image = None
        try:
            while True:
                msg = await ws.receive_text()
                data = json.loads(msg)
                t = data.get("type")
                if t == "init":
                    b64 = data.get("hero_image")
                    if b64:
                        img_bytes = base64.b64decode(b64)
                        arr = np.frombuffer(img_bytes, dtype=np.uint8)
                        hero_image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                        await ws.send_json({
                            "type": "ready",
                            "width": hero_image.shape[1],
                            "height": hero_image.shape[0],
                        })
                elif t == "audio":
                    # DUMMY: solange keine echte LP‑Pipeline aktiv ist,
                    # senden wir das Hero‑Bild als JPEG‑Frame zurück.
                    if hero_image is not None:
                        ok, jpeg = cv2.imencode(".jpg", hero_image, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
                        if ok:
                            await ws.send_json({
                                "type": "frame",
                                "data": base64.b64encode(jpeg.tobytes()).decode(),
                                "pts_ms": int(data.get("pts_ms", 0)),
                                "format": "jpeg",
                            })
                elif t == "stop":
                    await ws.send_json({"type": "done"})
                    break
        except WebSocketDisconnect:
            pass

    return web


