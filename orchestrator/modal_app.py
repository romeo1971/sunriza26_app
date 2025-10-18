import os
import modal

# Image: Python ASGI + optional Node sources copied (nicht benötigt zur Laufzeit)
image = (
    modal.Image.debian_slim()
    .apt_install("bash")
    .pip_install("fastapi", "uvicorn", "websockets", "PyJWT")
    # Bundle den gesamten Orchestrator-Ordner (klein) → stellt sicher, dass py_asgi_app.py vorhanden ist
    .add_local_dir(".", "/app", copy=True)
)

app = modal.App("lipsync-orchestrator", image=image)


@app.function(
    secrets=[
        modal.Secret.from_name("lipsync-eleven"),
        # Erwartet Key: LIVEPORTRAIT_WS_URL
        modal.Secret.from_name("liveportrait-ws"),
        # Erwartet Keys: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
        modal.Secret.from_name("livekit-cloud"),
    ],
    min_containers=1,
    scaledown_window=300,
    timeout=3600,
)
@modal.asgi_app()
def asgi():
    """ASGI-WebSocket-Orchestrator (CPU) für ElevenLabs."""
    import sys
    sys.path.insert(0, "/app")
    from py_asgi_app import app as fastapi_app
    return fastapi_app
