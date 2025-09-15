import os
import urllib.parse
from typing import List, Dict, Any
import time, uuid

from fastapi import FastAPI, HTTPException
import re
import logging
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv
from pathlib import Path
from openai import OpenAI
from google.cloud import texttospeech
import base64, requests

from .chunking import chunk_text
from .pinecone_client import (
    get_pinecone,
    ensure_index_exists,
    upsert_vectors,
    fetch_vectors,
    upsert_vector,
    delete_by_filter,
)


class InsertRequest(BaseModel):
    user_id: str
    avatar_id: str
    full_text: str
    source: str | None = None
    file_url: str | None = None
    file_name: str | None = None
    file_path: str | None = None


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
GPT_SYSTEM_PROMPT = os.getenv(
    "GPT_SYSTEM_PROMPT",
    (
        "Du bist der Avatar und sprichst strikt in der Ich-Form; den Nutzer sprichst du mit 'du' an. "
        "Regeln: "
        "1) Erkenne und korrigiere Tippfehler automatisch, ohne die Bedeutung zu ändern. "
        "2) Nutze bereitgestellten Kontext (Pinecone/Avatar-Wissen) nur, wenn er eindeutig zur Frage passt. Wenn nicht, ignoriere ihn. "
        "3) Wenn Kontext fehlt oder nicht reicht, antworte mit deinem allgemeinen Wissen – ohne zu erwähnen, ob/welcher Kontext genutzt wurde. "
        "4) Keine Meta-Sätze wie 'Ich habe keine spezifischen Informationen ...' oder Hinweise auf Datenbanken/Kontextquellen. "
        "5) Antworte flüssig und natürlich in EINEM kurzen Satz (max. 1–2 Sätze). "
        "6) Bei sehr allgemeinen Eingaben (nur Stichwort), stelle genau EINE kurze, smarte Rückfrage oder biete 1–2 naheliegende Optionen an. "
        "7) Antworte in der Sprache der Nutzerfrage (Spiegeln). Wenn unklar, antworte auf Deutsch."
    ),
)

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

    # Wenn Freitext (kein file_url) und nur 1 Chunk: in 'latest' anhängen statt neuen Vector zu erzeugen
    try:
        if payload.file_url is None and len(chunks) == 1:
            latest_id = f"{payload.avatar_id}-latest-0"
            fetched = fetch_vectors(pc, PINECONE_INDEX, namespace, [latest_id])
            existing = fetched.get("vectors", {}).get(latest_id)
            if existing and "metadata" in existing and "text" in existing["metadata"]:
                # Append Text und re-embed den kombinierten Text
                combined_text = (existing["metadata"]["text"] or "") + "\n\n" + chunks[0]["text"]
                emb2 = client.embeddings.create(model=EMBEDDING_MODEL, input=[combined_text])
                # Vor dem Upsert Metadaten von None-Werten bereinigen
                cleaned_meta = {k: v for k, v in {**existing["metadata"],
                                                  "text": combined_text,
                                                  "updated_at": int(time.time()*1000),
                                                  "source": payload.source or existing["metadata"].get("source") or "text",
                                                  }.items() if v is not None}
                vec = {
                    "id": latest_id,
                    "values": emb2.data[0].embedding,
                    "metadata": cleaned_meta,
                }
                upsert_vector(pc, PINECONE_INDEX, namespace, vec)
                return InsertResponse(namespace=namespace, inserted=1, index_name=PINECONE_INDEX, model=EMBEDDING_MODEL)

        # sonst normal: neuen doc anlegen (file_url nur setzen, wenn vorhanden)
        vectors: List[Dict[str, Any]] = []
        doc_id = f"{int(time.time()*1000)}-{uuid.uuid4().hex[:6]}"
        created_at = int(time.time()*1000)
        def _extract_storage_path(url: str | None) -> str | None:
            if not url:
                return None
            try:
                # Firebase download URLs enthalten /o/<ENCODED_PATH>?...
                parts = urllib.parse.urlparse(url)
                if not parts.path:
                    return None
                # Suche nach '/o/' und nehme den Teil danach bis zum '?'
                path = parts.path
                if "/o/" in path:
                    enc = path.split("/o/", 1)[1]
                else:
                    enc = path.lstrip("/")
                # Falls Query leer ist, ist enc bereits der ganze Pfad
                enc = enc if enc else ""
                # URL-decoden und %2F -> '/'
                decoded = urllib.parse.unquote(enc)
                # Sicherheitsabschneidung: alles vor '?' entfernen (falls doch enthalten)
                decoded = decoded.split('?', 1)[0]
                return decoded
            except Exception:
                return None

        storage_path = payload.file_path or _extract_storage_path(payload.file_url)
        def _extract_file_name(url: str | None) -> str | None:
            if not url:
                return None
            try:
                fpath = _extract_storage_path(url)
                if not fpath:
                    return None
                # letzter Pfadteil
                base = fpath.rstrip('/').split('/')[-1]
                return base or None
            except Exception:
                return None

        file_name = payload.file_name or _extract_file_name(payload.file_url)

        # Falls ein stabiler Datei-Bezug vorhanden ist (z. B. profile.txt):
        # Alte Chunks zu dieser Datei vor dem Insert entfernen (Update-Semantik)
        if storage_path or file_name:
            try:
                ors = []
                if storage_path:
                    ors.append({"file_path": {"$eq": storage_path}})
                if file_name:
                    ors.append({"file_name": {"$eq": file_name}})
                flt = ors[0] if len(ors) == 1 else {"$or": ors}
                delete_by_filter(pc=pc, index_name=PINECONE_INDEX, namespace=namespace, flt=flt)
            except Exception:
                pass

        for i, chunk in enumerate(chunks):
            meta = {
                "user_id": payload.user_id,
                "avatar_id": payload.avatar_id,
                "chunk_index": chunk["index"],
                "doc_id": doc_id,
                "created_at": created_at,
                "source": (payload.source or ("file_upload" if payload.file_url else "text")),
                # file_url nur setzen, wenn nicht None
                "file_url": payload.file_url,
                # stabiler Storage-Pfad (z. B. avatars/<uid>/<avatarId>/texts/..)
                "file_path": storage_path,
                # Dateiname für einfaches Filtern
                "file_name": file_name,
                "text": chunk["text"],
            }
            # None-Werte aus Metadaten entfernen (Pinecone erlaubt kein null)
            meta = {k: v for k, v in meta.items() if v is not None}
            vec = {
                "id": f"{payload.avatar_id}-{doc_id}-{chunk['index']}",
                "values": emb.data[i].embedding,
                "metadata": meta,
            }
            vectors.append(vec)
        upsert_vectors(pc, PINECONE_INDEX, namespace, vectors)
        return InsertResponse(
            namespace=namespace,
            inserted=len(vectors),
            index_name=PINECONE_INDEX,
            model=EMBEDDING_MODEL,
        )
    except Exception as e:
        logger.exception("Pinecone-Fehler")
        raise HTTPException(status_code=500, detail=f"Pinecone-Fehler: {e}")


