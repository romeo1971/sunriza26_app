#!/usr/bin/env python3
"""
Modal BitHuman LiveKit Worker (Always-On GPU)
==============================================
GPU-enabled LiveKit Worker für BitHuman Avatar
Registriert sich bei LiveKit und wartet auf Room-Events

Deploy: modal deploy modal_bithuman_serve.py
"""

import modal
import logging

# GPU Image
image = (
    modal.Image.debian_slim()
    .apt_install("libgl1-mesa-glx", "libglib2.0-0", "libsm6", "libxext6", "libxrender1")
    .pip_install(
        "livekit-agents[openai,bithuman,silero]>=1.2.17",
        "python-dotenv>=1.1.1",
        "firebase-admin>=6.4.0",
        "livekit-plugins-elevenlabs",
    )
)

app = modal.App("bithuman-worker-serve", image=image)

secrets = [
    modal.Secret.from_name("livekit-cloud"),
    modal.Secret.from_name("bithuman-api"),
    modal.Secret.from_name("openai-api"),
    modal.Secret.from_name("elevenlabs-api"),
    modal.Secret.from_name("firebase-admin"),
]


# Worker Code
WORKER_CODE = '''
import logging
import os
import json
from typing import Dict, Any

from livekit.agents import (
    Agent,
    AgentSession,
    JobContext,
    RoomOutputOptions,
    WorkerOptions,
    WorkerType,
    cli,
)
from livekit.plugins import bithuman, openai, silero

try:
    from livekit.plugins import elevenlabs
    ELEVENLABS_AVAILABLE = True
except ImportError:
    ELEVENLABS_AVAILABLE = False

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bithuman-worker")


def get_config(agent_id: str) -> Dict[str, Any]:
    """Load config from Firebase"""
    if not FIREBASE_AVAILABLE:
        return {}
    try:
        if not firebase_admin._apps:
            creds = os.getenv("FIREBASE_CREDENTIALS")
            if creds:
                cred = credentials.Certificate(json.loads(creds))
                firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        query = db.collection("avatars").where("liveAvatar.agentId", "==", agent_id).limit(1)
        
        for doc in query.stream():
            data = doc.to_dict()
            voice = data.get("training", {}).get("voice", {})
            vid = voice.get("cloneVoiceId") or voice.get("elevenVoiceId")
            if vid == "__CLONE__":
                vid = None
            
            live_avatar = data.get("liveAvatar", {})
            bh_model = live_avatar.get("model", "essence")
            
            return {
                "voice_id": vid.strip() if vid else None,
                "instructions": data.get("personality"),
                "name": data.get("name", "Avatar"),
                "bithuman_model": bh_model,
            }
        return {}
    except Exception as e:
        logger.error(f"Firebase error: {e}")
        return {}


async def entrypoint(ctx: JobContext):
    """Main entrypoint"""
    await ctx.connect()
    logger.info(f"✅ Connected to room: {ctx.room.name}")
    
    # Wait for participant
    logger.info("⏳ Waiting for participant...")
    await ctx.wait_for_participant()
    logger.info("✅ Participant joined!")
    
    # Get Agent ID from room metadata
    agent_id = ctx.room.metadata or os.getenv("BITHUMAN_AGENT_ID")
    if not agent_id:
        logger.error("❌ No agent_id!")
        return
    
    logger.info(f"🤖 Agent ID: {agent_id}")
    
    # Load config
    config = get_config(agent_id)
    voice_id = config.get("voice_id") or os.getenv("ELEVEN_DEFAULT_VOICE_ID")
    bh_model = config.get("bithuman_model", "essence")
    
    logger.info(f"🎤 Voice: {voice_id}, Model: {bh_model}")
    
    # TTS
    if ELEVENLABS_AVAILABLE and voice_id:
        tts = elevenlabs.TTS(voice_id=voice_id, api_key=os.getenv("ELEVENLABS_API_KEY"))
    else:
        tts = openai.TTS(voice="coral")
    
    # LLM
    llm = openai.realtime.RealtimeModel(
        voice=os.getenv("OPENAI_VOICE", "coral"),
        model="gpt-4o-mini-realtime-preview"
    )
    
    # Session
    session = AgentSession(llm=llm, vad=silero.VAD.load(), tts=tts)
    
    # BitHuman Avatar
    logger.info(f"🎬 Creating BitHuman Avatar (model={bh_model})...")
    avatar = bithuman.AvatarSession(
        avatar_id=agent_id,
        api_secret=os.getenv("BITHUMAN_API_SECRET"),
        model=bh_model,
    )
    logger.info("✅ Avatar created")
    
    # Start Avatar
    logger.info("🚀 Starting Avatar...")
    await avatar.start(session, room=ctx.room)
    logger.info("🎥 Avatar STARTED!")
    
    # Start Agent
    instructions = config.get("instructions") or f"Du bist {config.get('name', 'Avatar')}"
    await session.start(
        agent=Agent(instructions=instructions),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False)
    )
    logger.info("✅ Agent running!")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            worker_type=WorkerType.ROOM,
            job_memory_warn_mb=4000,
            num_idle_processes=0,
            initialize_process_timeout=180,
        )
    )
'''


@app.function(
    secrets=secrets,
    gpu="T4",  # GPU für expression model  
    cpu=2.0,
    memory=8192,
    timeout=86400,  # 24h max runtime
    keep_warm=1,  # Always-on (1 container immer bereit)
)
def run_worker():
    """Runs the LiveKit Worker continuously"""
    import tempfile
    import subprocess
    import sys
    import os
    
    # Write worker code to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(WORKER_CODE)
        worker_file = f.name
    
    try:
        # Run worker (blocks until terminated)
        logging.info("🚀 Starting LiveKit Worker...")
        subprocess.run(
            [sys.executable, worker_file, "start"],
            env=os.environ.copy(),
            check=True,
        )
    finally:
        # Cleanup
        try:
            os.unlink(worker_file)
        except:
            pass

