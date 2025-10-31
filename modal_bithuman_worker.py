#!/usr/bin/env python3
"""
Modal.com - BitHuman LiveKit Worker (PROPER WAY)
================================================
Deploy: modal deploy modal_bithuman_worker.py
Serve: modal serve modal_bithuman_worker.py (for dev)

This creates a PERSISTENT worker that listens for LiveKit dispatch requests.
When a participant joins a room, LiveKit automatically dispatches a job to this worker.

NO manual room/agent_id needed - worker gets jobs from LiveKit automatically!
"""

import modal

# === MODAL IMAGE ===
image = (
    modal.Image.debian_slim()
    .apt_install("libgl1-mesa-glx", "libglib2.0-0", "libsm6", "libxext6", "libxrender1")
    .pip_install(
        # Core LiveKit Agent with plugins
        "livekit-agents[openai,bithuman,silero]>=1.2.16",
        "python-dotenv>=1.1.1",
        
        # OpenCV headless
        "opencv-python-headless==4.10.0.84",
        
        # Knowledge Base
        "pinecone>=5.0.0",
        "openai>=1.35.0",
        
        # Firebase
        "firebase-admin>=6.4.0",
        
        # Utils
        "aiohttp>=3.8.0",
        "fastapi>=0.115.0",  # ← FIX: Required for web endpoints!
    )
    .run_commands(
        "python -m pip uninstall -y opencv-python opencv-contrib-python pinecone-client || true",
        "pip install --no-cache-dir --force-reinstall opencv-python-headless==4.10.0.84",
        "pip install livekit-plugins-elevenlabs || echo 'ElevenLabs optional'",
        "echo 'REBUILD-V4: 2025-10-31-19-52-ABSOLUTE-FINAL'",  # ← Change to force rebuild
        "python3 --version",  # ← Extra line to bust cache
        gpu=None,
    )
)

app = modal.App("bithuman-worker-v4", image=image)  # ← Neuer Name = garantiert neuer Deploy

# === SECRETS ===
secrets = [
    modal.Secret.from_name("livekit-cloud"),      # LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
    modal.Secret.from_name("bithuman-api"),       # BITHUMAN_API_SECRET, BITHUMAN_API_URL
    modal.Secret.from_name("openai-api"),         # OPENAI_API_KEY
    modal.Secret.from_name("elevenlabs-api"),     # ELEVENLABS_API_KEY, ELEVEN_DEFAULT_VOICE_ID
    modal.Secret.from_name("pinecone-api"),       # PINECONE_API_KEY, PINECONE_INDEX_NAME
    modal.Secret.from_name("firebase-admin"),     # FIREBASE_CREDENTIALS
]


