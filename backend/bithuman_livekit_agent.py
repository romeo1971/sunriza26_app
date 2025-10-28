#!/usr/bin/env python3
"""
bitHuman LiveKit Agent - Cloud API Integration

Startet Bithuman Avatar in LiveKit Room und publisht Video automatisch.

Setup:
  pip install livekit livekit-agents
  uv pip install git+https://github.com/livekit/agents@main#subdirectory=livekit-plugins/livekit-plugins-bithuman

Usage:
  export BITHUMAN_API_SECRET="your_secret"
  export LIVEKIT_URL="wss://your-livekit-server.com"
  export LIVEKIT_API_KEY="your_key"
  export LIVEKIT_API_SECRET="your_secret"
  
  python bithuman_livekit_agent.py --agent-id A91XMB7113 --room my-room
"""

import os
import asyncio
import logging
from pathlib import Path
from dotenv import load_dotenv
from livekit import agents, rtc, api
import bithuman
import argparse

# Load .env file
env_path = Path(__file__).parent / '.env'
if env_path.exists():
    load_dotenv(env_path)
    logging.info(f"✅ .env geladen: {env_path}")
else:
    logging.warning(f"⚠️ Keine .env gefunden: {env_path}")

# Logging Setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def entrypoint(ctx: agents.JobContext):
    """
    LiveKit Agents Entrypoint - wird pro Room-Join aufgerufen
    """
    logger.info(f"🚀 Bithuman Agent startet für Room: {ctx.room.name}")
    
    # Bithuman Avatar initialisieren
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    api_secret = os.getenv("BITHUMAN_API_SECRET")
    model = os.getenv("BITHUMAN_MODEL", "expression")
    
    if not agent_id or not api_secret:
        logger.error("❌ BITHUMAN_AGENT_ID oder BITHUMAN_API_SECRET fehlt!")
        return
    
    logger.info(f"🤖 Initialisiere Avatar: {agent_id} (Model: {model})")
    
    # Bithuman Cloud API Session
    avatar = bithuman.AvatarSession(
        avatar_id=agent_id,
        api_secret=api_secret,
        model=model
    )
    
    logger.info("✅ Avatar Session erstellt")
    
    # Warte auf Participant (Flutter App)
    await ctx.wait_for_participant()
    logger.info(f"✅ Participant verbunden im Room")
    
    # Video Track publishen
    source = rtc.VideoSource(512, 512)
    track = rtc.LocalVideoTrack.create_video_track("bithuman-video", source)
    options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_CAMERA)
    
    await ctx.room.local_participant.publish_track(track, options)
    logger.info("🎬 Video Track gepublisht")
    
    # TODO: Generate frames from bithuman avatar
    # For now: black frame placeholder
    import numpy as np
    frame_data = np.zeros((512, 512, 4), dtype=np.uint8)
    frame_data[:, :, 3] = 255  # Alpha
    
    video_frame = rtc.VideoFrame(
        width=512,
        height=512,
        type=rtc.VideoBufferType.RGBA,
        data=frame_data.tobytes()
    )
    source.capture_frame(video_frame)
    logger.info("📹 Initial frame sent")
    
    # Warte auf Room-Ende
    await ctx.room.wait_for_disconnect()
    logger.info("👋 Room disconnected")


async def main():
    """
    CLI Entrypoint - startet Agent für spezifischen Room
    """
    parser = argparse.ArgumentParser(description="bitHuman LiveKit Agent")
    parser.add_argument("--agent-id", required=True, help="bitHuman Agent ID (z.B. A91XMB7113)")
    parser.add_argument("--room", required=True, help="LiveKit Room Name")
    parser.add_argument("--model", default="expression", choices=["essence", "expression"], help="Avatar Model")
    
    args = parser.parse_args()
    
    # Set ENV für entrypoint
    os.environ["BITHUMAN_AGENT_ID"] = args.agent_id
    os.environ["BITHUMAN_MODEL"] = args.model
    
    # API Secret prüfen
    if not os.getenv("BITHUMAN_API_SECRET"):
        logger.error("❌ BITHUMAN_API_SECRET fehlt!")
        return
    
    # LiveKit Worker starten
    worker = agents.Worker(
        room=args.room,
        entrypoint_fnc=entrypoint,
    )
    
    logger.info(f"🚀 Agent Worker startet für Room: {args.room}")
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())

