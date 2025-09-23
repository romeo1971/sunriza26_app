import os
import urllib.parse
from typing import List, Dict, Any
import time, uuid

from fastapi import FastAPI, HTTPException, BackgroundTasks
import re
import logging
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv
from pathlib import Path
from openai import OpenAI
from google.cloud import texttospeech
import base64, requests, json, tempfile, subprocess, threading

# Firebase Admin SDK für Chat-Storage
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    
    # Firebase initialisieren (falls noch nicht geschehen)
    if not firebase_admin._apps:
        # Versuche Service Account Key zu finden
        service_account_paths = [
            Path(__file__).resolve().parents[1] / "service-account-key.json",
            Path(__file__).resolve().parents[2] / "service-account-key.json",
        ]
        for sa_path in service_account_paths:
            if sa_path.exists():
                cred = credentials.Certificate(str(sa_path))
                firebase_admin.initialize_app(cred)
                break
        else:
            # Fallback: Default credentials
            firebase_admin.initialize_app()
    
    db = firestore.client()
    FIREBASE_AVAILABLE = True
except Exception as e:
    logger = logging.getLogger("uvicorn.error")
    logger.warning(f"Firebase nicht verfügbar: {e}")
    db = None
    FIREBASE_AVAILABLE = False

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
    # Chunking-Parameter (optional, überschreiben Defaults)
    target_tokens: int | None = None
    overlap: int | None = None
    min_chunk_tokens: int | None = None


class InsertResponse(BaseModel):
    namespace: str
    inserted: int
    index_name: str
    model: str


# Lade bevorzugt backend/.env; fallback: nächstes .env via find_dotenv()
env_path = Path(__file__).resolve().parents[1] / ".env"
if env_path.exists():
    # Wichtig: Shell/Deploy-Variablen NICHT überschreiben
    load_dotenv(env_path, override=False)
else:
    load_dotenv(find_dotenv(), override=False)

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
client = OpenAI(api_key=OPENAI_API_KEY, timeout=20, max_retries=0)
pc = get_pinecone(PINECONE_API_KEY)


# Persistenter Debug-Recorder für die letzte Insert-Operation
_LAST_INSERT_PATH = (Path(__file__).resolve().parents[1] / "last_memory_insert.json")

def _record_last_insert(data: Dict[str, Any]) -> None:
    try:
        data["ts"] = int(time.time() * 1000)
        _LAST_INSERT_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    except Exception:
        pass


# Einfache Namespace-State-Verwaltung für Rolling-Summaries (lokal auf Filesystem)
def _ns_state_dir() -> Path:
    p = Path(__file__).resolve().parents[1] / "ns_state"
    try:
        p.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    return p


def _ns_state_path(namespace: str) -> Path:
    return _ns_state_dir() / f"{namespace}.json"


def _load_ns_state(namespace: str) -> Dict[str, Any]:
    try:
        p = _ns_state_path(namespace)
        if p.exists():
            return json.loads(p.read_text() or "{}") or {}
    except Exception:
        pass
    return {"recent_texts": [], "summary_seq": 0}


def _save_ns_state(namespace: str, state: Dict[str, Any]) -> None:
    try:
        _ns_state_path(namespace).write_text(json.dumps(state, ensure_ascii=False))
    except Exception:
        pass


