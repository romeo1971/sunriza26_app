#!/usr/bin/env python3
"""
BitHuman LiveKit Agent - COMPLETE PRODUCTION VERSION
=====================================================
- Pinecone als Primary Knowledge Base
- ElevenLabs Custom Voice Clone
- OpenAI als Fallback
- BitHuman Avatar mit Lipsync
- Firebase für Config/Voice IDs
"""

import logging
import os
import sys
from pathlib import Path
from typing import Optional, List, Dict, Any
import asyncio

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

# ElevenLabs Plugin (falls vorhanden)
try:
    from livekit.plugins import elevenlabs
    ELEVENLABS_AVAILABLE = True
except ImportError:
    ELEVENLABS_AVAILABLE = False
    print("⚠️ livekit-plugins-elevenlabs nicht installiert")

# Firebase Admin
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False
    print("⚠️ firebase-admin nicht installiert")

# Pinecone
try:
    from pinecone import Pinecone, ServerlessSpec
    PINECONE_AVAILABLE = True
except ImportError:
    PINECONE_AVAILABLE = False
    print("⚠️ pinecone-client nicht installiert")

# OpenAI für Embeddings
try:
    from openai import OpenAI
    OPENAI_CLIENT_AVAILABLE = True
except ImportError:
    OPENAI_CLIENT_AVAILABLE = False
    print("⚠️ openai client nicht installiert")

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bithuman-agent")

# .env laden
env_path = Path(__file__).parent / '.env'
if env_path.exists():
    load_dotenv(env_path)
    logger.info(f"✅ .env geladen: {env_path}")


class KnowledgeBase:
    """Pinecone Knowledge Base mit OpenAI Fallback"""
    
    def __init__(
        self,
        pinecone_api_key: str,
        pinecone_index_name: str,
        openai_api_key: str,
        namespace: str = None,
    ):
        self.namespace = namespace
        self.openai_client = OpenAI(api_key=openai_api_key) if OPENAI_CLIENT_AVAILABLE else None
        
        # Pinecone initialisieren
        if PINECONE_AVAILABLE and pinecone_api_key:
            try:
                self.pc = Pinecone(api_key=pinecone_api_key)
                self.index = self.pc.Index(pinecone_index_name)
                logger.info(f"✅ Pinecone verbunden: {pinecone_index_name}")
            except Exception as e:
                logger.error(f"❌ Pinecone Fehler: {e}")
                self.pc = None
                self.index = None
        else:
            self.pc = None
            self.index = None
    
    async def query(self, question: str, top_k: int = 5) -> Optional[str]:
        """
        Fragt Pinecone Knowledge Base.
        Returns: Context String oder None
        """
        if not self.index or not self.openai_client:
            logger.warning("⚠️ Pinecone oder OpenAI Client nicht verfügbar")
            return None
        
        try:
            # 1. Embedding für Frage erstellen
            response = await asyncio.to_thread(
                self.openai_client.embeddings.create,
                model="text-embedding-ada-002",
                input=question,
            )
            query_embedding = response.data[0].embedding
            
            # 2. Pinecone Query
            query_params = {
                "vector": query_embedding,
                "top_k": top_k,
                "include_metadata": True,
            }
            if self.namespace:
                query_params["namespace"] = self.namespace
            
            results = await asyncio.to_thread(
                self.index.query,
                **query_params
            )
            
            if not results.matches:
                logger.info("ℹ️ Pinecone: Keine Matches gefunden")
                return None
            
            # 3. Relevante Matches filtern (Score > 0.7)
            relevant_matches = [m for m in results.matches if m.score > 0.7]
            
            if not relevant_matches:
                logger.info("ℹ️ Pinecone: Keine relevanten Matches (Score < 0.7)")
                return None
            
            # 4. Context zusammenbauen
            context_parts = []
            for match in relevant_matches[:3]:  # Top 3
                text = match.metadata.get('text', '')
                source = match.metadata.get('source', 'Unknown')
                context_parts.append(f"[{source}]: {text}")
            
            context = "\n\n".join(context_parts)
            logger.info(f"✅ Pinecone Context: {len(context)} chars, {len(relevant_matches)} matches")
            return context
            
        except Exception as e:
            logger.error(f"❌ Pinecone Query Fehler: {e}")
            return None


