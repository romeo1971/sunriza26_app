#!/usr/bin/env python3
"""
Lokaler BitHuman Agent (zum Testen)
====================================
Start: python bithuman_agent_local.py start

Braucht:
- LIVEKIT_URL
- LIVEKIT_API_KEY
- LIVEKIT_API_SECRET
- BITHUMAN_API_SECRET
"""

import logging
import os
from dotenv import load_dotenv
from livekit.agents import (
    Agent,
    AgentSession,
    JobContext,
    RoomOutputOptions,
    WorkerOptions,
    WorkerType,
    cli,
)
from livekit.plugins import bithuman, silero
from livekit.plugins import openai as lk_openai

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bithuman-local")

# DEBUG: Print ENV vars
logger.info(f"🔍 LIVEKIT_URL: {os.getenv('LIVEKIT_URL')}")
logger.info(f"🔍 LIVEKIT_API_KEY: {os.getenv('LIVEKIT_API_KEY')}")
logger.info(f"🔍 LIVEKIT_API_SECRET: {'SET' if os.getenv('LIVEKIT_API_SECRET') else 'MISSING'}")


async def entrypoint(ctx: JobContext):
    """Main entrypoint"""
    await ctx.connect()
    logger.info(f"✅ Connected to room: {ctx.room.name}")
    
    # Wait for participant
    logger.info("⏳ Waiting for participant...")
    await ctx.wait_for_participant()
    logger.info("✅ Participant joined!")
    
    # Get Agent ID from room metadata or env
    agent_id = ctx.room.metadata or os.getenv("BITHUMAN_AGENT_ID", "A96KSC8832")
    logger.info(f"🤖 Agent ID: {agent_id}")
    
    # TTS
    tts = lk_openai.TTS(voice="coral")
    
    # LLM
    llm = lk_openai.realtime.RealtimeModel(
        voice="coral",
        model="gpt-4o-mini-realtime-preview"
    )
    
    # Session
    session = AgentSession(llm=llm, vad=silero.VAD.load(), tts=tts)
    
    # BitHuman Avatar
    logger.info("🎬 Creating BitHuman Avatar...")
    avatar = bithuman.AvatarSession(
        api_url=os.getenv("BITHUMAN_API_URL", "https://auth.api.bithuman.ai/v1/runtime-tokens/request"),
        api_secret=os.getenv("BITHUMAN_API_SECRET"),
        avatar_id=agent_id,
    )
    logger.info("✅ Avatar created")
    
    # Start Avatar
    logger.info("🚀 Starting Avatar...")
    await avatar.start(session, room=ctx.room)
    logger.info("🎥 Avatar STARTED - Video Track published!")
    
    # Start Agent
    await session.start(
        agent=Agent(instructions="Du bist ein hilfreicher Assistent."),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False)
    )
    logger.info("✅ Agent running!")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            worker_type=WorkerType.ROOM,
        )
    )