def _maybe_rolling_summary(index_name: str, namespace: str, new_texts: list[str]) -> None:
    try:
        if os.getenv("ROLLING_SUMMARY_ENABLED", "1") != "1":
            return
        every_n = int(os.getenv("ROLLING_SUMMARY_EVERY_N", "10"))
        window_n = max(1, int(os.getenv("ROLLING_SUMMARY_WINDOW", str(every_n))))

        st = _load_ns_state(namespace)
        recent: list[str] = list(st.get("recent_texts", []))
        recent.extend([t for t in new_texts if isinstance(t, str) and t.strip()])
        # nur die letzten window_n Elemente halten
        if len(recent) > window_n:
            recent = recent[-window_n:]

        if len(recent) < every_n:
            st["recent_texts"] = recent
            _save_ns_state(namespace, st)
            return

        # Zusammenfassung erstellen
        prompt = (
            "Fasse die folgenden Einträge prägnant als Meta-Zusammenfassung zusammen. "
            "Strukturiere nach: Emotionen/Stimmung, Verhalten/Aktionen, Ereignisse/Auslöser, "
            "Physisch/Biologisch, Soziale Interaktionen. Konzentriere dich auf Muster und Tendenzen.\n\n"
        ) + "\n\n".join(f"- {t.strip()}" for t in recent if t.strip())

        comp = client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": "Du bist ein präziser Zusammenfasser. Antworte kurz und strukturiert."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.2,
            max_tokens=220,
        )
        summary = (comp.choices[0].message.content or "").strip()
        if not summary:
            # ohne Summary kein Eintrag
            st["recent_texts"] = recent
            _save_ns_state(namespace, st)
            return

        # Embedding für Meta-Chunk erzeugen
        emb_vecs, real_dim = _create_embeddings_with_timeout([summary], EMBEDDING_MODEL, timeout_sec=10)
        vec = {
            "id": f"meta-{int(time.time()*1000)}",
            "values": emb_vecs[0],
            "metadata": {
                "type": "meta_summary",
                "text": summary,
                "created_at": int(time.time()*1000),
                "window_size": len(recent),
                "source": "summary",
                "summary_seq": int(st.get("summary_seq", 0) or 0) + 1,
            },
        }
        upsert_vector(pc, index_name, namespace, vec)
        # State zurücksetzen/fortschreiben
        st["recent_texts"] = []
        st["summary_seq"] = int(st.get("summary_seq", 0) or 0) + 1
        _save_ns_state(namespace, st)
        _record_last_insert({"stage": "meta_summary_upsert", "namespace": namespace, "index": index_name, "window": len(recent)})
    except Exception as e:
        logger.warning(f"Rolling-Summary Fehler: {e}")


def _store_chat_message(user_id: str, avatar_id: str, sender: str, content: str) -> str:
    """Speichert Chat-Message in Firebase und gibt message_id zurück."""
    if not FIREBASE_AVAILABLE or not db:
        return f"msg-{int(time.time()*1000)}"
    
    try:
        chat_id = f"{user_id}_{avatar_id}"
        message_id = f"msg-{int(time.time()*1000)}-{uuid.uuid4().hex[:6]}"
        timestamp = int(time.time() * 1000)
        
        message_data = {
            "message_id": message_id,
            "sender": sender,
            "content": content,
            "timestamp": timestamp,
            "avatar_id": avatar_id,
            "user_id": user_id,
        }
        
        # Speichere in Firebase: avatarUserChats/{chat_id}/messages/{message_id}
        db.collection("avatarUserChats").document(chat_id).collection("messages").document(message_id).set(message_data)
        
        # Zusätzlich Chat-Metadata aktualisieren
        chat_metadata = {
            "user_id": user_id,
            "avatar_id": avatar_id,
            "last_message_timestamp": timestamp,
            "last_message_content": content[:100],  # Kurzer Preview
            "last_sender": sender,
        }
        db.collection("avatarUserChats").document(chat_id).set(chat_metadata, merge=True)
        
        return message_id
    except Exception as e:
        logger.warning(f"Firebase Chat-Storage Fehler: {e}")
        return f"msg-{int(time.time()*1000)}"


def _get_chat_history(user_id: str, avatar_id: str, limit: int = 50, before_timestamp: int | None = None) -> tuple[List[Dict[str, Any]], bool]:
    """Holt Chat-Verlauf aus Firebase."""
    if not FIREBASE_AVAILABLE or not db:
        return [], False
    
    try:
        chat_id = f"{user_id}_{avatar_id}"
        query = db.collection("avatarUserChats").document(chat_id).collection("messages").order_by("timestamp", direction=firestore.Query.DESCENDING).limit(limit + 1)
        
        if before_timestamp:
            query = query.where("timestamp", "<", before_timestamp)
        
        docs = query.get()
        messages = []
        
        for i, doc in enumerate(docs):
            if i >= limit:  # Extra doc für has_more Check
                break
            data = doc.to_dict()
            messages.append(data)
        
        has_more = len(docs) > limit
        return messages, has_more
    except Exception as e:
        logger.warning(f"Firebase Chat-History Fehler: {e}")
        return [], False