# === WORKER ENTRYPOINT ===
@app.function(
    image=image,
    secrets=secrets,
    timeout=3600,  # 60 min per job
    cpu=2.0,
    memory=4096,
    scaledown_window=300,  # 5 min idle → scale down
    max_containers=10,  # Handle multiple rooms
)
async def agent_worker(room_name: str, agent_id: str):
    """
    LiveKit Agent Worker - called by LiveKit dispatch
    
    Args:
        room_name: LiveKit room name (provided by dispatch)
        agent_id: BitHuman Agent ID (from Firebase/ENV)
    """
    import logging
    import os
    import asyncio
    from typing import Optional, Dict, Any
    
    from livekit import rtc
    from livekit.agents import Agent, AgentSession, RoomOutputOptions
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
        def __init__(self, pc_key: str, index_name: str, openai_key: str, namespace: str = None):
            self.namespace = namespace
            self.openai_client = OpenAI(api_key=openai_key)
            self.pc = Pinecone(api_key=pc_key)
            self.index = self.pc.Index(index_name)
        
        async def query(self, question: str, top_k: int = 5) -> Optional[str]:
            try:
                resp = await asyncio.to_thread(
                    self.openai_client.embeddings.create,
                    model="text-embedding-ada-002",
                    input=question
                )
                vec = resp.data[0].embedding
                
                params = {"vector": vec, "top_k": top_k, "include_metadata": True}
                if self.namespace:
                    params["namespace"] = self.namespace
                
                results = await asyncio.to_thread(self.index.query, **params)
                matches = [m for m in results.matches if m.score > 0.7]
                
                if not matches:
                    return None
                
                context = "\n\n".join([
                    f"[{m.metadata.get('source', 'Unknown')}]: {m.metadata.get('text', '')}"
                    for m in matches[:3]
                ])
                logger.info(f"✅ Pinecone: {len(matches)} matches")
                return context
            except Exception as e:
                logger.error(f"❌ Pinecone error: {e}")
                return None
    
    def get_config(agent_id: str) -> Dict[str, Any]:
        if not FIREBASE_AVAILABLE:
            raise RuntimeError("Firebase Admin SDK not available!")
        
        if not firebase_admin._apps:
            import json
            creds_json = os.getenv("FIREBASE_CREDENTIALS")
            if not creds_json:
                raise ValueError("FIREBASE_CREDENTIALS not set in Modal Secret!")
            
            # Parse und validate JSON
            creds_dict = json.loads(creds_json)
            if not isinstance(creds_dict, dict):
                raise ValueError("FIREBASE_CREDENTIALS must be a valid JSON object!")
            
            cred = credentials.Certificate(creds_dict)
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
        
        # Kein Avatar gefunden - das ist ein FEHLER!
        raise ValueError(f"No avatar found in Firestore for agent_id={agent_id}")
    
    # === MAIN LOGIC ===
    logger.info(f"🚀 Agent starting: room={room_name}, agent={agent_id}")
    
    # Connect to LiveKit
    lk_url = os.getenv("LIVEKIT_URL")
    lk_key = os.getenv("LIVEKIT_API_KEY")
    lk_secret = os.getenv("LIVEKIT_API_SECRET")
    
    if not all([lk_url, lk_key, lk_secret]):
        raise ValueError("LiveKit credentials missing!")
    
    # Generate token for agent
    from livekit import api
    token = api.AccessToken(lk_key, lk_secret)
    token.with_identity(f"agent-{agent_id}")
    token.with_name("BitHuman Agent")
    token.with_grants(api.VideoGrants(
        room_join=True,
        room=room_name,
    ))
    lk_token = token.to_jwt()
    
    # Connect room
    room = rtc.Room()
    await room.connect(lk_url, lk_token)
    logger.info(f"✅ Connected to room: {room_name}")
    
    # Wait for participant
    logger.info("⏳ Waiting for participant...")
    while len([p for p in room.remote_participants.values()]) == 0:
        await asyncio.sleep(0.5)
    logger.info("✅ Participant joined!")
    
    # Get config
    config = get_config(agent_id)
    voice_id = config.get('voice_id') or os.getenv("ELEVEN_DEFAULT_VOICE_ID")
    namespace = config.get('namespace')
    
    logger.info(f"🎤 Voice: {voice_id}, NS: {namespace}")
    
    # Knowledge Base
    kb = None
    if PINECONE_AVAILABLE and os.getenv("PINECONE_API_KEY"):
        kb = KnowledgeBase(
            os.getenv("PINECONE_API_KEY"),
            os.getenv("PINECONE_INDEX_NAME", "sunriza26-avatar-data"),
            os.getenv("OPENAI_API_KEY"),
            namespace
        )
        logger.info("✅ Knowledge Base initialized")
    
    # TTS
    if ELEVENLABS_AVAILABLE and voice_id:
        logger.info(f"🎵 ElevenLabs TTS: {voice_id}")
        tts = elevenlabs.TTS(voice_id=voice_id, api_key=os.getenv("ELEVENLABS_API_KEY"))
    else:
        logger.info("🎵 OpenAI TTS (fallback)")
        tts = openai.TTS(voice="coral")
    
    # LLM
    base_llm = openai.realtime.RealtimeModel(
        voice="coral",
        model="gpt-4o-mini-realtime-preview"
    )
    
    class KBLLM:
        def __init__(self, llm, kb):
            self.llm = llm
            self.kb = kb
        
        async def generate(self, prompt, **kwargs):
            ctx = await self.kb.query(prompt) if self.kb else None
            if ctx:
                prompt = f"Kontext:\n{ctx}\n\nFrage: {prompt}"
            return await self.llm.generate(prompt, **kwargs)
    
    llm = KBLLM(base_llm, kb) if kb else base_llm
    
    # Session
    session = AgentSession(llm=llm, vad=silero.VAD.load(), tts=tts)
    logger.info("✅ Agent Session created")
    
    # BitHuman Avatar - NO http_session needed! Modal provides it via context
    import aiohttp
    http_session = aiohttp.ClientSession()
    
    try:
        avatar = bithuman.AvatarSession(
            api_url=os.getenv("BITHUMAN_API_URL", "https://auth.api.bithuman.ai/v1/runtime-tokens/request"),
            api_secret=os.getenv("BITHUMAN_API_SECRET"),
            avatar_id=agent_id,
            http_session=http_session,  # ← Provide session explicitly
        )
        logger.info("✅ BitHuman Avatar Session created")
        
        # Start Avatar
        logger.info("🚀 Starting BitHuman Avatar...")
        await avatar.start(session, room=room)
        logger.info("🎥 BitHuman Avatar STARTED!")
        
        # Start Agent
        instructions = config.get('instructions') or f"Du bist {config.get('name', 'Avatar')}, ein hilfreicher Assistent."
        await session.start(
            agent=Agent(instructions=instructions),
            room=room,
            room_output_options=RoomOutputOptions(audio_enabled=False)
        )
        
        logger.info("✅ Agent running!")
        
        # Keep alive
        try:
            await room.wait_for_disconnect()
        except Exception as e:
            logger.error(f"❌ Session error: {e}")
    finally:
        await http_session.close()
        logger.info("👋 Agent finished")


