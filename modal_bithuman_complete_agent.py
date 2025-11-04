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
    # Systemabhängigkeiten für OpenCV (headless ausreichend, aber libs schaden nicht) [REBUILD v2]
    .apt_install("libgl1-mesa-glx", "libglib2.0-0", "libsm6", "libxext6", "libxrender1")
    .pip_install(
        # Core
        "livekit-agents[openai,bithuman,silero]>=1.2.17",
        "python-dotenv>=1.1.1",
        # OpenCV headless (erzwingen, Headful deinstallieren)
        "opencv-python-headless==4.10.0.84",
        
        # Knowledge Base (neues SDK)
        "pinecone>=5.0.0",
        "openai>=1.35.0",
        
        # Mistral AI
        "mistralai>=1.0.0",
        
        # Firebase
        "firebase-admin>=6.4.0",
        
        # Utils
        "aiohttp>=3.8.0",
        "fastapi>=0.115.0",
        "loguru>=0.7.3",
    )
    # Versuche ElevenLabs Plugin (falls verfügbar)
    .run_commands(
        # Entferne evtl. installiertes opencv-python (headful)
        "python -m pip uninstall -y opencv-python opencv-contrib-python pinecone-client || true",
        "pip install --no-cache-dir --force-reinstall opencv-python-headless==4.10.0.84",
        "pip install livekit-plugins-elevenlabs || echo 'ElevenLabs plugin wird zur Laufzeit geprüft'",
        # Sichtprüfung der installierten Pinecone-Pakete
        "python -m pip install --upgrade pip setuptools wheel",
        "python -m pip list | grep -i pinecone || true",
        "echo 'REBUILD: 2025-10-31-19:30'",  # ← Change date/time to force rebuild
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
    modal.Secret.from_name("mistral-api"),        # MISTRAL_API_KEY
]


