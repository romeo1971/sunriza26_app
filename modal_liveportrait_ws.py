#!/usr/bin/env python3
"""
Modal.com ASGI-App für den LivePortrait WebSocket-Server.

Bereitstellt den Endpoint:
  - GET /health
  - WS  /stream

Backend-Implementierung liegt in backend/liveportrait_stream_server.py

Deployment (Beispiel):
  modal deploy modal_liveportrait_ws.py::web

Nach dem Deploy lautet die WS-URL typischerweise:
  wss://<workspace>--liveportrait-ws.modal.run/stream
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
    .run_commands(
        "echo 'REBUILD: 2025-10-31-19:30'",  # ← Change date/time to force rebuild
    )
    # Nur die eine Datei bundeln – vermeidet große Mounts (API-Limit)
    .add_local_file(
        "backend/liveportrait_stream_server.py",
        "/app/backend/liveportrait_stream_server.py",
    )
)

app = modal.App("liveportrait-ws", image=image)


@app.function(timeout=30, min_containers=0, scaledown_window=15)  # 30s idle → shutdown!
@modal.asgi_app()
def asgi():
    # Import zur Laufzeit (Code liegt unter /app)
    import sys
    sys.path.insert(0, "/app")
    from backend.liveportrait_stream_server import app as fastapi_app

    return fastapi_app


@app.function()
@modal.fastapi_endpoint(method="GET")
def check_secrets():
    """Debug: Check loaded secrets"""
    import os
    return {
        "app": "liveportrait-ws",
        "secrets": {
            "note": "This app uses NO secrets"
        }
    }


