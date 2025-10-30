#!/usr/bin/env python3
"""
Modal.com App - BitHuman Agent COMPLETE
========================================
Deploy: modal deploy modal_bithuman_final.py

Features:
- Pinecone Knowledge Base (Primary)
- ElevenLabs Custom Voice
- OpenAI Fallback
- Firebase Config
- BitHuman Avatar
"""

import modal
import os

# === MODAL IMAGE MIT ALLEN DEPENDENCIES ===
image = (
    modal.Image.debian_slim()
    .pip_install(
        # Core
        "livekit-agents[openai,bithuman,silero]>=1.2.16",
        "python-dotenv>=1.1.1",
        
        # Knowledge Base
        "pinecone-client>=3.0.0",
        "openai>=1.35.0",
        
        # Firebase
        "firebase-admin>=6.4.0",
        
        # Utils
        "aiohttp>=3.8.0",
        "fastapi>=0.115.0",
        "loguru>=0.7.3",
    )
    # Versuche ElevenLabs Plugin (falls verfügbar)
    .run_commands(
        "pip install livekit-plugins-elevenlabs || echo 'ElevenLabs plugin wird zur Laufzeit geprüft'",
        gpu=None,
    )
)

app = modal.App("bithuman-complete-agent", image=image)

# === MODAL SECRETS ===
secrets = [
    modal.Secret.from_name("livekit-cloud"),      # LIVEKIT_URL, API_KEY, API_SECRET
    modal.Secret.from_name("bithuman-api"),       # BITHUMAN_API_SECRET
    modal.Secret.from_name("openai-api"),         # OPENAI_API_KEY
    modal.Secret.from_name("elevenlabs-api"),     # ELEVENLABS_API_KEY, ELEVEN_DEFAULT_VOICE_ID
    modal.Secret.from_name("pinecone-api"),       # PINECONE_API_KEY, PINECONE_INDEX_NAME
    modal.Secret.from_name("firebase-admin"),     # FIREBASE_CREDENTIALS (JSON)
]