def _store_chat_in_pinecone(user_id: str, avatar_id: str, user_message: str, avatar_response: str) -> None:
    """Speichert Chat-Konversation in Pinecone für Psychogramm und semantische Suche."""
    try:
        # Kombiniere User-Message und Avatar-Response für Kontext
        conversation_text = f"User: {user_message}\nAvatar: {avatar_response}"
        
        # Erstelle Embedding für die Konversation
        embeddings_list, real_dim = _create_embeddings_with_timeout([conversation_text], EMBEDDING_MODEL, timeout_sec=10)
        
        namespace = f"{user_id}_{avatar_id}"
        index_name = _pinecone_index_for(user_id, avatar_id)
        
        # Index sicherstellen
        ensure_index_exists(
            pc=pc,
            index_name=index_name,
            dimension=real_dim,
            metric="cosine",
            cloud=PINECONE_CLOUD,
            region=PINECONE_REGION,
        )
        
        # Chat-Vektor erstellen
        chat_id = f"chat-{int(time.time()*1000)}"
        vec = {
            "id": chat_id,
            "values": embeddings_list[0],
            "metadata": {
                "user_id": user_id,
                "avatar_id": avatar_id,
                "type": "chat_conversation",
                "user_message": user_message,
                "avatar_response": avatar_response,
                "conversation_text": conversation_text,
                "created_at": int(time.time()*1000),
                "source": "chat",
            },
        }
        
        upsert_vector(pc, index_name, namespace, vec)
        logger.info(f"Chat stored in Pinecone: {chat_id}")
    except Exception as e:
        logger.warning(f"Pinecone Chat-Storage Fehler: {e}")


def _create_embeddings_with_timeout(texts: List[str], model: str, timeout_sec: int = 20) -> tuple[List[List[float]], int]:
    """Ruft Embeddings mit hartem Timeout ab. Liefert (Vectors, Dimension) oder wirft Exception/TimeoutError."""
    result: Dict[str, Any] = {}
    errors: list[Exception] = []

    def _worker() -> None:
        try:
            emb = client.embeddings.create(model=model, input=texts, timeout=timeout_sec)
            result["emb"] = emb
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    th = threading.Thread(target=_worker, daemon=True)
    th.start()
    th.join(timeout=timeout_sec + 5)
    if "emb" in result:
        emb = result["emb"]
        try:
            real_dim = len(emb.data[0].embedding)  # type: ignore[index]
        except Exception:  # noqa: BLE001
            real_dim = EMBEDDING_DIM
        vectors = [emb.data[i].embedding for i in range(len(texts))]  # type: ignore[index]
        return vectors, real_dim
    if errors:
        raise errors[0]
    raise TimeoutError("Embedding timeout")


def _fetch_vectors_with_timeout(index_name: str, namespace: str, ids: List[str], timeout_sec: int = 15) -> Dict[str, Any]:
    """Wrappt fetch_vectors mit hartem Timeout, um Hänger im SDK zu vermeiden."""
    result: Dict[str, Any] = {}
    errors: list[Exception] = []

    def _worker() -> None:
        try:
            res = fetch_vectors(pc, index_name, namespace, ids)
            result.update(res or {})
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    th = threading.Thread(target=_worker, daemon=True)
    th.start()
    th.join(timeout=timeout_sec)
    if result:
        return result
    if errors:
        raise errors[0]
    raise TimeoutError("Pinecone fetch timeout")