def get_firebase_config(agent_id: str) -> Dict[str, Any]:
    """
    Holt Config aus Firebase für Agent ID.
    
    Returns:
        {
            'voice_id': str,
            'namespace': str,
            'instructions': str,
        }
    """
    if not FIREBASE_AVAILABLE:
        logger.warning("⚠️ Firebase nicht verfügbar")
        return {}
    
    try:
        if not firebase_admin._apps:
            # Initialize Firebase
            cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
            if cred_path and Path(cred_path).exists():
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                firebase_admin.initialize_app()
        
        db = firestore.client()
        
        # Suche Avatar mit agent_id
        avatars_ref = db.collection('avatars')
        query = avatars_ref.where('liveAvatar.agentId', '==', agent_id).limit(1)
        docs = query.stream()
        
        for doc in docs:
            data = doc.to_dict()
            
            # Voice ID
            voice_data = data.get('training', {}).get('voice', {})
            voice_id = voice_data.get('cloneVoiceId') or voice_data.get('elevenVoiceId')
            if voice_id == '__CLONE__':
                voice_id = None
            
            # Namespace für Pinecone
            user_id = data.get('userId', '')
            avatar_id = doc.id
            namespace = f"{user_id}_{avatar_id}" if user_id else avatar_id
            
            # Instructions/Personality
            instructions = data.get('personality') or data.get('description') or None
            
            config = {
                'voice_id': voice_id.strip() if voice_id else None,
                'namespace': namespace,
                'instructions': instructions,
                'avatar_name': data.get('name', 'Avatar'),
            }
            
            logger.info(f"✅ Firebase Config: {config}")
            return config
        
        logger.warning(f"⚠️ Kein Avatar mit agent_id={agent_id} gefunden")
        return {}
        
    except Exception as e:
        logger.error(f"❌ Firebase Config Fehler: {e}")
        return {}


