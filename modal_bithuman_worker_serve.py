#!/usr/bin/env python3
"""
Modal BitHuman Worker (Serve Mode)
===================================
GPU-enabled LiveKit Worker für BitHuman Avatar
Läuft dauerhaft und wartet auf LiveKit Room Events

Deploy: modal deploy modal_bithuman_worker_serve.py
"""

import modal
import logging
import os
import json
from typing import Dict, Any

# Modal Image
image = (
    modal.Image.debian_slim()
    .apt_install("libgl1-mesa-glx", "libglib2.0-0", "libsm6", "libxext6", "libxrender1")
    .pip_install(
        "livekit-agents[openai,bithuman,silero]>=1.2.17",
        "python-dotenv>=1.1.1",
        "firebase-admin>=6.4.0",
        "livekit-plugins-elevenlabs",
        "pinecone>=5.0.0",
        "openai>=1.35.0",
    )
)

app = modal.App("bithuman-worker-serve", image=image)

secrets = [
    modal.Secret.from_name("livekit-cloud"),
    modal.Secret.from_name("bithuman-api"),
    modal.Secret.from_name("openai-api"),
    modal.Secret.from_name("elevenlabs-api"),
    modal.Secret.from_name("firebase-admin"),
    modal.Secret.from_name("pinecone-api"),
]

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

try:
    from pinecone import Pinecone
    from openai import OpenAI as OpenAIClient
    import asyncio
    PINECONE_AVAILABLE = True
except ImportError:
    PINECONE_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("bithuman-worker")


# Knowledge Base (Pinecone)
class KnowledgeBase:
    def __init__(self, pc_key: str, index_name: str, openai_key: str, namespace: str = None):
        self.namespace = namespace
        self.openai_client = OpenAIClient(api_key=openai_key)
        self.pc = Pinecone(api_key=pc_key)
        self.index = self.pc.Index(index_name)
    
    async def query(self, question: str, top_k: int = 5):
        try:
            # Embedding
            resp = await asyncio.to_thread(
                self.openai_client.embeddings.create,
                model="text-embedding-ada-002",
                input=question
            )
            vec = resp.data[0].embedding
            
            # Query Pinecone
            params = {"vector": vec, "top_k": top_k, "include_metadata": True}
            if self.namespace:
                params["namespace"] = self.namespace
            
            results = await asyncio.to_thread(self.index.query, **params)
            
            matches = [m for m in results.matches if m.score > 0.7]
            if not matches:
                return None
            
            context = "\\n\\n".join([
                f"[{m.metadata.get('source', 'Unknown')}]: {m.metadata.get('text', '')}"
                for m in matches[:3]
            ])
            logger.info(f"✅ Pinecone: {len(matches)} matches")
            return context
        except Exception as e:
            logger.error(f"❌ Pinecone: {e}")
            return None


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
                "namespace": f"{data.get('userId', '')}_{doc.id}",
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
    namespace = config.get("namespace")
    bh_model = config.get("bithuman_model", "essence")
    
    logger.info(f"🎤 Voice: {voice_id}, NS: {namespace}, Model: {bh_model}")
    
    # Knowledge Base
    kb = None
    if PINECONE_AVAILABLE and os.getenv("PINECONE_API_KEY"):
        try:
            kb = KnowledgeBase(
                os.getenv("PINECONE_API_KEY"),
                os.getenv("PINECONE_INDEX_NAME", "avatars-index"),
                os.getenv("OPENAI_API_KEY"),
                namespace
            )
            logger.info(f"✅ Knowledge Base initialized (index=avatars-index, namespace={namespace})")
        except Exception as e:
            logger.warning(f"⚠️ Knowledge Base init failed: {e}")
            kb = None
    
    # TTS
    if ELEVENLABS_AVAILABLE and voice_id:
        tts = elevenlabs.TTS(voice_id=voice_id, api_key=os.getenv("ELEVENLABS_API_KEY"))
    else:
        tts = openai.TTS(voice="coral")
    
    # LLM - OHNE voice damit TTS (ElevenLabs) übernimmt!
    base_llm = openai.realtime.RealtimeModel(
        voice=None,  # WICHTIG: None damit ElevenLabs TTS genutzt wird!
        model="gpt-4o-mini-realtime-preview"
    )
    
    # Custom LLM Wrapper with Knowledge Base
    class KBLLM:
        def __init__(self, llm, kb):
            self.llm = llm
            self.kb = kb
        
        async def generate(self, prompt, **kwargs):
            ctx = await self.kb.query(prompt) if self.kb else None
            if ctx:
                prompt = f"Kontext:\\n{ctx}\\n\\nFrage: {prompt}\\n\\nAntworte basierend auf dem Kontext."
            return await self.llm.generate(prompt, **kwargs)
    
    llm = KBLLM(base_llm, kb) if kb else base_llm
    logger.info("✅ LLM initialized")
    
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


@app.function(
    secrets=secrets,
    gpu="T4",
    cpu=2.0,
    memory=8192,
    timeout=300,  # 5 Min max (Demo Mode)
    min_containers=0,  # scale-to-zero
    scaledown_window=120,  # shutdown nach 2 Min idle
)
def run_worker():
    """Runs the LiveKit Worker"""
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            worker_type=WorkerType.ROOM,
            job_memory_warn_mb=4000,
            num_idle_processes=0,
            initialize_process_timeout=180,
        )
    )