@app.function(
    secrets=secrets,
    timeout=3600,  # 60 Min
    cpu=2.0,
    memory=4096,
    keep_warm=1,  # 1 Container warm halten
)
def start_agent(room: str, agent_id: str):
    """
    Startet BitHuman Agent für Room.
    
    Args:
        room: LiveKit Room Name
        agent_id: BitHuman Agent ID (aus Firebase liveAvatar.agentId)
    """
    import subprocess
    import sys
    import tempfile
    from pathlib import Path
    
    # ENV setzen
    env = os.environ.copy()
    env["BITHUMAN_AGENT_ID"] = agent_id
    
    print(f"🚀 Starting Agent: room={room}, agent={agent_id}")
    
    # === AGENT CODE INLINE (damit Modal es findet) ===
    agent_code = '''
import logging
import os
from pathlib import Path
from typing import Optional, Dict, Any
import asyncio

from livekit.agents import Agent, AgentSession, JobContext, RoomOutputOptions, WorkerOptions, WorkerType, cli
from livekit.plugins import bithuman, openai, silero

# ElevenLabs
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

# Pinecone
try:
    from pinecone import Pinecone
    from openai import OpenAI
    PINECONE_AVAILABLE = True
except ImportError:
    PINECONE_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agent")


class KnowledgeBase:
    """Pinecone + OpenAI Embeddings"""
    def __init__(self, pc_key: str, index_name: str, openai_key: str, namespace: str = None):
        self.namespace = namespace
        self.openai_client = OpenAI(api_key=openai_key)
        self.pc = Pinecone(api_key=pc_key)
        self.index = self.pc.Index(index_name)
    
    async def query(self, question: str, top_k: int = 5) -> Optional[str]:
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
    """Firebase Config"""
    if not FIREBASE_AVAILABLE:
        return {}
    try:
        if not firebase_admin._apps:
            import json
            creds = os.getenv("FIREBASE_CREDENTIALS")
            if creds:
                cred = credentials.Certificate(json.loads(creds))
                firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        query = db.collection('avatars').where('liveAvatar.agentId', '==', agent_id).limit(1)
        
        for doc in query.stream():
            data = doc.to_dict()
            voice = data.get('training', {}).get('voice', {})
            vid = voice.get('cloneVoiceId') or voice.get('elevenVoiceId')
            if vid == '__CLONE__':
                vid = None
            
            return {
                'voice_id': vid.strip() if vid else None,
                'namespace': f"{data.get('userId', '')}_{doc.id}",
                'instructions': data.get('personality'),
                'name': data.get('name', 'Avatar'),
            }
        return {}
    except Exception as e:
        logger.error(f"Firebase error: {e}")
        return {}


async def entrypoint(ctx: JobContext):
    await ctx.connect()
    await ctx.wait_for_participant()
    
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    config = get_config(agent_id)
    
    voice_id = config.get('voice_id') or os.getenv("ELEVEN_DEFAULT_VOICE_ID")
    namespace = config.get('namespace')
    
    logger.info(f"Agent: {agent_id}, Voice: {voice_id}, NS: {namespace}")
    
    # Knowledge Base
    kb = None
    if PINECONE_AVAILABLE and os.getenv("PINECONE_API_KEY"):
        kb = KnowledgeBase(
            os.getenv("PINECONE_API_KEY"),
            os.getenv("PINECONE_INDEX_NAME", "sunriza-knowledge"),
            os.getenv("OPENAI_API_KEY"),
            namespace
        )
    
    # BitHuman Avatar
    avatar = bithuman.AvatarSession(
        api_url=os.getenv("BITHUMAN_API_URL", "https://auth.api.bithuman.ai/v1/runtime-tokens/request"),
        api_secret=os.getenv("BITHUMAN_API_SECRET"),
        avatar_id=agent_id,
    )
    
    # TTS
    if ELEVENLABS_AVAILABLE and voice_id:
        tts = elevenlabs.TTS(voice_id=voice_id, api_key=os.getenv("ELEVENLABS_API_KEY"))
    else:
        tts = openai.TTS(voice="coral")
    
    # LLM mit Pinecone
    base_llm = openai.realtime.RealtimeModel(model="gpt-4o-mini-realtime-preview")
    
    # Custom LLM Wrapper
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
    
    # Session
    session = AgentSession(llm=llm, vad=silero.VAD.load(), tts=tts)
    await avatar.start(session, room=ctx.room)
    
    instructions = config.get('instructions') or f"Du bist {config.get('name', 'Avatar')}, ein hilfreicher Assistent."
    await session.start(
        agent=Agent(instructions=instructions),
        room=ctx.room,
        room_output_options=RoomOutputOptions(audio_enabled=False)
    )


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, worker_type=WorkerType.ROOM))
'''
    
    # Agent Code in temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(agent_code)
        agent_file = f.name
    
    try:
        # Agent starten (blockiert bis Session endet)
        result = subprocess.run(
            [sys.executable, agent_file, "start"],
            env=env,
            capture_output=True,
            text=True,
            timeout=3500,  # 58 Min
        )
        
        print(f"✅ Agent finished: {result.returncode}")
        if result.stdout:
            print(f"STDOUT:\n{result.stdout}")
        if result.stderr:
            print(f"STDERR:\n{result.stderr}")
        
        # Cleanup
        Path(agent_file).unlink(missing_ok=True)
        
        return {"status": "completed", "exit_code": result.returncode}
        
    except subprocess.TimeoutExpired:
        print("⏱️ Timeout (normal)")
        Path(agent_file).unlink(missing_ok=True)
        return {"status": "timeout"}
    except Exception as e:
        print(f"❌ Error: {e}")
        Path(agent_file).unlink(missing_ok=True)
        return {"status": "error", "message": str(e)}


@app.function(secrets=secrets)
@modal.web_endpoint(method="POST")
def join(data: dict):
    """
    Webhook: Startet Agent ODER Health Check
    
    POST /join
    Body: {"room": "room-abc", "agent_id": "A91XMB7113"}
    
    GET /join (für Health Check)
    """
    # Health Check bei GET oder leeren POST
    if not data or data.get("health"):
        return {
            "status": "ok",
            "service": "bithuman-complete-agent",
            "features": [
                "Pinecone Knowledge Base",
                "ElevenLabs Custom Voice",
                "OpenAI Fallback",
                "Firebase Config",
                "BitHuman Avatar"
            ]
        }
    
    room = data.get("room", "").strip()
    agent_id = data.get("agent_id", "").strip()
    
    if not room or not agent_id:
        return {"status": "error", "message": "room and agent_id required"}
    
    print(f"🎬 Join request: room={room}, agent={agent_id}")
    
    # Agent asynchron starten
    start_agent.spawn(room, agent_id)
    
    return {"status": "started", "room": room, "agent_id": agent_id}

