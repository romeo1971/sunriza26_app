import os
from typing import List, Dict, Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv
from openai import OpenAI

from .chunking import chunk_text
from .pinecone_client import get_pinecone, ensure_index_exists, upsert_vectors


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


load_dotenv(find_dotenv())

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
PINECONE_API_KEY = os.getenv("PINECONE_API_KEY")
PINECONE_INDEX = os.getenv("PINECONE_INDEX", "avatars-index")
PINECONE_CLOUD = os.getenv("PINECONE_CLOUD", "aws")
PINECONE_REGION = os.getenv("PINECONE_REGION", "us-east-1")

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIM = int(os.getenv("EMBEDDING_DIM", "1536"))

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY fehlt in .env")
if not PINECONE_API_KEY:
    raise RuntimeError("PINECONE_API_KEY fehlt in .env")

app = FastAPI(title="Avatar Memory API", version="0.1.0")
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

    chunks = chunk_text(payload.full_text, target_tokens=900, overlap=100)
    if not chunks:
        raise HTTPException(status_code=400, detail="full_text ist leer")

    texts: List[str] = [c["text"] for c in chunks]

    try:
        emb = client.embeddings.create(model=EMBEDDING_MODEL, input=texts)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding-Fehler: {e}")

    vectors: List[Dict[str, Any]] = []
    for i, chunk in enumerate(chunks):
        vec = {
            "id": f"{payload.avatar_id}-{chunk['index']}",
            "values": emb.data[i].embedding,
            "metadata": {
                "user_id": payload.user_id,
                "avatar_id": payload.avatar_id,
                "chunk_index": chunk["index"],
                "source": payload.source or "text",
                "text": chunk["text"],
            },
        }
        vectors.append(vec)

    upsert_vectors(
        pc=pc,
        index_name=PINECONE_INDEX,
        namespace=namespace,
        vectors=vectors,
    )

    return InsertResponse(
        namespace=namespace,
        inserted=len(vectors),
        index_name=PINECONE_INDEX,
        model=EMBEDDING_MODEL,
    )


