#!/usr/bin/env python3
"""
Modal BitHuman Worker (Serve Mode)
===================================
GPU-enabled LiveKit Worker für BitHuman Avatar
Läuft dauerhaft und wartet auf LiveKit Room Events

Deploy: modal serve modal_bithuman_worker_serve.py
"""

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