class DeleteByFileRequest(BaseModel):
    user_id: str
    avatar_id: str
    file_url: str | None = None
    file_name: str | None = None
    file_path: str | None = None


@app.post("/avatar/memory/delete/by-file")
def delete_by_file(payload: DeleteByFileRequest) -> Dict[str, Any]:
    namespace = f"{payload.user_id}_{payload.avatar_id}"
    try:
        # Robuster Filter: lösche per URL ODER stabilem Storage-Pfad
        def _extract_storage_path(url: str) -> str | None:
            try:
                parts = urllib.parse.urlparse(url)
                path = parts.path
                if not path:
                    return None
                if "/o/" in path:
                    enc = path.split("/o/", 1)[1]
                else:
                    enc = path.lstrip("/")
                decoded = urllib.parse.unquote(enc)
                decoded = decoded.split('?', 1)[0]
                return decoded
            except Exception:
                return None

        fpath = payload.file_path or _extract_storage_path(payload.file_url or "")
        flt = None
        ors = []
        if payload.file_url:
            ors.append({"file_url": {"$eq": payload.file_url}})
        if fpath:
            ors.append({"file_path": {"$eq": fpath}})
        if payload.file_name:
            ors.append({"file_name": {"$eq": payload.file_name}})
        if len(ors) == 1:
            flt = ors[0]
        elif len(ors) > 1:
            flt = {"$or": ors}

        if flt:
            delete_by_filter(
                pc=pc,
                index_name=PINECONE_INDEX,
                namespace=namespace,
                flt=flt,
            )
        # Zusatz: falls nur Dateiname bekannt, optionaler Cleanup über file_name
        try:
            fname = None
            # aus URL extrahieren, wenn möglich
            parts = urllib.parse.urlparse(payload.file_url)
            if parts.path:
                if "/o/" in parts.path:
                    enc = parts.path.split("/o/", 1)[1]
                else:
                    enc = parts.path.lstrip("/")
                decoded = urllib.parse.unquote(enc)
                decoded = decoded.split('?', 1)[0]
                fname = decoded.rstrip('/').split('/')[-1]
            if fname:
                delete_by_filter(
                    pc=pc,
                    index_name=PINECONE_INDEX,
                    namespace=namespace,
                    flt={"file_name": {"$eq": fname}},
                )
        except Exception:
            pass
        return {"deleted": True}
    except Exception as e:
        logger.exception("Pinecone-Delete-Fehler")
        raise HTTPException(status_code=500, detail=f"Pinecone-Delete-Fehler: {e}")


