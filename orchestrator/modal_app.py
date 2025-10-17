import os
import modal

# Image: Python ASGI + optional Node sources copied (nicht benötigt zur Laufzeit)
image = (
    modal.Image.debian_slim()
    .apt_install("bash")
    .pip_install("fastapi", "uvicorn", "websockets")
    .add_local_dir(".", "/app/orchestrator", copy=True)
)

app = modal.App("lipsync-orchestrator", image=image)


@app.function(
    secrets=[modal.Secret.from_name("lipsync-eleven")],
    min_containers=1,
    scaledown_window=300,
    timeout=3600,
)
@modal.asgi_app()
def asgi():
    """ASGI-WebSocket-Orchestrator (CPU) für ElevenLabs."""
    import sys
    sys.path.insert(0, "/app/orchestrator")
    from py_asgi_app import app as fastapi_app
    return fastapi_app