# === WEBHOOK TO TRIGGER WORKER ===
@app.function(secrets=secrets)
@modal.fastapi_endpoint(method="POST")
def join(data: dict):
    """
    Trigger agent to join room
    
    POST /join
    Body: {"room": "room-name", "agent_id": "A96KSC8832"}
    """
    room = data.get("room", "").strip()
    agent_id = data.get("agent_id", "").strip()
    
    if not room or not agent_id:
        return {"status": "error", "message": "room and agent_id required"}
    
    print(f"🎬 Agent join: room={room}, agent={agent_id}")
    
    # Spawn worker
    agent_worker.spawn(room, agent_id)
    
    return {"status": "started", "room": room, "agent_id": agent_id}


@app.function()
@modal.fastapi_endpoint(method="GET")
def health():
    """Health check"""
    return {
        "status": "ok",
        "service": "bithuman-worker",
        "type": "Modal + LiveKit",
        "note": "Worker spawns on demand via /join endpoint"
    }


# check_secrets endpoint removed to save web endpoint limit
# @app.function(secrets=secrets)
# @modal.fastapi_endpoint(method="GET")
# def check_secrets():
#     """Debug: Check if secrets are loaded"""
#     import os
#     return {
#         "livekit_url": os.getenv("LIVEKIT_URL", "NOT SET")[:30] + "..." if os.getenv("LIVEKIT_URL") else "NOT SET",
#         "livekit_api_key": os.getenv("LIVEKIT_API_KEY", "NOT SET")[:10] + "..." if os.getenv("LIVEKIT_API_KEY") else "NOT SET",
#         "livekit_api_secret": "***" if os.getenv("LIVEKIT_API_SECRET") else "NOT SET",
#         "bithuman_api_secret": "***" if os.getenv("BITHUMAN_API_SECRET") else "NOT SET",
#         "openai_api_key": "***" if os.getenv("OPENAI_API_KEY") else "NOT SET",
#         "elevenlabs_api_key": "***" if os.getenv("ELEVENLABS_API_KEY") else "NOT SET",
#         "pinecone_api_key": "***" if os.getenv("PINECONE_API_KEY") else "NOT SET",
#         "firebase_credentials": "***" if os.getenv("FIREBASE_CREDENTIALS") else "NOT SET",
#     }
