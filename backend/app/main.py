import os
from typing import List, Dict, Any
import time, uuid

from fastapi import FastAPI, HTTPException
import logging
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv
from pathlib import Path
from openai import OpenAI

from .chunking import chunk_text
from .pinecone_client import (
    get_pinecone,
    ensure_index_exists,
    upsert_vectors,
    fetch_vectors,
    upsert_vector,
)


class InsertRequest(BaseModel):
    user_id: str
    avatar_id: str
    full_text: str
    source: str | None = None


class InsertResponse(BaseModel):
    namespace: str
    inserted: int
    index_name: str
    model: str


# Lade bevorzugt backend/.env; fallback: nächstes .env via find_dotenv()
env_path = Path(__file__).resolve().parents[1] / ".env"
if env_path.exists():
    load_dotenv(env_path, override=True)
else:
    load_dotenv(find_dotenv())

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
PINECONE_API_KEY = os.getenv("PINECONE_API_KEY")
PINECONE_INDEX = os.getenv("PINECONE_INDEX", "avatars-index")
PINECONE_CLOUD = os.getenv("PINECONE_CLOUD", "aws")
PINECONE_REGION = os.getenv("PINECONE_REGION", "us-east-1")

# Standard-Modelle (nur ändern, wenn explizit angewiesen)
GPT_MODEL = os.getenv("GPT_MODEL", "gpt-4o-mini")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIM = int(os.getenv("EMBEDDING_DIM", "1536"))

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY fehlt in .env")
if not PINECONE_API_KEY:
    raise RuntimeError("PINECONE_API_KEY fehlt in .env")

app = FastAPI(title="Avatar Memory API", version="0.1.0")
logger = logging.getLogger("uvicorn.error")
client = OpenAI(api_key=OPENAI_API_KEY)
pc = get_pinecone(PINECONE_API_KEY)


@app.on_event("startup")
def on_startup() -> None:
    ensure_index_exists(
        pc=pc,
        index_name=PINECONE_INDEX,
        dimension=EMBEDDING_DIM,
        metric="cosine",
        cloud=PINECONE_CLOUD,
        region=PINECONE_REGION,
    )


@app.post("/avatar/memory/insert", response_model=InsertResponse)
def insert_avatar_memory(payload: InsertRequest) -> InsertResponse:
    namespace = f"{payload.user_id}_{payload.avatar_id}"

    # Größere Chunks für kleine Inputs
    chunks = chunk_text(payload.full_text, target_tokens=1000, overlap=100)
    if not chunks:
        raise HTTPException(status_code=400, detail="full_text ist leer")

    texts: List[str] = [c["text"] for c in chunks]

    try:
        emb = client.embeddings.create(model=EMBEDDING_MODEL, input=texts)
    except Exception as e:
        logger.exception("Embedding-Fehler")
        raise HTTPException(status_code=500, detail=f"Embedding-Fehler: {e}")

    # Wenn nur 1 Chunk und es existiert bereits ein doc mit doc_id 'latest', dann append statt neuem Vektor
    try:
        if len(chunks) == 1:
            latest_id = f"{payload.avatar_id}-latest-0"
            fetched = fetch_vectors(pc, PINECONE_INDEX, namespace, [latest_id])
            existing = fetched.get("vectors", {}).get(latest_id)
            if existing and "metadata" in existing and "text" in existing["metadata"]:
                # Append Text und re-embed den kombinierten Text
                combined_text = (existing["metadata"]["text"] or "") + "\n\n" + chunks[0]["text"]
                emb2 = client.embeddings.create(model=EMBEDDING_MODEL, input=[combined_text])
                vec = {
                    "id": latest_id,
                    "values": emb2.data[0].embedding,
                    "metadata": {
                        **existing["metadata"],
                        "text": combined_text,
                        "updated_at": int(time.time()*1000),
                    },
                }
                upsert_vector(pc, PINECONE_INDEX, namespace, vec)
                return InsertResponse(namespace=namespace, inserted=1, index_name=PINECONE_INDEX, model=EMBEDDING_MODEL)

        # sonst normal: neuen doc anlegen
        vectors: List[Dict[str, Any]] = []
        doc_id = f"{int(time.time()*1000)}-{uuid.uuid4().hex[:6]}"
        created_at = int(time.time()*1000)
        for i, chunk in enumerate(chunks):
            vec = {
                "id": f"{payload.avatar_id}-{doc_id}-{chunk['index']}",
                "values": emb.data[i].embedding,
                "metadata": {
                    "user_id": payload.user_id,
                    "avatar_id": payload.avatar_id,
                    "chunk_index": chunk["index"],
                    "doc_id": doc_id,
                    "created_at": created_at,
                    "source": payload.source or "text",
                    "text": chunk["text"],
                },
            }
            vectors.append(vec)
        upsert_vectors(pc, PINECONE_INDEX, namespace, vectors)
    except Exception as e:
        logger.exception("Pinecone-Fehler")
        raise HTTPException(status_code=500, detail=f"Pinecone-Fehler: {e}")

    return InsertResponse(
        namespace=namespace,
        inserted=len(vectors),
        index_name=PINECONE_INDEX,
        model=EMBEDDING_MODEL,
    )


