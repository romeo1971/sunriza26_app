#!/usr/bin/env python3
"""
Modal.com App - BitHuman Agent mit ElevenLabs Voice

Deploy:
  modal deploy modal_bithuman_elevenlabs.py

URL:
  https://your-workspace--bithuman-elevenlabs-agent-join.modal.run

Endpoint:
  POST /join
  Body: {"room": "room-abc123", "agent_id": "A91XMB7113"}
"""

import modal
import os

# Image mit allen Dependencies
image = (
    modal.Image.debian_slim()
    .pip_install(
        "livekit-agents[openai,bithuman,silero]>=1.2.16",
        "python-dotenv>=1.1.1",
        "firebase-admin>=6.4.0",
    )
    .apt_install("git")
    # Versuche ElevenLabs Plugin zu installieren (falls verfügbar)
    .run_commands(
        "pip install livekit-plugins-elevenlabs || echo 'ElevenLabs plugin not available'",
        gpu=None,
    )
)

app = modal.App("bithuman-elevenlabs-agent", image=image)

# Secrets aus Modal
secrets = [
    modal.Secret.from_name("livekit-cloud"),      # LIVEKIT_URL, API_KEY, API_SECRET
    modal.Secret.from_name("bithuman-api"),       # BITHUMAN_API_SECRET
    modal.Secret.from_name("openai-api"),         # OPENAI_API_KEY
    modal.Secret.from_name("elevenlabs-api"),     # ELEVENLABS_API_KEY
    modal.Secret.from_name("firebase-admin"),     # FIREBASE_CREDENTIALS (JSON)
]


@app.function(
    secrets=secrets,
    timeout=3600,  # 60 Min max
    cpu=2.0,
    memory=4096,
    keep_warm=1,  # Ein Container warm halten für schnellere Starts
)
def start_agent(room: str, agent_id: str, voice_id: str = None):
    """
    Startet BitHuman Agent für gegebenen Room.
    
    Args:
        room: LiveKit Room Name
        agent_id: BitHuman Agent ID
        voice_id: Optional ElevenLabs Voice ID (sonst aus Firebase)
    """
    import subprocess
    import sys
    
    # ENV setzen
    env = os.environ.copy()
    env["BITHUMAN_AGENT_ID"] = agent_id
    
    # Optional: Voice ID überschreiben
    if voice_id:
        env["ELEVEN_DEFAULT_VOICE_ID"] = voice_id
    
    print(f"🚀 Starting BitHuman Agent for room: {room}, agent: {agent_id}")
    
    # Agent als Subprocess starten (da er mit LiveKit CLI laufen muss)
    try:
        # Agent Code inline schreiben (damit Modal es findet)
        agent_code = """
import logging
import os
from pathlib import Path
from typing import Optional
from livekit.agents import Agent, AgentSession, JobContext, RoomOutputOptions, WorkerOptions, WorkerType, cli
from livekit.plugins import bithuman, openai, silero

# ElevenLabs falls vorhanden
try:
    from livekit.plugins import elevenlabs
    ELEVENLABS_AVAILABLE = True
except ImportError:
    ELEVENLABS_AVAILABLE = False

# Firebase
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agent")

def get_voice_id(agent_id: str) -> Optional[str]:
    if not FIREBASE_AVAILABLE:
        return os.getenv("ELEVEN_DEFAULT_VOICE_ID")
    try:
        if not firebase_admin._apps:
            # Firebase Credentials aus Modal Secret (JSON String)
            import json
            creds_json = os.getenv("FIREBASE_CREDENTIALS")
            if creds_json:
                creds_dict = json.loads(creds_json)
                cred = credentials.Certificate(creds_dict)
                firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        query = db.collection('avatars').where('liveAvatar.agentId', '==', agent_id).limit(1)
        for doc in query.stream():
            voice_data = doc.to_dict().get('training', {}).get('voice', {})
            vid = voice_data.get('cloneVoiceId') or voice_data.get('elevenVoiceId')
            if vid and vid != '__CLONE__':
                return vid.strip()
    except Exception as e:
        logger.error(f"Firebase error: {e}")
    return os.getenv("ELEVEN_DEFAULT_VOICE_ID")

async def entrypoint(ctx: JobContext):
    await ctx.connect()
    await ctx.wait_for_participant()
    
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    voice_id = get_voice_id(agent_id)
    
    logger.info(f"Agent: {agent_id}, Voice: {voice_id}")
    
    # BitHuman Avatar
    avatar = bithuman.AvatarSession(
        api_url=os.getenv("BITHUMAN_API_URL", "https://auth.api.bithuman.ai/v1/runtime-tokens/request"),
        api_secret=os.getenv("BITHUMAN_API_SECRET"),
        avatar_id=agent_id,
    )
    
    # TTS: ElevenLabs oder OpenAI Fallback
    if ELEVENLABS_AVAILABLE and voice_id:
        tts = elevenlabs.TTS(voice_id=voice_id, api_key=os.getenv("ELEVENLABS_API_KEY"))
    else:
        tts = openai.TTS(voice="coral")
    
    # Session
    session = AgentSession(
        llm=openai.realtime.RealtimeModel(model="gpt-4o-mini-realtime-preview"),
        vad=silero.VAD.load(),
        tts=tts,
    )
    
    await avatar.start(session, room=ctx.room)
    
    await session.start(
        agent=Agent(instructions="Du bist ein hilfreicher Assistent."),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False),
    )

if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, worker_type=WorkerType.ROOM))
"""
        
        # Agent Code in temp file schreiben
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(agent_code)
            agent_file = f.name
        
        # Agent starten
        result = subprocess.run(
            [sys.executable, agent_file, "start"],
            env=env,
            capture_output=True,
            text=True,
            timeout=3500,  # 58 Min (etwas unter Modal timeout)
        )
        
        print(f"✅ Agent finished: {result.returncode}")
        print(f"STDOUT:\n{result.stdout}")
        if result.stderr:
            print(f"STDERR:\n{result.stderr}")
        
        return {
            "status": "completed" if result.returncode == 0 else "failed",
            "exit_code": result.returncode,
        }
        
    except subprocess.TimeoutExpired:
        print("⏱️ Agent timeout (normal bei langen Sessions)")
        return {"status": "timeout"}
    except Exception as e:
        print(f"❌ Agent error: {e}")
        return {"status": "error", "message": str(e)}


@app.function(secrets=secrets)
@modal.web_endpoint(method="POST")
def join(data: dict):
    """
    Webhook Endpoint: Startet Agent wenn User "Gespräch starten" klickt.
    
    Request:
        POST /join
        Body: {"room": "room-abc123", "agent_id": "A91XMB7113", "voice_id": "xyz" (optional)}
    
    Response:
        {"status": "started", "room": "...", "agent_id": "..."}
    """
    room = data.get("room", "").strip()
    agent_id = data.get("agent_id", "").strip()
    voice_id = data.get("voice_id", "").strip() or None
    
    if not room or not agent_id:
        return {"status": "error", "message": "room and agent_id required"}
    
    print(f"🎬 Join request: room={room}, agent={agent_id}, voice={voice_id}")
    
    # Agent asynchron starten (damit Request nicht blockiert)
    start_agent.spawn(room, agent_id, voice_id)
    
    return {
        "status": "started",
        "room": room,
        "agent_id": agent_id,
        "voice_id": voice_id or "from_firebase",
    }


@app.function(secrets=secrets)
@modal.web_endpoint(method="GET")
def health():
    """Health Check"""
    return {
        "status": "ok",
        "service": "bithuman-elevenlabs-agent",
        "endpoint": "POST /join with {room, agent_id, voice_id?}",
    }

