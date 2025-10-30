#!/usr/bin/env python3
"""
Modal.com App - Bithuman LiveKit Agent

Deploy:
  modal deploy modal_bithuman_agent.py

URL:
  https://romeo1971--bithuman-agent-join.modal.run/join
"""

import modal
import os

# Image mit Bithuman
image = (
    modal.Image.debian_slim()
    .pip_install(
        "fastapi",
        "livekit>=0.10.0",
        "livekit-agents",
        "bithuman",
        "numpy",
    )
    .add_local_file(
        "backend/bithuman_livekit_agent.py",
        "/app/bithuman_livekit_agent.py"
    )
)

app = modal.App("bithuman-agent", image=image)

# Secrets
secrets = [
    modal.Secret.from_name("livekit-cloud"),  # LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
    modal.Secret.from_name("bithuman-api"),   # BITHUMAN_API_SECRET
]


@app.function(
    secrets=secrets,
    timeout=3600,  # 60 Min max
    min_containers=0,  # scale-to-zero
    scaledown_window=60,  # 60s idle → shutdown
)
@modal.web_endpoint(method="POST")
def join(data: dict):
    """
    POST (ohne /join am Ende!)
    Body: {"room": "...", "agent_id": "..."}
    
    Startet Bithuman Agent - Plugin joined LiveKit automatisch
    """
    import bithuman
    
    room = data.get("room", "").strip()
    agent_id = data.get("agent_id", "").strip()
    
    if not room or not agent_id:
        return {"status": "error", "message": "room und agent_id erforderlich"}
    
    api_secret = os.getenv("BITHUMAN_API_SECRET")
    if not api_secret:
        return {"status": "error", "message": "BITHUMAN_API_SECRET fehlt in Modal Secrets"}
    
    try:
        print(f"🤖 Creating Bithuman Avatar Session: {agent_id} for room: {room}")
        
        # Bithuman Cloud API - Plugin joined LiveKit automatisch!
        avatar = bithuman.AvatarSession(
            avatar_id=agent_id,
            api_secret=api_secret,
            model="expression"
        )
        
        print(f"✅ Bithuman Avatar Session created: {agent_id}")
        
        return {
            "status": "started",
            "room": room,
            "agent_id": agent_id,
            "message": "Bithuman Agent gestartet - Video wird automatisch in LiveKit Room gepublisht"
        }
    except Exception as e:
        print(f"❌ Bithuman Error: {e}")
        import traceback
        traceback.print_exc()
        return {
            "status": "error",
            "message": str(e)
        }


@app.function(secrets=secrets)
@modal.web_endpoint(method="GET")
def health():
    """GET /health"""
    return {
        "status": "ok",
        "service": "bithuman-agent",
        "message": "POST /join zum Starten"
    }

