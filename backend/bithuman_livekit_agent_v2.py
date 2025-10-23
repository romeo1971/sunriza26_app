#!/usr/bin/env python3
"""
bitHuman LiveKit Agent (Local Runtime API)

WICHTIG: Nutzt die LOCAL Runtime API, nicht die Cloud API!
Die PDF-Dokumentation beschreibt eine zukünftige Cloud-API.

Die tatsächliche API braucht:
- Ein lokales .imx Model File (von bitHuman Platform herunterladen)
- ODER api_secret zum automatischen Download

Setup:
  pip install bithuman livekit livekit-agents python-dotenv
  
  # Model herunterladen von imaginex.bithuman.ai
  # Oder api_secret verwenden für Auto-Download

Usage:
  export BITHUMAN_API_SECRET="your_secret"
  export LIVEKIT_URL="wss://your-livekit-server.com"
  export LIVEKIT_API_KEY="your_key"
  export LIVEKIT_API_SECRET="your_secret"
  
  python bithuman_livekit_agent_v2.py --model-path path/to/model.imx --room my-room
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
    """LiveKit Agent mit bitHuman Local Runtime"""
    
    def __init__(
        self, 
        model_path: Optional[str] = None,
        api_secret: Optional[str] = None,
        livekit_url: str = None,
        livekit_api_key: str = None,
        livekit_api_secret: str = None
    ):
        self.model_path = model_path
        self.api_secret = api_secret or os.getenv("BITHUMAN_API_SECRET")
        
        # LiveKit Credentials
        self.livekit_url = livekit_url or os.getenv("LIVEKIT_URL")
        self.livekit_api_key = livekit_api_key or os.getenv("LIVEKIT_API_KEY")
        self.livekit_api_secret = livekit_api_secret or os.getenv("LIVEKIT_API_SECRET")
        
        if not all([self.livekit_url, self.livekit_api_key, self.livekit_api_secret]):
            raise ValueError("LiveKit credentials fehlen!")
        
        if not self.model_path and not self.api_secret:
            raise ValueError("Entweder model_path ODER api_secret muss angegeben werden!")
        
        self.room: Optional[rtc.Room] = None
        self.runtime: Optional[bithuman.AsyncBithuman] = None
        
    async def initialize_runtime(self):
        """Initialisiert bitHuman Runtime"""
        logger.info("🤖 Initialisiere bitHuman Runtime...")
        
        try:
            # Create AsyncBithuman instance
            if self.model_path:
                logger.info(f"   Loading model from: {self.model_path}")
                self.runtime = await bithuman.AsyncBithuman.create(
                    model_path=self.model_path,
                    api_secret=self.api_secret,
                )
            else:
                logger.info("   Using api_secret (model wird automatisch geladen)")
                self.runtime = await bithuman.AsyncBithuman.create(
                    api_secret=self.api_secret,
                )
            
            # Load model data
            await self.runtime.load_data_async()
            
            logger.info("✅ bitHuman Runtime initialisiert")
            
        except Exception as e:
            logger.error(f"❌ Runtime Initialisierung fehlgeschlagen: {e}")
            raise
    
    async def connect_to_room(self, room_name: str):
        """Verbindet Agent mit LiveKit Room"""
        logger.info(f"🔗 Verbinde mit Room: {room_name}")
        
        # Token generieren
        token = api.AccessToken(self.livekit_api_key, self.livekit_api_secret)
        token.with_identity("bithuman-agent")
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
        
        # TODO: Audio von LiveKit → bitHuman Runtime
        # TODO: Video von bitHuman Runtime → LiveKit Room publishen
        
        # Placeholder:
        logger.warning("⚠️ Audio Processing noch nicht implementiert")
        logger.warning("⚠️ Video Publishing noch nicht implementiert")
        logger.info("💡 Siehe bitHuman Dokumentation für Audio/Video Integration")
    
    async def run(self, room_name: str):
        """Hauptloop"""
        try:
            await self.initialize_runtime()
            await self.connect_to_room(room_name)
            
            logger.info("🚀 Agent läuft... (Ctrl+C zum Beenden)")
            logger.warning("")
            logger.warning("⚠️ HINWEIS: Audio/Video Processing noch nicht vollständig implementiert!")
            logger.warning("   Die PDFs beschreiben eine zukünftige Cloud-API")
            logger.warning("   Die tatsächliche API ist anders und nutzt lokale .imx Dateien")
            logger.warning("")
            
            # Warte auf Disconnect
            await asyncio.Event().wait()
            
        except KeyboardInterrupt:
            logger.info("⏹️ Agent wird beendet...")
        except Exception as e:
            logger.error(f"❌ Fehler: {e}")
            import traceback
            traceback.print_exc()
        finally:
            if self.room:
                await self.room.disconnect()
                logger.info("👋 Von Room getrennt")


async def main():
    parser = argparse.ArgumentParser(description="bitHuman LiveKit Agent (Local Runtime)")
    parser.add_argument("--model-path", help="Path to .imx model file")
    parser.add_argument("--room", required=True, help="LiveKit Room Name")
    
    args = parser.parse_args()
    
    # API Secret aus Env
    api_secret = os.getenv("BITHUMAN_API_SECRET")
    
    if not args.model_path and not api_secret:
        logger.error("❌ Entweder --model-path ODER BITHUMAN_API_SECRET erforderlich!")
        logger.info("💡 Model herunterladen von: imaginex.bithuman.ai")
        return
    
    # Agent erstellen und starten
    agent = BitHumanLiveKitAgent(
        model_path=args.model_path,
        api_secret=api_secret
    )
    
    await agent.run(args.room)


if __name__ == "__main__":
    asyncio.run(main())