def _pinecone_index_for(user_id: str, avatar_id: str) -> str:
    mode = os.getenv("PINECONE_INDEX_MODE", "namespace").lower()
    base = os.getenv("PINECONE_INDEX", "avatars-index")
    if mode == "per_avatar":
        def _san(s: str) -> str:
            s = (s or "").lower()
            s = re.sub(r"[^a-z0-9-]", "-", s)
            return s
        # Begrenze Länge; Pinecone Indexnamen dürfen nicht zu lang sein
        name = f"{base}-{_san(user_id)[:24]}-{_san(avatar_id)[:24]}"
        return name[:45]
    return base


@app.on_event("startup")
def on_startup() -> None:
    # Bei namespace-Modus nur Basis-Index sicherstellen,
    # bei per_avatar wird dynamisch vor Inserts/Queries erzeugt
    mode = os.getenv("PINECONE_INDEX_MODE", "namespace").lower()
    logger.info(f"PINECONE mode='{mode}' base_index='{PINECONE_INDEX}' cloud='{PINECONE_CLOUD}' region='{PINECONE_REGION}'")
    if mode != "per_avatar":
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


def _process_memory_insert(payload: InsertRequest) -> InsertResponse:
    namespace = f"{payload.user_id}_{payload.avatar_id}"
    index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
    ctx: Dict[str, Any] = {
        "stage": "start",
        "index": index_name,
        "namespace": namespace,
        "user_id": payload.user_id,
        "avatar_id": payload.avatar_id,
        "text_len": len(payload.full_text or ""),
    }
    _record_last_insert({**ctx})

    # Chunking-Parameter anwenden (Client-Overrides erlauben)
    try:
        _tt = int(payload.target_tokens) if payload.target_tokens is not None else 1000
    except Exception:
        _tt = 1000
    try:
        _ov = int(payload.overlap) if payload.overlap is not None else 100
    except Exception:
        _ov = 100
    _min_override = None
    try:
        if payload.min_chunk_tokens is not None:
            _min_override = int(payload.min_chunk_tokens)
    except Exception:
        _min_override = None

    # Größere Chunks für kleine Inputs
    chunks = chunk_text(
        payload.full_text,
        target_tokens=_tt,
        overlap=_ov,
        min_chunk_tokens_override=_min_override,
    )
    ctx["chunks"] = len(chunks)
    if not chunks:
        _record_last_insert({**ctx, "stage": "chunks_empty"})
        raise HTTPException(status_code=400, detail="full_text ist leer")
    _record_last_insert({**ctx, "stage": "chunks_ready", "chunks": len(chunks)})

    texts: List[str] = [c["text"] for c in chunks]

    logger.info(
        f"MEMORY_INSERT start uid='{payload.user_id}' avatar='{payload.avatar_id}' index='{index_name}' namespace='{namespace}' chunks={len(chunks)} text_len={len(payload.full_text)}"
    )
    FAKE = os.getenv("EMBEDDINGS_FAKE", "0") == "1"
    embeddings_list: List[List[float]] = []
    try:
        _record_last_insert({**ctx, "stage": "embeddings_start", "chunks": len(chunks)})
        if FAKE:
            raise RuntimeError("FAKE embeddings enabled")
        embeddings_list, real_dim = _create_embeddings_with_timeout(texts, EMBEDDING_MODEL, timeout_sec=20)
        _record_last_insert({**ctx, "stage": "embeddings_ok", "dim": len(embeddings_list[0]) if embeddings_list else None, "chunks": len(chunks)})
    except Exception as e:
        # Fallback: Fake-Embeddings generieren, damit Upsert und Namespace sicher stattfinden
        logger.warning(f"Embedding fehlgeschlagen, fallback auf Fake-Embeddings: {e}")
        ctx["embedding_error"] = str(e)
        real_dim = EMBEDDING_DIM
        embeddings_list = [[0.001 * (i + 1)] * real_dim for i in range(len(chunks))]
        _record_last_insert({**ctx, "stage": "embeddings_fallback", "error": str(e), "chunks": len(chunks)})
    # Index sicherstellen (per_avatar)
    ensure_index_exists(
        pc=pc,
        index_name=index_name,
        dimension=real_dim,
        metric="cosine",
        cloud=PINECONE_CLOUD,
        region=PINECONE_REGION,
    )
    ctx["dim"] = real_dim
    logger.info(f"MEMORY_INSERT preparing index='{index_name}' dim={real_dim} namespace='{namespace}' chunks={len(chunks)}")
    _record_last_insert({**ctx, "stage": "index_ready"})

    # Skip latest-optimization completely to avoid fetch hangs
    _record_last_insert({**ctx, "stage": "skip_latest_optimization"})

    # Normal: neuen doc anlegen (file_url nur setzen, wenn vorhanden)
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

    storage_path = payload.file_path or _extract_storage_path(payload.file_url)
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
            delete_by_filter(pc=pc, index_name=index_name, namespace=namespace, flt=flt)
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
            "values": embeddings_list[i],
            "metadata": meta,
        }
        vectors.append(vec)
    
    try:
        upsert_vectors(pc, index_name, namespace, vectors)
        # Rolling-Summary versuchen
        try:
            _maybe_rolling_summary(index_name, namespace, texts)
        except Exception:
            pass
        logger.info(f"MEMORY_INSERT upsert batch index='{index_name}' namespace='{namespace}' inserted={len(vectors)}")
        _record_last_insert({**ctx, "stage": "upsert_batch", "inserted": len(vectors)})
        return InsertResponse(
            namespace=namespace,
            inserted=len(vectors),
            index_name=index_name,
            model=EMBEDDING_MODEL,
        )
    except Exception as e:
        logger.exception(f"MEMORY_INSERT upsert failed for index='{index_name}', falling back to base index '{PINECONE_INDEX}'")
        _record_last_insert({**ctx, "stage": "upsert_error", "error": str(e)})
        # Fallback: Basisindex verwenden
        ensure_index_exists(
            pc=pc,
            index_name=PINECONE_INDEX,
            dimension=EMBEDDING_DIM,
            metric="cosine",
            cloud=PINECONE_CLOUD,
            region=PINECONE_REGION,
        )
        upsert_vectors(pc, PINECONE_INDEX, namespace, vectors)
        try:
            _maybe_rolling_summary(PINECONE_INDEX, namespace, texts)
        except Exception:
            pass
        logger.info(f"MEMORY_INSERT upsert batch index='{PINECONE_INDEX}' namespace='{namespace}' inserted={len(vectors)} (fallback)")
        _record_last_insert({**ctx, "stage": "upsert_fallback", "inserted": len(vectors)})
        return InsertResponse(
            namespace=namespace,
            inserted=len(vectors),
            index_name=PINECONE_INDEX,
            model=EMBEDDING_MODEL,
        )


