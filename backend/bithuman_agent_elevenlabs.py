#!/usr/bin/env python3
"""
BitHuman LiveKit Agent mit ElevenLabs Voice
---------------------------------------------------------------------------
Dieser Agent verbindet:
- BitHuman Cloud (Avatar Video + Lipsync)
- ElevenLabs (Custom Voice Clone TTS)
- OpenAI Realtime (LLM + STT)
- LiveKit (Room Management)

Wird vom Orchestrator gestartet wenn User "Gespräch starten" klickt.
"""

import logging
import os
import sys
from pathlib import Path
from typing import Optional

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
from livekit.plugins import bithuman, openai, silero

# Optional: ElevenLabs Plugin falls vorhanden
try:
    from livekit.plugins import elevenlabs
    ELEVENLABS_PLUGIN_AVAILABLE = True
except ImportError:
    ELEVENLABS_PLUGIN_AVAILABLE = False
    print("⚠️ livekit-plugins-elevenlabs nicht installiert")

# Firebase Admin für Voice ID Lookup
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False
    print("⚠️ firebase-admin nicht installiert")

# Logging Setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bithuman-elevenlabs-agent")

# Load .env
env_path = Path(__file__).parent / '.env'
if env_path.exists():
    load_dotenv(env_path)
    logger.info(f"✅ .env geladen: {env_path}")


def get_voice_id_from_firebase(agent_id: str) -> Optional[str]:
    """
    Holt elevenVoiceId aus Firebase für gegebene agent_id.
    
    Firebase Struktur:
    avatars/{id}/training/voice/elevenVoiceId
    avatars/{id}/training/voice/cloneVoiceId
    """
    if not FIREBASE_AVAILABLE:
        logger.warning("Firebase nicht verfügbar - nutze DEFAULT_VOICE_ID")
        return None
    
    try:
        # Initialize Firebase (falls noch nicht)
        if not firebase_admin._apps:
            cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
            if cred_path and Path(cred_path).exists():
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                # Application Default Credentials
                firebase_admin.initialize_app()
        
        db = firestore.client()
        
        # Suche Avatar mit liveAvatar.agentId == agent_id
        avatars_ref = db.collection('avatars')
        query = avatars_ref.where('liveAvatar.agentId', '==', agent_id).limit(1)
        docs = query.stream()
        
        for doc in docs:
            data = doc.to_dict()
            voice_data = data.get('training', {}).get('voice', {})
            
            # Priorität: cloneVoiceId > elevenVoiceId
            voice_id = voice_data.get('cloneVoiceId') or voice_data.get('elevenVoiceId')
            
            if voice_id and voice_id != '__CLONE__':
                logger.info(f"✅ Voice ID aus Firebase: {voice_id} für Agent: {agent_id}")
                return voice_id.strip()
        
        logger.warning(f"⚠️ Kein Avatar mit agent_id={agent_id} gefunden in Firebase")
        return None
        
    except Exception as e:
        logger.error(f"❌ Firebase Voice ID Fehler: {e}")
        return None


async def entrypoint(ctx: JobContext):
    """
    LiveKit Agent Entrypoint - wird vom Orchestrator gestartet.
    """
    await ctx.connect()
    logger.info(f"🚀 Agent connected to room: {ctx.room.name}")
    
    # Warte auf Participant
    await ctx.wait_for_participant()
    logger.info(f"✅ Participant joined")
    
    # Credentials validieren
    bithuman_api_secret = os.getenv("BITHUMAN_API_SECRET")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    elevenlabs_api_key = os.getenv("ELEVENLABS_API_KEY")
    
    if not bithuman_api_secret:
        raise ValueError("BITHUMAN_API_SECRET fehlt!")
    if not openai_api_key:
        raise ValueError("OPENAI_API_KEY fehlt!")
    if not elevenlabs_api_key and not ELEVENLABS_PLUGIN_AVAILABLE:
        raise ValueError("ELEVENLABS_API_KEY fehlt und Plugin nicht verfügbar!")
    
    # Agent ID aus ENV oder CLI Argument
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    if not agent_id:
        logger.error("❌ BITHUMAN_AGENT_ID fehlt!")
        raise ValueError("BITHUMAN_AGENT_ID muss gesetzt sein")
    
    logger.info(f"🤖 Using BitHuman Agent ID: {agent_id}")
    
    # Voice ID aus Firebase holen
    voice_id = get_voice_id_from_firebase(agent_id)
    if not voice_id:
        # Fallback zu DEFAULT
        voice_id = os.getenv("ELEVEN_DEFAULT_VOICE_ID", "").strip()
        if not voice_id:
            logger.error("❌ Keine Voice ID gefunden (weder Firebase noch DEFAULT)!")
            raise ValueError("Voice ID fehlt - Agent kann nicht starten")
    
    logger.info(f"🎤 Using ElevenLabs Voice ID: {voice_id}")
    
    # BitHuman Avatar Session initialisieren
    try:
        bithuman_avatar = bithuman.AvatarSession(
            api_url=os.getenv(
                "BITHUMAN_API_URL",
                "https://auth.api.bithuman.ai/v1/runtime-tokens/request"
            ),
            api_secret=bithuman_api_secret,
            avatar_id=agent_id,
        )
        logger.info("✅ BitHuman Avatar Session erstellt")
    except Exception as e:
        logger.error(f"❌ BitHuman Init Fehler: {e}")
        raise
    
    # TTS Setup: ElevenLabs falls Plugin verfügbar, sonst OpenAI Fallback
    if ELEVENLABS_PLUGIN_AVAILABLE:
        logger.info("✅ ElevenLabs Plugin verfügbar - nutze Custom Voice")
        tts_engine = elevenlabs.TTS(
            voice_id=voice_id,
            api_key=elevenlabs_api_key,
        )
    else:
        logger.warning("⚠️ ElevenLabs Plugin NICHT verfügbar - Fallback zu OpenAI Voice")
        # Falls ElevenLabs Plugin fehlt, nutze OpenAI als Fallback
        # ABER: Das ist NICHT die gewünschte Lösung!
        tts_engine = openai.TTS(voice="coral")
    
    # AgentSession mit Custom TTS
    session = AgentSession(
        llm=openai.realtime.RealtimeModel(
            voice=None,  # Voice wird von TTS gehandelt
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini-realtime-preview"),
        ),
        vad=silero.VAD.load(),
        tts=tts_engine,  # ← HIER: Custom TTS!
    )
    
    # BitHuman Avatar mit Session verbinden
    try:
        logger.info("🎬 Starting BitHuman Avatar...")
        await bithuman_avatar.start(session, room=ctx.room)
        logger.info("✅ BitHuman Avatar gestartet")
    except Exception as e:
        logger.error(f"❌ BitHuman Start Fehler: {e}")
        raise
    
    # Agent Instruktionen
    instructions = os.getenv(
        "AGENT_INSTRUCTIONS",
        "Du bist ein hilfreicher KI-Assistent. "
        "Antworte natürlich und freundlich. "
        "Halte deine Antworten kurz und prägnant."
    )
    
    # Agent Session starten
    await session.start(
        agent=Agent(instructions=instructions),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False),  # Audio kommt von BitHuman
    )
    
    logger.info("✅ Agent läuft - bereit für Conversation!")


if __name__ == "__main__":
    # Agent als Worker starten
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            worker_type=WorkerType.ROOM,
            job_memory_warn_mb=2000,
            num_idle_processes=1,
            initialize_process_timeout=300,
        )
    )