class QueryRequest(BaseModel):
    user_id: str
    avatar_id: str
    query: str
    top_k: int = 5


class QueryResponse(BaseModel):
    namespace: str
    results: List[Dict[str, Any]]


@app.post("/avatar/memory/query", response_model=QueryResponse)
def memory_query(payload: QueryRequest) -> QueryResponse:
    namespace = f"{payload.user_id}_{payload.avatar_id}"
    try:
        emb = client.embeddings.create(model=EMBEDDING_MODEL, input=[payload.query])
        vec = emb.data[0].embedding
        index = pc.Index(PINECONE_INDEX)
        res = index.query(
            vector=vec,
            top_k=payload.top_k,
            namespace=namespace,
            include_values=False,
            include_metadata=True,
        )
        # Pinecone SDK returns dict-like
        matches = res.get("matches", []) if isinstance(res, dict) else res.matches  # type: ignore
        results: List[Dict[str, Any]] = []
        for m in matches:
            if isinstance(m, dict):
                results.append({
                    "id": m.get("id"),
                    "score": m.get("score"),
                    "metadata": m.get("metadata"),
                })
            else:
                results.append({
                    "id": getattr(m, "id", None),
                    "score": getattr(m, "score", None),
                    "metadata": getattr(m, "metadata", None),
                })
        return QueryResponse(namespace=namespace, results=results)
    except Exception as e:
        logger.exception("Pinecone-Query-Fehler")
        raise HTTPException(status_code=500, detail=f"Pinecone-Query-Fehler: {e}")


class ChatRequest(BaseModel):
    user_id: str
    avatar_id: str
    message: str
    top_k: int = 5
    voice_id: str | None = None
    avatar_name: str | None = None


class ChatResponse(BaseModel):
    answer: str
    used_context: List[Dict[str, Any]]
    tts_audio_b64: str | None = None

class CreateVoiceFromAudioRequest(BaseModel):
    user_id: str
    avatar_id: str
    audio_urls: List[str]
    name: str | None = None
    voice_id: str | None = None  # Wenn gesetzt: bestehende Stimme updaten statt neu anlegen

class CreateVoiceFromAudioResponse(BaseModel):
    voice_id: str
    name: str