class DeleteByFileRequest(BaseModel):
    user_id: str
    avatar_id: str
    file_url: str | None = None
    file_name: str | None = None
    file_path: str | None = None


@app.post("/avatar/memory/delete/by-file")
def delete_by_file(payload: DeleteByFileRequest) -> Dict[str, Any]:
    namespace = f"{payload.user_id}_{payload.avatar_id}"
    index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
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
                index_name=index_name,
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
                    index_name=index_name,
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
    index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
    try:
        emb = client.embeddings.create(model=EMBEDDING_MODEL, input=[payload.query])
        vec = emb.data[0].embedding
        # Index sicherstellen (per_avatar)
        ensure_index_exists(
            pc=pc,
            index_name=index_name,
            dimension=EMBEDDING_DIM,
            metric="cosine",
            cloud=PINECONE_CLOUD,
            region=PINECONE_REGION,
        )
        index = pc.Index(index_name)
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
    chat_id: str | None = None  # Für Chat-Verlauf-Tracking

class ChatMessage(BaseModel):
    message_id: str
    sender: str  # "user" oder "avatar"
    content: str
    timestamp: int
    avatar_id: str
    user_id: str

class ChatHistoryRequest(BaseModel):
    user_id: str
    avatar_id: str
    limit: int = 50
    before_timestamp: int | None = None  # Für Paginierung

