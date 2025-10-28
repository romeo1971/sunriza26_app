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
async def join(data: dict):
    """
    POST /join
    Body: {"room": "...", "agent_id": "..."}
    
    Startet Bithuman Agent für den Room
    """
    import asyncio
    import sys
    sys.path.insert(0, "/app")
    
    from livekit import agents
    from bithuman_livekit_agent import entrypoint
    
    room = data.get("room", "").strip()
    agent_id = data.get("agent_id", "").strip()
    
    if not room or not agent_id:
        return {"status": "error", "message": "room und agent_id erforderlich"}
    
    # Set ENV
    os.environ["BITHUMAN_AGENT_ID"] = agent_id
    os.environ["BITHUMAN_MODEL"] = "expression"
    
    # Check API Secret
    if not os.getenv("BITHUMAN_API_SECRET"):
        return {"status": "error", "message": "BITHUMAN_API_SECRET fehlt in Modal Secrets"}
    
    # Start Worker (non-blocking)
    async def _run_worker():
        try:
            worker = agents.Worker(
                room=room,
                entrypoint_fnc=entrypoint,
            )
            await worker.run()
        except Exception as e:
            print(f"❌ Worker Error: {e}")
    
    # Fire-and-forget
    asyncio.create_task(_run_worker())
    
    return {
        "status": "started",
        "room": room,
        "agent_id": agent_id,
        "message": "Bithuman Agent wird gestartet..."
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

