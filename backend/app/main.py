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
import base64, requests, json

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


@app.get("/health")
def health() -> Dict[str, Any]:
    return {"status": "healthy", "service": "memory-backend"}


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
    dialect: str | None = None   # z. B. "de-DE", "de-AT", "en-US"
    tempo: float | None = None   # z. B. 0.8 .. 1.2 (Meta-Label)

class CreateVoiceFromAudioResponse(BaseModel):
    voice_id: str
    name: str

@app.post("/avatar/voice/create", response_model=CreateVoiceFromAudioResponse)
def create_eleven_voice(payload: CreateVoiceFromAudioRequest) -> CreateVoiceFromAudioResponse:
    key = os.getenv("ELEVENLABS_API_KEY")
    if not key:
        raise HTTPException(status_code=400, detail="ELEVENLABS_API_KEY fehlt")

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

        # Hilfsfunktionen für robustes Löschen
        def _safe_delete_voice(vid: str) -> bool:
            try:
                dr = requests.delete(
                    f"https://api.elevenlabs.io/v1/voices/{vid}",
                    headers=headers,
                    timeout=30,
                )
                # ElevenLabs kann 204 No Content zurückgeben → akzeptiere jedes 2xx
                if 200 <= dr.status_code < 300:
                    logger.info(f"ElevenLabs Stimme gelöscht: {vid} ({dr.status_code})")
                    return True
                logger.warning(f"Delete fehlgeschlagen {vid}: {dr.status_code} {dr.text}")
                return False
            except Exception as _e:
                logger.warning(f"Delete Exception {vid}: {_e}")
                return False

        def _cleanup_voices_by_name(vname: str, keep_id: str | None = None) -> int:
            try:
                gr = requests.get(
                    "https://api.elevenlabs.io/v1/voices",
                    headers=headers,
                    timeout=30,
                )
                gr.raise_for_status()
                data = gr.json() or {}
                voices = data.get("voices", []) or []
                deleted = 0
                for v in voices:
                    vid = (v or {}).get("voice_id")
                    nm = (v or {}).get("name")
                    if not vid or not nm:
                        continue
                    # Ziel: alle Stimmen mit gleichem Namen oder Präfix entfernen, außer optional keep_id
                    if (nm == vname or nm.startswith(vname)) and (keep_id is None or vid != keep_id):
                        if _safe_delete_voice(vid):
                            deleted += 1
                return deleted
            except Exception as _e:
                logger.warning(f"Cleanup by name Fehler: {_e}")
                return 0

        def _cleanup_voices_by_names(vnames: list[str], keep_id: str | None = None) -> int:
            total = 0
            seen: set[str] = set()
            for n in vnames:
                if not n or n in seen:
                    continue
                seen.add(n)
                total += _cleanup_voices_by_name(n, keep_id=keep_id)
            return total

        # Namen vorbereiten (kanonisch + evtl. Displayname)
        canonical_name = f"avatar_{payload.avatar_id}"
        candidate_names = list({canonical_name, voice_name})

        # Alte Stimme löschen, falls vorhanden
        logger.info(f"Voice ID zum Löschen: '{payload.voice_id}'")
        if payload.voice_id and payload.voice_id.strip() and payload.voice_id != "__CLONE__":
            _safe_delete_voice(payload.voice_id.strip())
        else:
            logger.info("Keine alte Stimme zum Löschen gefunden")

        # Zusätzlich: Duplikate mit (kanonischem oder Display-)Namen entfernen (Sicherheitsnetz)
        dup_cleaned = _cleanup_voices_by_names(candidate_names, keep_id=None)
        if dup_cleaned:
            logger.info(f"Zusätzliche Duplikate gelöscht: {dup_cleaned}")

        # Neue Stimme anlegen (Labels für Metadaten wie Dialekt/Tempo mitschicken)
        labels: dict[str, str] = {}
        if payload.dialect:
            labels["dialect"] = str(payload.dialect)
        if payload.tempo is not None:
            try:
                labels["tempo"] = f"{float(payload.tempo):.2f}"
            except Exception:
                labels["tempo"] = str(payload.tempo)

        data = {"name": canonical_name}
        if labels:
            # ElevenLabs akzeptiert labels als JSON-String im multipart Feld "labels"
            data["labels"] = json.dumps(labels)
        r = requests.post(
            "https://api.elevenlabs.io/v1/voices/add",
            headers={**headers, "Accept": "application/json"},
            data=data,
            files=files,
            timeout=120,
        )
        r.raise_for_status()
        res = r.json()
        voice_id = res.get("voice_id") or res.get("id")
        name = res.get("name") or canonical_name
        if not voice_id:
            raise HTTPException(status_code=500, detail="ElevenLabs: voice_id fehlt in Antwort")
        # Post‑Cleanup: sicherstellen, dass keine weiteren Stimmen mit gleichem Namen übrig bleiben
        try:
            import time as _t

            def _list_voice_ids_for_names(vnames: list[str]) -> list[dict]:
                try:
                    gr = requests.get(
                        "https://api.elevenlabs.io/v1/voices",
                        headers=headers,
                        timeout=30,
                    )
                    gr.raise_for_status()
                    data = gr.json() or {}
                    voices = data.get("voices", []) or []
                    res = []
                    for v in voices:
                        vid = (v or {}).get("voice_id")
                        nm = (v or {}).get("name")
                        if not vid or not nm:
                            continue
                        for n in vnames:
                            if not n:
                                continue
                            if nm == n or nm.startswith(n):
                                res.append({"voice_id": vid, "name": nm})
                                break
                    return res
                except Exception:
                    return []

            # Bis zu 3 Versuche: Liste → lösche alles außer neuer ID
            attempts = 3
            for i in range(attempts):
                matches = _list_voice_ids_for_names([name] + candidate_names)
                to_delete = [m for m in matches if m.get("voice_id") != voice_id]
                if not to_delete:
                    break
                removed = 0
                for m in to_delete:
                    if _safe_delete_voice(m["voice_id"]):
                        removed += 1
                logger.info(f"Nach-Cleanup Pass {i+1}: entfernt={removed}, verbleibend={len(to_delete)-removed}")
                if removed == 0:
                    break
                _t.sleep(0.6)
        except Exception as _e:
            logger.warning(f"Nach-Cleanup Fehler: {_e}")
        return CreateVoiceFromAudioResponse(voice_id=voice_id, name=name)
    except requests.HTTPError as e:
        logger.exception("ElevenLabs Voice Create HTTPError")
        raise HTTPException(status_code=e.response.status_code, detail=f"ElevenLabs: {e.response.text}")
    except Exception as e:
        logger.exception("ElevenLabs Voice Create Fehler")
        raise HTTPException(status_code=500, detail=f"ElevenLabs Voice Create Fehler: {e}")