@app.post("/avatar/voice/create", response_model=CreateVoiceFromAudioResponse)
def create_eleven_voice(payload: CreateVoiceFromAudioRequest) -> CreateVoiceFromAudioResponse:
    key = os.getenv("ELEVEN_API_KEY")
    if not key:
        raise HTTPException(status_code=400, detail="ELEVEN_API_KEY fehlt")

    # Lade die Audios (max 3) herunter und sende an ElevenLabs API
    files = []
    try:
        for i, url in enumerate(payload.audio_urls[:3]):
            r = requests.get(url, timeout=60)
            r.raise_for_status()
            ctype = r.headers.get('content-type', 'application/octet-stream')
            ext = '.wav' if 'wav' in ctype else ('.m4a' if ('mp4' in ctype or 'm4a' in ctype) else '.mp3')
            files.append((f"files", (f"sample_{i}{ext}", r.content, ctype)))

        voice_name = payload.name or f"avatar_{payload.avatar_id}"
        headers = {"xi-api-key": key}

        if payload.voice_id and payload.voice_id.strip():
            # Bestehende Stimme bearbeiten (ersetzen)
            target_id = payload.voice_id.strip()
            data = {"name": voice_name}
            r = requests.post(
                f"https://api.elevenlabs.io/v1/voices/{target_id}/edit",
                headers=headers,
                data=data,
                files=files,
                timeout=120,
            )
            r.raise_for_status()
            res = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
            name = res.get("name") or voice_name
            return CreateVoiceFromAudioResponse(voice_id=target_id, name=name)
        else:
            # Neue Stimme anlegen
            data = {"name": voice_name}
            r = requests.post(
                "https://api.elevenlabs.io/v1/voices/add",
                headers=headers,
                data=data,
                files=files,
                timeout=120,
            )
            r.raise_for_status()
            res = r.json()
            voice_id = res.get("voice_id") or res.get("id")
            name = res.get("name") or voice_name
            if not voice_id:
                raise HTTPException(status_code=500, detail="ElevenLabs: voice_id fehlt in Antwort")
            return CreateVoiceFromAudioResponse(voice_id=voice_id, name=name)
    except requests.HTTPError as e:
        logger.exception("ElevenLabs Voice Create HTTPError")
        raise HTTPException(status_code=e.response.status_code, detail=f"ElevenLabs: {e.response.text}")
    except Exception as e:
        logger.exception("ElevenLabs Voice Create Fehler")
        raise HTTPException(status_code=500, detail=f"ElevenLabs Voice Create Fehler: {e}")