class ChatHistoryResponse(BaseModel):
    messages: List[ChatMessage]
    has_more: bool

class DebugUpsertRequest(BaseModel):
    user_id: str
    avatar_id: str
    text: str | None = None

class DebugEmbeddingRequest(BaseModel):
    text: str = "hello from debug"

class CreateVoiceFromAudioRequest(BaseModel):
    user_id: str
    avatar_id: str
    audio_urls: List[str]
    name: str | None = None
    voice_id: str | None = None  # Wenn gesetzt: bestehende Stimme updaten statt neu anlegen
    dialect: str | None = None   # z. B. "de-DE", "de-AT", "en-US"
    tempo: float | None = None   # z. B. 0.8 .. 1.2 (Meta-Label)
    stability: float | None = None
    similarity: float | None = None

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

        # Hinweis: Aufwändiges Namens-Cleanup jetzt asynchron (siehe unten)

        # Neue Stimme anlegen (Labels für Metadaten wie Dialekt/Tempo mitschicken)
        labels: dict[str, str] = {}
        if payload.dialect:
            labels["dialect"] = str(payload.dialect)
        if payload.tempo is not None:
            try:
                labels["tempo"] = f"{float(payload.tempo):.2f}"
            except Exception:
                labels["tempo"] = str(payload.tempo)
        if payload.stability is not None:
            try:
                labels["stability"] = f"{float(payload.stability):.2f}"
            except Exception:
                labels["stability"] = str(payload.stability)
        if payload.similarity is not None:
            try:
                labels["similarity"] = f"{float(payload.similarity):.2f}"
            except Exception:
                labels["similarity"] = str(payload.similarity)

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
        # Nach-Cleanup asynchron ausführen, um Latenz zu minimieren
        try:
            def _async_cleanup():
                try:
                    _cleanup_voices_by_names([name] + candidate_names, keep_id=voice_id)
                except Exception as _e:
                    logger.warning(f"Async Cleanup Fehler: {_e}")
            threading.Thread(target=_async_cleanup, daemon=True).start()
        except Exception as _e:
            logger.warning(f"Async Cleanup Start Fehler: {_e}")
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
    speed: float | None = None  # 0.5 .. 1.5
    dialect: str | None = None  # nur zur Durchreichung/Protokollierung


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
        # Marker-Support: [lachen], [lachen:kurz], [lachen:lang], [pause:700ms]
        import re as _re
        _marker_regex = _re.compile(r"\[(?P<tag>lachen|pause)(?::(?P<arg>[^\]]+))?\]", _re.IGNORECASE)

        def _sfx_dir() -> str:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            return os.path.normpath(os.path.join(base_dir, "..", "assets", "sfx"))

        def _sfx_path(tag: str, arg: str | None) -> str | None:
            tag = (tag or "").lower()
            arg = (arg or "").lower() if arg else None
            sdir = _sfx_dir()
            candidates: list[str] = []
            if tag == "lachen":
                if arg in ("kurz", "short"):
                    candidates += ["laugh_short.mp3", "laugh.mp3"]
                elif arg in ("lang", "long"):
                    candidates += ["laugh_long.mp3", "laugh.mp3"]
                else:
                    candidates += ["laugh_short.mp3", "laugh.mp3"]
            for name in candidates:
                p = os.path.join(sdir, name)
                if os.path.isfile(p):
                    return p
            return None

        def _make_silence_ms(ms: int) -> str | None:
            try:
                dur = max(1, int(ms)) / 1000.0
                out_fd = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
                out_fd.close()
                out_path = out_fd.name
                cmd = [
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                    "-t", f"{dur}",
                    "-q:a", "9", "-acodec", "libmp3lame",
                    out_path,
                ]
                subprocess.run(cmd, check=True)
                return out_path
            except Exception:
                return None

        def _tts_text_to_temp_mp3(text_segment: str) -> str:
            rr = requests.post(
                f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
                headers={
                    "xi-api-key": key,
                    "Content-Type": "application/json",
                    "Accept": "audio/mpeg",
                },
                json={
                    "text": text_segment,
                    "model_id": model,
                    "voice_settings": {"stability": stability, "similarity_boost": similarity},
                },
                timeout=30,
            )
            rr.raise_for_status()
            fd = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
            fd.write(rr.content)
            fd.flush()
            fd.close()
            return fd.name

        text_input = req.text or ""
        if _marker_regex.search(text_input):
            segments: list[dict] = []
            last = 0
            for m in _marker_regex.finditer(text_input):
                start, end = m.span()
                if start > last:
                    seg_text = text_input[last:start].strip()
                    if seg_text:
                        segments.append({"type": "text", "value": seg_text})
                tag = m.group("tag")
                arg = m.group("arg")
                if tag and tag.lower() == "lachen":
                    segments.append({"type": "sfx", "value": _sfx_path(tag, arg)})
                elif tag and tag.lower() == "pause":
                    ms = 500
                    if arg:
                        ms_str = str(arg).lower().replace("ms", "").strip()
                        try:
                            ms = max(1, int(float(ms_str)))
                        except Exception:
                            pass
                    segments.append({"type": "silence", "ms": ms})
                last = end
            if last < len(text_input):
                tail = text_input[last:].strip()
                if tail:
                    segments.append({"type": "text", "value": tail})

            part_files: list[str] = []
            try:
                for seg in segments:
                    st = seg.get("type")
                    if st == "text":
                        part_files.append(_tts_text_to_temp_mp3(seg["value"]))
                    elif st == "sfx":
                        p = seg.get("value")
                        if isinstance(p, str) and os.path.isfile(p):
                            part_files.append(p)
                        else:
                            sp = _make_silence_ms(300)
                            if sp:
                                part_files.append(sp)
                    elif st == "silence":
                        ms = int(seg.get("ms") or 500)
                        sp = _make_silence_ms(ms)
                        if sp:
                            part_files.append(sp)

                if part_files:
                    out_fd = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
                    out_fd.close()
                    out_path = out_fd.name
                    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
                    for p in part_files:
                        cmd += ["-i", p]
                    n = len(part_files)
                    concat_filter = "".join([f"[{i}:a]" for i in range(n)]) + f"concat=n={n}:v=0:a=1"
                    cmd += ["-filter_complex", concat_filter, out_path]
                    subprocess.run(cmd, check=True)

                    import base64 as _b64
                    with open(out_path, "rb") as f:
                        audio_bytes2 = f.read()
                    return {"audio_b64": _b64.b64encode(audio_bytes2).decode("utf-8")}
            except Exception:
                pass

        # Standardfluss
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
        audio_bytes = r.content

        # Optional: Sprechtempo per ffmpeg ändern (client sendet speed 0.5..1.5)
        try:
            if req.speed is not None and abs(float(req.speed) - 1.0) > 1e-6:
                sp = max(0.5, min(2.0, float(req.speed)))
                with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as _in:
                    _in.write(audio_bytes)
                    _in.flush()
                    in_path = _in.name
                out_fd = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
                out_fd.close()
                out_path = out_fd.name
                # ffmpeg atempo unterstützt 0.5..2.0 pro Filter. Unser UI nutzt 0.5..1.5 → ein Filter reicht.
                cmd = [
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", in_path,
                    "-filter:a", f"atempo={sp:.2f}",
                    out_path,
                ]
                subprocess.run(cmd, check=True)
                with open(out_path, "rb") as f:
                    audio_bytes = f.read()
                try:
                    import os as _os
                    _os.remove(in_path)
                    _os.remove(out_path)
                except Exception:
                    pass
        except Exception:
            # Fallback: Original-Audio wenn ffmpeg fehlt/fehlschlägt
            pass

        # MP3-Bytes zurückgeben
        import base64 as _b64
        return {"audio_b64": _b64.b64encode(audio_bytes).decode("utf-8")}
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

        # Chat-Storage: Speichere User-Message und Avatar-Response
        try:
            # Speichere User-Message in Firebase
            user_msg_id = _store_chat_message(payload.user_id, payload.avatar_id, "user", payload.message)
            
            # Speichere Avatar-Response in Firebase
            avatar_msg_id = _store_chat_message(payload.user_id, payload.avatar_id, "avatar", answer)
            
            # Optional: Chat in Pinecone (Default AUS)
            if os.getenv("STORE_CHAT_IN_PINECONE", "0") == "1":
                _store_chat_in_pinecone(payload.user_id, payload.avatar_id, payload.message, answer)
            
            chat_id = f"{payload.user_id}_{payload.avatar_id}"
        except Exception as e:
            logger.warning(f"Chat-Storage Fehler: {e}")
            chat_id = None

        return ChatResponse(answer=answer, used_context=context_items, tts_audio_b64=tts_b64, chat_id=chat_id)
    except Exception as e:
        logger.exception("Chat-Fehler")
        raise HTTPException(status_code=500, detail=f"Chat-Fehler: {e}")

    