class TTSRequest(BaseModel):
    text: str
    voice_id: str | None = None
    model_id: str | None = None
    stability: float | None = None
    similarity: float | None = None


@app.post("/avatar/tts")
def tts_endpoint(req: TTSRequest):
    key = os.getenv("ELEVENLABS_API_KEY")
    if not key:
        raise HTTPException(status_code=400, detail="ELEVENLABS_API_KEY fehlt")
    try:
        vid = (req.voice_id or os.getenv("ELEVEN_VOICE_ID") or "21m00Tcm4TlvDq8ikWAM").strip()
        model = (req.model_id or os.getenv("ELEVEN_TTS_MODEL") or "eleven_multilingual_v2").strip()
        stability = float(req.stability) if req.stability is not None else float(os.getenv("ELEVEN_STABILITY", "0.5"))
        similarity = float(req.similarity) if req.similarity is not None else float(os.getenv("ELEVEN_SIMILARITY", "0.75"))
        r = requests.post(
            f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
            headers={
                "xi-api-key": key,
                "Content-Type": "application/json",
                "Accept": "audio/mpeg",
            },
            json={
                "text": req.text,
                "model_id": model,
                "voice_settings": {"stability": stability, "similarity_boost": similarity},
            },
            timeout=30,
        )
        r.raise_for_status()
        # MP3-Bytes direkt zurückgeben
        import base64 as _b64
        return {"audio_b64": _b64.b64encode(r.content).decode("utf-8")}
    except requests.HTTPError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"TTS Fehler: {e}")

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
        eleven_key = os.getenv("ELEVENLABS_API_KEY")
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