@app.function(
    secrets=secrets,
    cpu=2.0,
    memory=4096,
    timeout=300,  # 5 Min max (Demo Mode)
    min_containers=0,  # scale-to-zero
    scaledown_window=120,  # shutdown nach 2 Min idle
)
def run_agent(room: str, agent_id: str):
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

    # Sicherstellen: korrektes Pinecone SDK zur Laufzeit erzwingen (kein pinecone-client)
    try:
        import subprocess as _sp
        _sp.run([sys.executable, "-m", "pip", "uninstall", "-y", "pinecone-client"], check=False)
        _sp.run([sys.executable, "-m", "pip", "install", "--no-cache-dir", "pinecone==5.0.1"], check=False)
    except Exception as _e:
        print(f"⚠️ Pinecone runtime setup skipped: {_e}")

    # LiveKit Token besorgen (vom Orchestrator) → garantiert passender Raum
    import requests as _req
    try:
        orch = os.getenv("ORCHESTRATOR_URL", "https://romeo1971--lipsync-orchestrator-asgi.modal.run").rstrip("/")
        tk_res = _req.get(f"{orch}/livekit/token", params={"room": room, "avatar_id": agent_id, "user_id": "agent"}, timeout=10)
        tk_res.raise_for_status()
        tk_json = tk_res.json()
        lk_url = tk_json.get("url")
        lk_token = tk_json.get("token")
        if not lk_url or not lk_token:
            raise RuntimeError("LiveKit token response invalid")
        env["LK_URL"] = lk_url
        env["LK_TOKEN"] = lk_token
    except Exception as e:
        print(f"❌ Could not mint LiveKit token: {e}")
        return {"status": "error", "message": str(e)}

    print(f"🚀 Starting Agent: room={room}, agent={agent_id}")
    
    # === AGENT CODE INLINE (damit Modal es findet) ===
    agent_code = '''
import logging
import os
from pathlib import Path
from typing import Optional, Dict, Any
import asyncio

from livekit.agents import Agent, AgentSession, RoomOutputOptions
from livekit import rtc
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
            
            # BitHuman Model aus liveAvatar.model lesen
            live_avatar = data.get('liveAvatar', {})
            bh_model = live_avatar.get('model', 'expression')  # Default: expression
            
            return {
                'voice_id': vid.strip() if vid else None,
                'namespace': f"{data.get('userId', '')}_{doc.id}",
                'instructions': data.get('personality'),
                'name': data.get('name', 'Avatar'),
                'bithuman_model': bh_model,
            }
        return {}
    except Exception as e:
        logger.error(f"Firebase error: {e}")
        return {}


async def main():
    url = os.getenv("LK_URL")
    token = os.getenv("LK_TOKEN")
    if not url or not token:
        logger.error("❌ LK_URL/LK_TOKEN not set")
        return
    room = rtc.Room()
    await room.connect(url, token)
    logger.info("✅ Connected to LiveKit room")
    
    agent_id = os.getenv("BITHUMAN_AGENT_ID")
    if not agent_id:
        logger.error("❌ BITHUMAN_AGENT_ID not set!")
        return
    
    # WICHTIG: Warte auf Teilnehmer wie bithumanProd!
    logger.info("⏳ Waiting for participant to join...")
    # Warte bis mindestens 1 Teilnehmer im Room ist (außer uns selbst)
    while len([p for p in room.remote_participants.values()]) == 0:
        await asyncio.sleep(0.5)
    logger.info("✅ Participant joined!")
    
    config = get_config(agent_id)
    voice_id = config.get('voice_id') or os.getenv("ELEVEN_DEFAULT_VOICE_ID")
    namespace = config.get('namespace')
    bh_model = config.get('bithuman_model', 'expression')  # Default: expression
    
    logger.info(f"🤖 Agent: {agent_id}, Voice: {voice_id}, NS: {namespace}, Model: {bh_model}")
    
    # Knowledge Base (Avatar-spezifischer Index!)
    kb = None
    if PINECONE_AVAILABLE and os.getenv("PINECONE_API_KEY"):
        try:
            kb = KnowledgeBase(
                os.getenv("PINECONE_API_KEY"),
                os.getenv("PINECONE_INDEX_NAME", "avatars-index"),  # RICHTIG: Avatar-Index, nicht global!
                os.getenv("OPENAI_API_KEY"),
                namespace
            )
            logger.info(f"✅ Knowledge Base initialized (index=avatars-index, namespace={namespace})")
        except Exception as e:
            logger.warning(f"⚠️ Knowledge Base init failed (continuing without KB): {e}")
            kb = None
    
    # LLM Setup - Mistral AI (kein OpenAI für LLM!)
    try:
        from mistralai import Mistral as MistralClient
        mistral_client = MistralClient(api_key=os.getenv("MISTRAL_API_KEY"))
        MISTRAL_AVAILABLE = True
    except Exception as e:
        logger.warning(f"⚠️ Mistral import failed: {e}")
        mistral_client = None
        MISTRAL_AVAILABLE = False
    
    # Custom LLM Wrapper mit Pinecone + Mistral
    class PineconeMistralLLM:
        def __init__(self, mistral_client, kb):
            self.mistral = mistral_client
            self.kb = kb
        
        async def chat(self, chat_ctx):
            # Letzten User-Prompt holen
            last_msg = chat_ctx.messages[-1] if chat_ctx.messages else None
            if not last_msg or last_msg.role != "user":
                # Fallback ohne Kontext
                resp = await asyncio.to_thread(
                    self.mistral.chat.complete,
                    model="mistral-small-latest",
                    messages=[{"role": m.role, "content": m.content} for m in chat_ctx.messages]
                )
                return resp.choices[0].message.content
            
            prompt = last_msg.content
            
            # 1. Pinecone abfragen
            ctx = await self.kb.query(prompt) if self.kb else None
            
            # 2. Wenn Pinecone Kontext hat → DIREKT zurückgeben (KEINE LLM Moderation!)
            if ctx and ctx.strip():
                logger.info("✅ Pinecone Kontext gefunden → DIREKTE Antwort (kein LLM)")
                return ctx
            
            # 3. Nur wenn KEIN Pinecone Kontext → Mistral AI
            logger.info("⚠️ Kein Pinecone Kontext → Mistral AI Fallback")
            resp = await asyncio.to_thread(
                self.mistral.chat.complete,
                model="mistral-small-latest",
                messages=[{"role": m.role, "content": m.content} for m in chat_ctx.messages]
            )
            return resp.choices[0].message.content
    
    # LLM Setup basierend auf verfügbaren Services
    if MISTRAL_AVAILABLE and kb:
        llm = PineconeMistralLLM(mistral_client, kb)
        logger.info("✅ LLM: Pinecone + Mistral (BitHuman Voice aktiv!)")
    else:
        llm = openai.LLM(model="gpt-4o-mini")
        logger.info("⚠️ Fallback: OpenAI LLM (Mistral/Pinecone nicht verfügbar)")
    
    # TTS Setup: ElevenLabs falls Voice-ID vorhanden, sonst BitHuman intern
    tts = None
    if ELEVENLABS_AVAILABLE and voice_id:
        logger.info(f"✅ ElevenLabs TTS aktiviert (Voice: {voice_id})")
        tts = elevenlabs.TTS(
            voice_id=voice_id,
            api_key=os.getenv("ELEVENLABS_API_KEY"),
        )
    else:
        logger.info("⚠️ Kein ElevenLabs → BitHuman nutzt interne Voice (vom audioUrl)")
    
    # Agent Session (VAD + LLM + optional TTS)
    session = AgentSession(
        llm=llm,
        vad=silero.VAD.load(),
        tts=tts  # None = BitHuman nutzt audioUrl, sonst ElevenLabs
    )
    logger.info("✅ Agent Session created")
    
    # BitHuman Avatar Session (Cloud Plugin)
    logger.info(f"🎬 Creating BitHuman Avatar Session (model={bh_model})...")
    
    try:
        # WICHTIG: model_path für lokales Model ODER avatar_id für Cloud
        # Da wir Cloud nutzen: nur avatar_id + api_secret
        avatar = bithuman.AvatarSession(
            avatar_id=agent_id,
            api_secret=os.getenv("BITHUMAN_API_SECRET"),
            model=bh_model,  # essence oder expression
        )
        logger.info(f"✅ BitHuman Avatar Session created (model={bh_model})")
        
        # START BitHuman Avatar
        logger.info("🚀 Starting BitHuman Avatar (streaming video to room)...")
        await avatar.start(session, room=room)
        logger.info("🎥 BitHuman Avatar STARTED - Video Track published!")
        
        # Start Agent
        instructions = config.get('instructions') or f"Du bist {config.get('name', 'Avatar')}, ein hilfreicher Assistent."
        logger.info(f"🤖 Starting Agent with instructions...")
        await session.start(
            agent=Agent(instructions=instructions),
            room=room,
            room_output_options=RoomOutputOptions(audio_enabled=False)
        )
        logger.info("✅ Agent fully running - listening for speech!")
        
        # CUSTOM: Höre auch auf orchestrator-audio für ElevenLabs TTS
        async def forward_orchestrator_audio():
            """Forward audio from orchestrator-audio directly to BitHuman Avatar"""
            logger.info("🎧 Listening for orchestrator-audio tracks...")
            for participant_id, participant in room.remote_participants.items():
                if participant.identity == "orchestrator-audio":
                    logger.info(f"✅ Found orchestrator-audio participant!")
                    for track_id, track_pub in participant.track_publications.items():
                        if track_pub.kind == rtc.TrackKind.KIND_AUDIO and track_pub.track:
                            logger.info(f"🎵 Subscribing to orchestrator-audio track: {track_id}")
                            track = track_pub.track
                            # Forward audio frames directly to Avatar (bypass LLM/VAD)
                            async for frame in rtc.AudioStream(track):
                                # BitHuman Avatar nutzt den Audio-Stream automatisch für Lipsync
                                logger.debug(f"📥 Audio frame from orchestrator: {len(frame.data)} bytes")
        
        # Start orchestrator audio forwarding in background
        asyncio.create_task(forward_orchestrator_audio())
        
        # Keep session alive
        logger.info("⏳ Session running - waiting for disconnect...")
        try:
            await room.wait_for_disconnect()
        except Exception as e:
            logger.error(f"❌ Session error: {e}")
        finally:
            logger.info("👋 Session ended")
    except Exception as e:
        logger.error(f"❌ Avatar Session error: {e}")
        raise


if __name__ == "__main__":
    asyncio.run(main())
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
@modal.fastapi_endpoint(method="POST")
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
    run_agent.spawn(room, agent_id)
    
    return {"status": "started", "room": room, "agent_id": agent_id}

