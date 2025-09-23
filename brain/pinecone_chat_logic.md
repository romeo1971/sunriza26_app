# Pinecone Chat-Logik (Sunriza)

Dieses Dokument enthält die gesamte Pinecone-Logik, die im Chatfluss verwendet wird: Konfiguration/Init, Indexwahl, RAG-Query, optionales Speichern von Chat-Turns sowie die Pinecone-Client-Hilfsfunktionen.

Hinweis: Das Speichern der Chat-Konversation in Pinecone ist per Feature-Flag standardmäßig aus. Aktivieren mit:

```bash
STORE_CHAT_IN_PINECONE=1
```

## Konfiguration & Initialisierung (backend/app/main.py)

```python
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
```

## Indexwahl und Startup (backend/app/main.py)

```python
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
```

## RAG Query für Chat (backend/app/main.py)

```python
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
```

## Optional: Chat-Turns in Pinecone speichern (backend/app/main.py)

```python
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
```

### Nutzung im Chat (RAG + optionales Speichern) – Auszug (backend/app/main.py)

```python
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

# ... später nach der Antworterzeugung:

# Optional: Chat in Pinecone (Default AUS)
if os.getenv("STORE_CHAT_IN_PINECONE", "0") == "1":
    _store_chat_in_pinecone(payload.user_id, payload.avatar_id, payload.message, answer)
```

## Pinecone-Client-Hilfsfunktionen (backend/app/pinecone_client.py)

```python
from __future__ import annotations

from typing import List, Dict, Any

from pinecone import Pinecone, ServerlessSpec
import time


def get_pinecone(api_key: str) -> Pinecone:
    return Pinecone(api_key=api_key)


def ensure_index_exists(
    pc: Pinecone,
    index_name: str,
    dimension: int,
    metric: str,
    cloud: str,
    region: str,
) -> None:
    """Create index if missing (idempotent)."""
    existing_names = set()
    try:
        lst = pc.list_indexes()
        for it in lst:
            # Supports dict, object with .name, or plain string
            name = None
            if isinstance(it, str):
                name = it
            elif isinstance(it, dict):
                name = it.get("name")
            else:
                name = getattr(it, "name", None)
            if name:
                existing_names.add(name)
    except Exception:
        # Fallback: assume not existing, creation will be attempted
        existing_names = set()
    def _is_ready(desc: Any) -> bool:  # type: ignore[name-defined]
        try:
            if isinstance(desc, dict):
                status = desc.get("status")
                if isinstance(status, dict):
                    return bool(status.get("ready", True))
                # Keine Status-Info → als bereit behandeln
                return True
            status_obj = getattr(desc, "status", None)
            if status_obj is None:
                return True
            return bool(getattr(status_obj, "ready", True))
        except Exception:
            return True

    if index_name in existing_names:
        # ensure it's ready (max 60s)
        try:
            t0 = time.time()
            while True:
                desc = pc.describe_index(index_name)
                if _is_ready(desc):
                    break
                if time.time() - t0 > 60:
                    break
                time.sleep(1)
        except Exception:
            # best-effort readiness check
            pass
        return
    # Try requested spec first; on plan/region errors, auto-fallback to aws/us-east-1
    def _wait_ready(timeout_sec: int = 60) -> None:
        try:
            t0 = time.time()
            while True:
                desc = pc.describe_index(index_name)
                if _is_ready(desc):
                    return
                if time.time() - t0 > timeout_sec:
                    return
                time.sleep(1)
        except Exception:
            return

    try:
        pc.create_index(
            name=index_name,
            dimension=dimension,
            metric=metric,
            spec=ServerlessSpec(cloud=cloud, region=region),
        )
        _wait_ready()
        return
    except Exception as e:
        msg = str(e).lower()
        # Pinecone often returns 400 INVALID_ARGUMENT when region isn't allowed on plan
        hints = ("invalid_argument" in msg) or ("free plan" in msg) or ("does not support indexes" in msg) or ("bad request" in msg)
        # Be robust: if configured region/cloud isn't the known-free default, allow fallback even if message doesn't match
        is_non_default_target = (str(cloud).lower() != "aws") or (str(region).lower() != "us-east-1")
        if not (hints or is_non_default_target):
            # Re-raise unknown errors when already targeting the default region
            raise
    # Fallback to a widely-supported region on free plans
    pc.create_index(
        name=index_name,
        dimension=dimension,
        metric=metric,
        spec=ServerlessSpec(cloud="aws", region="us-east-1"),
    )
    _wait_ready()


def upsert_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    vectors: List[Dict[str, Any]],
) -> None:
    index = pc.Index(index_name)
    index.upsert(vectors=vectors, namespace=namespace)


def upsert_vector(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    vector: Dict[str, Any],
) -> None:
    index = pc.Index(index_name)
    index.upsert(vectors=[vector], namespace=namespace)


def fetch_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    ids: List[str],
) -> Dict[str, Any]:
    index = pc.Index(index_name)
    res = index.fetch(ids=ids, namespace=namespace)
    # Vereinheitliche Ausgabe auf Dict
    if isinstance(res, dict):
        return res
    # pinecone>=5 liefert Response-Objekte
    try:
        # neuere Clients haben to_dict()
        return res.to_dict()  # type: ignore[attr-defined]
    except Exception:
        vectors = getattr(res, "vectors", None)
        if isinstance(vectors, dict):
            return {"vectors": vectors}
        return {"vectors": {}}


def delete_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    ids: List[str],
) -> None:
    index = pc.Index(index_name)
    index.delete(ids=ids, namespace=namespace)


def delete_by_filter(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    flt: Dict[str, Any],
) -> None:
    try:
        index = pc.Index(index_name)
        try:
            index.delete(filter=flt, namespace=namespace)
        except Exception as e:
            # Wenn der Namespace nicht existiert, behandeln wir es als "nichts zu löschen".
            try:
                from pinecone.exceptions import NotFoundException  # type: ignore
            except Exception:
                NotFoundException = None  # type: ignore
            if (NotFoundException and isinstance(e, NotFoundException)) or (
                "Namespace not found" in str(e)
            ):
                return
            raise
    except Exception as e:
        # Index selbst existiert nicht → ebenfalls still ignorieren
        try:
            from pinecone.exceptions import NotFoundException  # type: ignore
        except Exception:
            NotFoundException = None  # type: ignore
        if (NotFoundException and isinstance(e, NotFoundException)) or (
            "not found" in str(e).lower()
        ):
            return
        raise
```