@app.post("/avatar/chat/history", response_model=ChatHistoryResponse)
def get_chat_history(payload: ChatHistoryRequest) -> ChatHistoryResponse:
    """Holt Chat-Verlauf für 'Ältere Nachrichten anzeigen' Button."""
    try:
        message_dicts, has_more = _get_chat_history(
            payload.user_id, 
            payload.avatar_id, 
            payload.limit, 
            payload.before_timestamp
        )
        messages = [ChatMessage(**msg) for msg in message_dicts]
        return ChatHistoryResponse(messages=messages, has_more=has_more)
    except Exception as e:
        logger.exception("Chat-History Fehler")
        raise HTTPException(status_code=500, detail=f"Chat-History Fehler: {e}")


@app.post("/avatar/memory/insert", response_model=InsertResponse)
def insert_avatar_memory(payload: InsertRequest) -> InsertResponse:
    """Synchroner Insert mit komplexer Chunk-Logik für Avatar-BRAIN-System."""
    logger.info("MEMORY_INSERT running synchronously")
    return _process_memory_insert(payload)


@app.post("/debug/upsert", response_model=InsertResponse)
def debug_upsert(payload: DebugUpsertRequest) -> InsertResponse:
    """Debug: Upsert ohne OpenAI – erzwingt Index/Namespace und legt 1 Dummy-Vector an."""
    namespace = f"{payload.user_id}_{payload.avatar_id}"
    index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
    # Index sicherstellen
    ensure_index_exists(
        pc=pc,
        index_name=index_name,
        dimension=EMBEDDING_DIM,
        metric="cosine",
        cloud=PINECONE_CLOUD,
        region=PINECONE_REGION,
    )
    vec = {
        "id": f"{payload.avatar_id}-debug-{int(time.time()*1000)}",
        "values": [0.001] * EMBEDDING_DIM,
        "metadata": {
            "user_id": payload.user_id,
            "avatar_id": payload.avatar_id,
            "source": "debug",
            "text": (payload.text or "debug"),
            "created_at": int(time.time()*1000),
        },
    }
    upsert_vector(pc, index_name, namespace, vec)
    logger.info(f"DEBUG_UPSERT index='{index_name}' namespace='{namespace}' id='{vec['id']}'")
    return InsertResponse(namespace=namespace, inserted=1, index_name=index_name, model=EMBEDDING_MODEL)


@app.post("/debug/embedding")
def debug_embedding(req: DebugEmbeddingRequest) -> Dict[str, Any]:
    """Testet OpenAI Embeddings direkt und liefert Dimension & Dauer zurück."""
    try:
        t0 = time.time()
        emb = client.embeddings.create(model=EMBEDDING_MODEL, input=[req.text], timeout=20)
        vec = emb.data[0].embedding  # type: ignore[index]
        ms = int((time.time() - t0) * 1000)
        return {"ok": True, "dim": len(vec), "ms": ms, "model": EMBEDDING_MODEL}
    except Exception as e:
        logger.exception("Debug-Embedding-Fehler")
        return {"ok": False, "error": str(e)}

