#!/usr/bin/env python3
"""
bitHuman LiveKit Agent

Dieser Agent verbindet einen bitHuman Avatar mit einem LiveKit Room.
Flutter App kann dann via LiveKit Client mit dem Avatar interagieren.

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
from typing import Optional
from pathlib import Path
from dotenv import load_dotenv
from livekit import rtc, api
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


class BitHumanLiveKitAgent:
    """LiveKit Agent mit bitHuman Avatar"""
    
    def __init__(
        self, 
        agent_id: str,
        api_secret: str,
        model: str = "essence",
        livekit_url: str = None,
        livekit_api_key: str = None,
        livekit_api_secret: str = None
    ):
        self.agent_id = agent_id
        self.api_secret = api_secret
        self.model = model
        
        # LiveKit Credentials
        self.livekit_url = livekit_url or os.getenv("LIVEKIT_URL")
        self.livekit_api_key = livekit_api_key or os.getenv("LIVEKIT_API_KEY")
        self.livekit_api_secret = livekit_api_secret or os.getenv("LIVEKIT_API_SECRET")
        
        if not all([self.livekit_url, self.livekit_api_key, self.livekit_api_secret]):
            raise ValueError("LiveKit credentials fehlen! Setze LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET")
        
        self.room: Optional[rtc.Room] = None
        self.avatar_session: Optional[bithuman.AvatarSession] = None
        
    async def initialize_avatar(self):
        """Initialisiert bitHuman Avatar Session"""
        logger.info(f"🤖 Initialisiere bitHuman Avatar: {self.agent_id}")
        
        self.avatar_session = bithuman.AvatarSession(
            avatar_id=self.agent_id,
            api_secret=self.api_secret,
            model=self.model
        )
        
        logger.info(f"✅ Avatar Session erstellt (Model: {self.model})")
    
    async def connect_to_room(self, room_name: str):
        """Verbindet Agent mit LiveKit Room"""
        logger.info(f"🔗 Verbinde mit Room: {room_name}")
        
        # Token generieren
        token = api.AccessToken(self.livekit_api_key, self.livekit_api_secret)
        token.with_identity(f"bithuman-agent-{self.agent_id}")
        token.with_name("BitHuman Avatar")
        token.with_grants(api.VideoGrants(
            room_join=True,
            room=room_name,
        ))
        
        room_token = token.to_jwt()
        
        # Room beitreten
        self.room = rtc.Room()
        
        @self.room.on("participant_connected")
        def on_participant_connected(participant: rtc.RemoteParticipant):
            logger.info(f"👤 Participant joined: {participant.identity}")
        
        @self.room.on("track_subscribed")
        def on_track_subscribed(
            track: rtc.Track,
            publication: rtc.RemoteTrackPublication,
            participant: rtc.RemoteParticipant,
        ):
            logger.info(f"🎤 Track subscribed: {track.kind} from {participant.identity}")
            
            if track.kind == rtc.TrackKind.KIND_AUDIO:
                asyncio.create_task(self.process_audio_track(track))
        
        await self.room.connect(self.livekit_url, room_token)
        logger.info(f"✅ Verbunden mit Room: {room_name}")
    
    async def process_audio_track(self, track: rtc.AudioTrack):
        """Verarbeitet Audio-Input und generiert Avatar-Response"""
        logger.info("🎧 Audio Track wird verarbeitet...")
        
        audio_stream = rtc.AudioStream(track)
        
        async for frame in audio_stream:
            # Audio an bitHuman Avatar senden
            if self.avatar_session:
                try:
                    # TODO: Audio Frame an Avatar senden
                    # response = self.avatar_session.process_audio(frame)
                    # Video Frame zurück an Room publishen
                    pass
                except Exception as e:
                    logger.error(f"❌ Audio Processing Error: {e}")
    
    async def publish_video_track(self):
        """Published Avatar Video Track in Room"""
        # TODO: Implement video publishing from avatar
        pass
    
    async def run(self, room_name: str):
        """Hauptloop: Avatar starten und in Room verbinden"""
        try:
            await self.initialize_avatar()
            await self.connect_to_room(room_name)
            
            logger.info("🚀 Agent läuft... (Ctrl+C zum Beenden)")
            
            # Warte auf Disconnect
            await asyncio.Event().wait()
            
        except KeyboardInterrupt:
            logger.info("⏹️ Agent wird beendet...")
        except Exception as e:
            logger.error(f"❌ Fehler: {e}")
        finally:
            if self.room:
                await self.room.disconnect()
                logger.info("👋 Von Room getrennt")


async def main():
    parser = argparse.ArgumentParser(description="bitHuman LiveKit Agent")
    parser.add_argument("--agent-id", required=True, help="bitHuman Agent ID (z.B. A91XMB7113)")
    parser.add_argument("--room", required=True, help="LiveKit Room Name")
    parser.add_argument("--model", default="essence", choices=["essence", "expression"], help="Avatar Model")
    
    args = parser.parse_args()
    
    # API Secret aus Env
    api_secret = os.getenv("BITHUMAN_API_SECRET")
    if not api_secret:
        logger.error("❌ BITHUMAN_API_SECRET fehlt!")
        return
    
    # Agent erstellen und starten
    agent = BitHumanLiveKitAgent(
        agent_id=args.agent_id,
        api_secret=api_secret,
        model=args.model
    )
    
    await agent.run(args.room)


if __name__ == "__main__":
    asyncio.run(main())