async def entrypoint(ctx: JobContext):
    """
    LiveKit Agent Entrypoint - PRODUCTION VERSION
    """
    await ctx.connect()
    logger.info(f"🚀 Agent connected to room: {ctx.room.name}")
    
    # Warte auf Participant
    await ctx.wait_for_participant()
    logger.info(f"✅ Participant joined")
    
    # === ENVIRONMENT VARIABLES ===
    bithuman_api_secret = os.getenv("BITHUMAN_API_SECRET")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    elevenlabs_api_key = os.getenv("ELEVENLABS_API_KEY")
    pinecone_api_key = os.getenv("PINECONE_API_KEY")
    pinecone_index = os.getenv("PINECONE_INDEX_NAME", "sunriza26-avatar-data")
    
    # Validierung
    if not bithuman_api_secret:
        raise ValueError("BITHUMAN_API_SECRET fehlt!")
    if not openai_api_key:
        raise ValueError("OPENAI_API_KEY fehlt!")
    if not elevenlabs_api_key and not ELEVENLABS_AVAILABLE:
        logger.warning("⚠️ ELEVENLABS_API_KEY fehlt - Fallback zu OpenAI Voice")
    
    # Agent ID aus ENV
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    if not agent_id:
        raise ValueError("BITHUMAN_AGENT_ID muss gesetzt sein!")
    
    logger.info(f"🤖 Agent ID: {agent_id}")
    
    # === FIREBASE CONFIG LADEN ===
    firebase_config = get_firebase_config(agent_id)
    voice_id = firebase_config.get('voice_id')
    namespace = firebase_config.get('namespace')
    custom_instructions = firebase_config.get('instructions')
    avatar_name = firebase_config.get('avatar_name', 'Avatar')
    
    # Fallback Voice ID
    if not voice_id:
        voice_id = os.getenv("ELEVEN_DEFAULT_VOICE_ID", "").strip()
        if not voice_id:
            logger.warning("⚠️ Keine Voice ID - nutze OpenAI Fallback")
    
    logger.info(f"🎤 Voice ID: {voice_id}")
    logger.info(f"📚 Pinecone Namespace: {namespace}")
    
    # === KNOWLEDGE BASE ===
    kb = None
    if pinecone_api_key and PINECONE_AVAILABLE:
        kb = KnowledgeBase(
            pinecone_api_key=pinecone_api_key,
            pinecone_index_name=pinecone_index,
            openai_api_key=openai_api_key,
            namespace=namespace,
        )
        logger.info("✅ Knowledge Base initialisiert")
    else:
        logger.warning("⚠️ Pinecone nicht verfügbar - Nur OpenAI Fallback")
    
    # === BITHUMAN AVATAR ===
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
    
    # === TTS SETUP ===
    if ELEVENLABS_AVAILABLE and voice_id and elevenlabs_api_key:
        logger.info("✅ ElevenLabs TTS aktiviert")
        tts_engine = elevenlabs.TTS(
            voice_id=voice_id,
            api_key=elevenlabs_api_key,
        )
    else:
        logger.warning("⚠️ ElevenLabs nicht verfügbar - OpenAI TTS Fallback")
        tts_engine = openai.TTS(voice="coral")
    
    # === AGENT SESSION MIT CUSTOM LOGIC ===
    
    # Custom LLM Wrapper für Pinecone Integration
    class KnowledgeAugmentedLLM:
        """Wrapper der Pinecone Context in Prompts einfügt"""
        
        def __init__(self, base_llm, knowledge_base: Optional[KnowledgeBase]):
            self.base_llm = base_llm
            self.kb = knowledge_base
        
        async def generate(self, prompt: str, **kwargs):
            # Query Pinecone
            context = None
            if self.kb:
                context = await self.kb.query(prompt)
            
            # Context in Prompt einfügen
            if context:
                augmented_prompt = f"""Kontext aus Knowledge Base:
{context}

Frage: {prompt}

Antworte basierend auf dem Kontext. Falls der Kontext nicht ausreicht, sage das ehrlich."""
                logger.info("✅ Prompt mit Pinecone Context erweitert")
            else:
                augmented_prompt = prompt
                logger.info("ℹ️ Kein Pinecone Context - OpenAI beantwortet direkt")
            
            # An Base LLM weiterleiten
            return await self.base_llm.generate(augmented_prompt, **kwargs)
    
    # Base LLM
    base_llm = openai.realtime.RealtimeModel(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini-realtime-preview"),
    )
    
    # Mit Knowledge Base wrappen
    llm = KnowledgeAugmentedLLM(base_llm, kb)
    
    # Agent Session
    session = AgentSession(
        llm=llm,
        vad=silero.VAD.load(),
        tts=tts_engine,
    )
    
    # === BITHUMAN AVATAR STARTEN ===
    try:
        logger.info("🎬 Starting BitHuman Avatar...")
        await bithuman_avatar.start(session, room=ctx.room)
        logger.info("✅ BitHuman Avatar gestartet")
    except Exception as e:
        logger.error(f"❌ BitHuman Start Fehler: {e}")
        raise
    
    # === AGENT INSTRUCTIONS ===
    default_instructions = f"""Du bist {avatar_name}, ein hilfreicher KI-Assistent.

Wichtig:
- Nutze die Knowledge Base wenn verfügbar
- Antworte natürlich und freundlich
- Halte Antworten kurz und prägnant
- Wenn du etwas nicht weißt, sage es ehrlich
"""
    
    instructions = custom_instructions or default_instructions
    
    # === AGENT STARTEN ===
    await session.start(
        agent=Agent(instructions=instructions),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False),
    )
    
    logger.info("✅ Agent läuft - bereit für Conversation!")


if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            worker_type=WorkerType.ROOM,
            job_memory_warn_mb=2000,
            num_idle_processes=0,  # Scale-to-zero! Nur aktiv wenn Chat läuft
            initialize_process_timeout=300,
        )
    )

