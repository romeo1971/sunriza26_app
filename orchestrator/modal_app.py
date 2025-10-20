import os
import modal

# Image: Python ASGI + optional Node sources copied (nicht benötigt zur Laufzeit)
image = (
    modal.Image.debian_slim()
    .apt_install("bash")
    .pip_install(
        "fastapi",
        "uvicorn",
        "websockets",
        "PyJWT",
        "httpx",
        "livekit",
    )
    .add_local_file("orchestrator/py_asgi_app.py", "/app/py_asgi_app.py")
)

app = modal.App("lipsync-orchestrator", image=image)


@app.function(
    secrets=[
        modal.Secret.from_name("lipsync-eleven"),
        modal.Secret.from_name("liveportrait-ws"),
        modal.Secret.from_name("livekit-cloud"),
    ],
    min_containers=0,            # scale-to-zero
    scaledown_window=15,         # schnellere Skalierung nach Inaktivität
    timeout=1800,                # Sitzung max. 30 Min.
)
@modal.asgi_app()
def asgi():
    """ASGI-WebSocket-Orchestrator (CPU) für ElevenLabs."""
    import sys
    sys.path.insert(0, "/app")
    from py_asgi_app import app as fastapi_app
    return fastapi_app