@app.post("/avatar/chat", response_model=ChatResponse)
def chat_with_avatar(payload: ChatRequest) -> ChatResponse:
    # Pre-Normalisierung: häufige Tippfehler korrigieren
    msg = payload.message
    msg = re.sub(r"\bdiesel jahr\b", "dieses Jahr", msg, flags=re.IGNORECASE)
    msg = re.sub(r"\bdieses jahr\b", "dieses Jahr", msg, flags=re.IGNORECASE)
    msg = re.sub(r"fussball", "Fußball", msg, flags=re.IGNORECASE)
    # häufige Tippfehler
    msg = re.sub(r"\bwet\s+ice\b", "wer ich", msg, flags=re.IGNORECASE)
    msg = re.sub(r"\bweisst\b", "weißt", msg, flags=re.IGNORECASE)
    msg = re.sub(r"\bweiss\b", "weiß", msg, flags=re.IGNORECASE)
    payload.message = msg
    # 1) RAG: relevante Schnipsel holen
    qres = memory_query(QueryRequest(
        user_id=payload.user_id,
        avatar_id=payload.avatar_id,
        query=payload.message,
        top_k=payload.top_k,
    ))
    context_items = qres.results
    context_texts = []
    for it in context_items:
        md = it.get("metadata") or {}
        t = md.get("text")
        if t:
            context_texts.append(f"- {t}")
    context_block = "\n".join(context_texts) if context_texts else ""

    # Heuristik: Allgemeine Wissensfrage nach "(Fußball-)Weltmeister" → Kontext ignorieren
    champion_q = re.search(r"weltmeister", msg, flags=re.IGNORECASE)
    if champion_q:
        context_block = ""

    # 2) Prompt bauen (kurz & menschlich)
    system = GPT_SYSTEM_PROMPT
    if payload.avatar_name:
        system = system + f" Dein Name ist {payload.avatar_name}."
    # Ohne Kontext: erlaube allgemeines Wissen statt “weiß ich nicht”
    if not context_block:
        system = (
            "Du bist der Avatar (Ich-Form, duzen). "
            "Korrigiere Tippfehler automatisch. "
            "Keine Meta-Hinweise zu Quellen/Kontext. "
            "Antworte kurz (1–2 Sätze) mit deinem allgemeinen Wissen. "
            "Bei sehr allgemeinem Prompt stelle genau EINE kurze Rückfrage. "
            "Antwortsprache = Sprache der Nutzerfrage; wenn unklar, Deutsch."
        )
    user_msg = payload.message
    if context_block:
        user_msg = (
            f"Kontext:\n{context_block}\n\nFrage: {payload.message}\n"
            "Nutze den obigen Kontext vorrangig. Wenn der Kontext die Antwort nicht eindeutig enthält, beantworte korrekt mit deinem allgemeinen Wissen."
        )
    # Spezifische Klärung für Weltmeister-Fragen: gib amtierenden Titelträger
    if champion_q:
        user_msg += "\nHinweis: Gemeint ist der aktuell amtierende Weltmeister (Herren, sofern nicht 'Frauen' erwähnt). Antworte knapp: Land + Jahr des Titels."

    # 3) OpenAI Chat
    try:
        comp = client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_msg},
            ],
            temperature=0.2,
            max_tokens=120,
        )
        answer = comp.choices[0].message.content.strip()  # type: ignore

        # TTS: bevorzugt ElevenLabs, sonst Google TTS
        tts_b64 = None
        eleven_key = os.getenv("ELEVEN_API_KEY")
        eleven_voice_id = payload.voice_id or os.getenv("ELEVEN_VOICE_ID")  # optional
        if eleven_key:
            try:
                vid = eleven_voice_id or "21m00Tcm4TlvDq8ikWAM"  # Standard‑Stimme
                r = requests.post(
                    f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
                    headers={
                        "xi-api-key": eleven_key,
                        "Content-Type": "application/json",
                        "Accept": "audio/mpeg",
                    },
                    json={
                        "text": answer,
                        "model_id": os.getenv("ELEVEN_TTS_MODEL", "eleven_multilingual_v2"),
                        "voice_settings": {
                            "stability": float(os.getenv("ELEVEN_STABILITY", "0.5")),
                            "similarity_boost": float(os.getenv("ELEVEN_SIMILARITY", "0.75")),
                        },
                    },
                    timeout=30,
                )
                r.raise_for_status()
                tts_b64 = base64.b64encode(r.content).decode("utf-8")
            except Exception:
                tts_b64 = None
        if not tts_b64:
            try:
                tts_client = texttospeech.TextToSpeechClient()
                synthesis_input = texttospeech.SynthesisInput(text=answer)
                voice = texttospeech.VoiceSelectionParams(
                    language_code=os.getenv("TTS_LANGUAGE", "de-DE"),
                    name=os.getenv("TTS_VOICE", "de-DE-Standard-A"),
                    ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL,
                )
                audio_config = texttospeech.AudioConfig(
                    audio_encoding=texttospeech.AudioEncoding.MP3,
                    speaking_rate=float(os.getenv("TTS_RATE", "1.0")),
                    pitch=float(os.getenv("TTS_PITCH", "0.0")),
                )
                tts_resp = tts_client.synthesize_speech(
                    input=synthesis_input, voice=voice, audio_config=audio_config
                )
                tts_b64 = base64.b64encode(tts_resp.audio_content).decode("utf-8")
            except Exception:
                tts_b64 = None

        return ChatResponse(answer=answer, used_context=context_items, tts_audio_b64=tts_b64)
    except Exception as e:
        logger.exception("Chat-Fehler")
        raise HTTPException(status_code=500, detail=f"Chat-Fehler: {e}")

    return InsertResponse(
        namespace=namespace,
        inserted=len(vectors),
        index_name=PINECONE_INDEX,
        model=EMBEDDING_MODEL,
    )


