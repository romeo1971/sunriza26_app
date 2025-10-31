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
    .run_commands(
        "echo 'REBUILD: 2025-10-31-19:30'",  # ← Change date/time to force rebuild
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
    timeout=30,                  # 30s idle → shutdown
)
@modal.asgi_app()
def asgi():
    """ASGI-WebSocket-Orchestrator (CPU) für ElevenLabs."""
    import sys
    sys.path.insert(0, "/app")
    from py_asgi_app import app as fastapi_app
    return fastapi_app


@app.function(
    secrets=[
        modal.Secret.from_name("lipsync-eleven"),
        modal.Secret.from_name("liveportrait-ws"),
        modal.Secret.from_name("livekit-cloud"),
    ]
)
@modal.fastapi_endpoint(method="GET")
def check_secrets():
    """Debug: Check loaded secrets"""
    import os
    return {
        "app": "lipsync-orchestrator",
        "secrets": {
            "livekit_url": os.getenv("LIVEKIT_URL", "NOT SET")[:30] + "..." if os.getenv("LIVEKIT_URL") else "NOT SET",
            "livekit_api_key": os.getenv("LIVEKIT_API_KEY", "NOT SET")[:10] + "..." if os.getenv("LIVEKIT_API_KEY") else "NOT SET",
            "livekit_api_secret": "***" if os.getenv("LIVEKIT_API_SECRET") else "NOT SET",
            "elevenlabs_api_key": "***" if os.getenv("ELEVENLABS_API_KEY") else "NOT SET",
            "liveportrait_ws_url": os.getenv("LIVEPORTRAIT_WS_URL", "NOT SET")[:50] + "..." if os.getenv("LIVEPORTRAIT_WS_URL") else "NOT SET",
        }
    }

# Force rebuild: 2025-10-20 14:05 - Updated ELEVENLABS_API_KEY
