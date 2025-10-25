 
import os
import urllib.parse
from typing import List, Dict, Any, Optional
import time, uuid, hashlib

from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
import re
import logging
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv
from pathlib import Path
from openai import OpenAI
from google.cloud import texttospeech
import base64, requests, json, tempfile, subprocess, threading
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
try:
    # Für saubere Fehlererkennung bei Firestore-Indexproblemen
    from google.api_core.exceptions import FailedPrecondition, InvalidArgument
except Exception:  # noqa: BLE001
    FailedPrecondition = InvalidArgument = Exception  # type: ignore

# LiveKit Server SDK
try:
    from livekit import api as lk_api  # type: ignore
except Exception:
    lk_api = None

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
PINECONE_INDEX = os.getenv("PINECONE_INDEX", "sunriza")
PINECONE_CLOUD = os.getenv("PINECONE_CLOUD", "aws")
PINECONE_REGION = os.getenv("PINECONE_REGION", "us-east-1")

# LiveKit
LIVEKIT_URL = os.getenv("LIVEKIT_URL", "").strip()
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "").strip()
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "").strip()

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

# In‑Memory Latenz‑Histories (Rolling Window)
_LAT_HIST: dict[str, list[int]] = {}
_LAT_MAX = 500  # pro Pfad maximal 500 Einträge im Fenster
_USER_CACHE: dict[str, Dict[str, Any]] = {}


def _is_index_missing_error(err: Exception) -> bool:
    """Erkennt typische Firestore-Fehler, wenn ein Composite-Index fehlt.
    Falls erkannt, können wir mit leerer Liste antworten statt 500.
    """
    try:
        if isinstance(err, (FailedPrecondition, InvalidArgument)):
            return True
        msg = str(err).lower()
        # Häufige Textfragmente der Admin-SDK Fehlermeldung
        hints = [
            "failed_precondition",
            "requires an index",
            "missing index",
            "need to create index",
            "request has insufficient indexes",
            "indexes are not defined",
        ]
        return any(h in msg for h in hints)
    except Exception:
        return False


def _strip_accents(text: str) -> str:
    try:
        return ''.join(
            ch for ch in unicodedata.normalize('NFD', text)
            if unicodedata.category(ch) != 'Mn'
        )
    except Exception:
        return text


def _normalize_fact_text_for_hash(text: str) -> str:
    """Erzeuge eine robuste Normalform für Duplikaterkennung.
    - Kleinbuchstaben, Akzente entfernen (ä->a, ö->o, ü->u, ß->ss)
    - Zahlen auf Platzhalter # normalisieren
    - Synonyme vereinheitlichen ("länger"/"groesser" -> "groesser")
    - Possessivformen vereinfachen ("deiner"/"dein" -> "avatar")
    - Nur alnum und Leerzeichen, Whitespace komprimieren
    """
    try:
        s = (text or '').lower().strip()
        s = _strip_accents(s).replace('ß', 'ss')
        # Synonyme/Heuristiken
        repl = {
            ' laenger ': ' groesser ',
            ' länger ': ' groesser ',
            ' groesser ': ' groesser ',
            ' grosser ': ' groesser ',
            ' grosseres ': ' groesser ',
            ' dein ': ' avatar ',
            ' deiner ': ' avatar ',
            ' des avatars ': ' avatar ',
        }
        # Padding spaces for safe replacements
        s = f' {s} '
        for a, b in repl.items():
            s = s.replace(a, b)
        s = s.strip()
        # Zahlen vereinheitlichen
        import re as _re
        s = _re.sub(r"\d+", "#", s)
        # Nur alnum/space
        s = ''.join(ch if ch.isalnum() or ch.isspace() else ' ' for ch in s)
        # Mehrfachspaces -> ein Space
        s = ' '.join(s.split())
        return s
    except Exception:
        return text or ''


def _is_sexual_or_offensive(text: str) -> bool:
    try:
        t = (text or '').lower()
        bad = [
            'penis', 'vagina', 'sex', 'porno', 'porn', 'ficken', 'blowjob',
            'anal', 'dildo', 'ejakulat', 'sperma', 'orgasmus',
        ]
        return any(w in t for w in bad)
    except Exception:
        return False


def _is_allowed_user_fact(text: str) -> bool:
    """Behalte nur sinnvolle, stabile Nutzer-Fakten (Whitelist-Muster)."""
    try:
        import re as _re
        t = (text or '').lower().strip()
        # Name wird separat erkannt/gespeichert → hier nicht nötig
        if _re.search(r"\bmein\s+name\s+ist\b|\bich\s+heisse?\b", t):
            return False
        # Tiere/Kinder Anzahl
        if _re.search(r"\bich\s+habe\s+\d+\s+(hunde|katzen|kinder)\b", t):
            return True
        # Stadt/Land (einfaches Muster)
        if _re.search(r"\bich\s+wohne?\s+in\s+[a-zäöüß\-]{2,}\b", t):
            return True
        return False
    except Exception:
        return False


def _should_store_fact(f: dict, role: str | None = None) -> bool:
    try:
        text = str(f.get('fact_text') or '').strip()
        scope = str(f.get('scope') or '').lower()
        claim_type = str(f.get('claim_type') or 'statement').lower()
        conf = float(f.get('confidence') or 0)
        if not text or conf < 0.75:
            return False
        if claim_type in ('question', 'joke', 'quote'):
            return False
        # Sexual/NSFW nur speichern, wenn explizit als Avatar-Fakt sinnvoll –
        # standardmäßig: nicht speichern. Auch bei role='explicit' speichern wir
        # solche Aussagen NICHT als Fakten (nur Chat erlaubt).
        if _is_sexual_or_offensive(text):
            return False
        if scope == 'user':
            return _is_allowed_user_fact(text)
        # Standard: avatar
        return True
    except Exception:
        return False

def _record_latency_sample(path: str, dur_ms: int) -> None:
    try:
        arr = _LAT_HIST.setdefault(path, [])
        arr.append(int(dur_ms))
        # Rolling Window beschneiden
        if len(arr) > _LAT_MAX:
            del arr[: len(arr) - _LAT_MAX]
    except Exception:
        pass

def _percentile(sorted_vals: list[int], p: float) -> float:
    if not sorted_vals:
        return 0.0
    p = max(0.0, min(100.0, float(p)))
    k = (p / 100.0) * (len(sorted_vals) - 1)
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return float(sorted_vals[f])
    d0 = sorted_vals[f] * (c - k)
    d1 = sorted_vals[c] * (k - f)
    return float(d0 + d1)

# Observability: Latenz-Middleware
@app.middleware("http")
async def timing_middleware(request: Request, call_next):
    t0 = time.perf_counter()
    response = None
    try:
        response = await call_next(request)
        return response
    finally:
        dur_ms = int((time.perf_counter() - t0) * 1000)
        try:
            if response is not None:
                response.headers["X-Response-Time-ms"] = str(dur_ms)
        except Exception:
            pass
        try:
            logger.info(
                "LATENCY method=%s path=%s status=%s dur_ms=%s",
                request.method,
                request.url.path,
                getattr(response, "status_code", None),
                dur_ms,
            )
            # Rolling-Window Sample erfassen
            _record_latency_sample(request.url.path, dur_ms)
        except Exception:
            pass

# Pinecone Query mit hartem Timeout
def _query_with_timeout(index_name: str, namespace: str, vec: List[float], top_k: int = 5, timeout_sec: int = 10) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    errors: list[Exception] = []

    def _worker() -> None:
        try:
            idx = pc.Index(index_name)
            res = idx.query(
                vector=vec,
                top_k=top_k,
                namespace=namespace,
                include_values=False,
                include_metadata=True,
            )
            if isinstance(res, dict):
                result.update(res)
            else:
                result["matches"] = getattr(res, "matches", [])
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    th = threading.Thread(target=_worker, daemon=True)
    th.start()
    th.join(timeout=timeout_sec)
    if result:
        return result
    if errors:
        raise errors[0]
    raise TimeoutError("Pinecone query timeout")

class LivekitTokenRequest(BaseModel):
    user_id: str
    avatar_id: str
    room: str | None = None
    name: str | None = None
    avatar_image_url: str | None = None

class LivekitTokenResponse(BaseModel):
    url: str
    token: str
    room: str
    identity: str

@app.post("/livekit/token", response_model=LivekitTokenResponse)
def create_livekit_token(payload: LivekitTokenRequest) -> LivekitTokenResponse:
    if not (LIVEKIT_URL and LIVEKIT_API_KEY and LIVEKIT_API_SECRET):
        raise HTTPException(status_code=400, detail="LIVEKIT_URL/API_KEY/API_SECRET fehlen")
    if lk_api is None:
        raise HTTPException(status_code=500, detail="LiveKit Server SDK nicht installiert")
    try:
        identity = payload.user_id.strip()
        room = (payload.room or f"user_{payload.user_id.strip()}_avatar_{payload.avatar_id.strip()}")[:128]
        name = (payload.name or identity)[:64]
        at = lk_api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        grants = lk_api.VideoGrants(room=room, room_join=True)
        token = at.with_identity(identity).with_name(name).with_grants(grants).to_jwt()
        # Optional: Avatar-Bild in Firestore synchronisieren
        try:
            if FIREBASE_AVAILABLE and db and payload.avatar_image_url:
                doc_ref = db.collection("users").document(payload.user_id).collection("avatars").document(payload.avatar_id)
                doc_ref.set({
                    "avatarImageUrl": payload.avatar_image_url.strip(),
                    "updatedAt": firestore.SERVER_TIMESTAMP if FIREBASE_AVAILABLE else int(time.time()*1000),
                }, merge=True)
        except Exception as _e:
            logger.warning(f"AvatarImageUrl Persist Fehler: {_e}")
        return LivekitTokenResponse(url=LIVEKIT_URL, token=token, room=room, identity=identity)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Token Fehler: {e}")


# NEU: ElevenLabs Voices Liste (Proxy)
@app.get("/avatar/voices")
def list_elevenlabs_voices() -> Dict[str, Any]:
    key = os.getenv("ELEVENLABS_API_KEY")
    if not key:
        raise HTTPException(status_code=400, detail="ELEVENLABS_API_KEY fehlt")
    try:
        r = requests.get(
            "https://api.elevenlabs.io/v1/voices",
            headers={"xi-api-key": key, "accept": "application/json"},
            timeout=30,
        )
        r.raise_for_status()
        return r.json()  # enthält { voices: [...] }
    except requests.HTTPError as e:
        raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voices Fehler: {e}")


# Persistenter Debug-Recorder für die letzte Insert-Operation
_LAST_INSERT_PATH = (Path(__file__).resolve().parents[1] / "last_memory_insert.json")

def _record_last_insert(data: Dict[str, Any]) -> None:
    try:
        data["ts"] = int(time.time() * 1000)
        _LAST_INSERT_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    except Exception:
        pass


def _cache_user_snapshot(user_id: str) -> Dict[str, Any]:
    if not FIREBASE_AVAILABLE or not db:
        return {}
    try:
        if user_id in _USER_CACHE:
            return _USER_CACHE[user_id] or {}
        snap = db.collection("users").document(user_id).get()
        data = snap.to_dict() or {}
        email = data.get("email") or data.get("profileEmail")
        display_name = data.get("displayName") or data.get("profileName")
        info = {
            "email": email if isinstance(email, str) else None,
            "display_name": display_name if isinstance(display_name, str) else None,
        }
        _USER_CACHE[user_id] = info
        return info
    except Exception:
        return {}


def _read_known_user_name(user_id: str, avatar_id: str) -> Optional[str]:
    """Liest einen benutzerspezifischen Anzeigenamen aus der Chat-Beziehung.
    Quelle: avatarUserChats/{user_id}_{avatar_id}.user_name; Fallback: users/{user_id}.displayName
    """
    if not FIREBASE_AVAILABLE or not db:
        return None
    try:
        chat_id = f"{user_id}_{avatar_id}"
        snap = db.collection("avatarUserChats").document(chat_id).get()
        data = snap.to_dict() or {}
        nm = (data.get("user_name") or data.get("participant_name") or "").strip()
        if nm:
            return nm
    except Exception:
        pass
    try:
        u = _cache_user_snapshot(user_id)
        if u.get("display_name"):
            return str(u["display_name"]).strip()
    except Exception:
        pass
    return None


def _maybe_update_user_name(user_id: str, avatar_id: str, user_text: str) -> None:
    """Erkennt Muster wie "mein Name ist X" oder "ich heiße X" und speichert den Namen
    in avatarUserChats/{chat_id}.user_name. (kein Fehlerwurf)
    """
    if not FIREBASE_AVAILABLE or not db:
        return
    try:
        import re as _re
        t = (user_text or "").strip()
        m = _re.search(r"\bmein\s+name\s+ist\s+([A-Za-zÄÖÜäöüß\-]{2,}(?:\s+[A-Za-zÄÖÜäöüß\-]{2,}){0,2})\b", t, flags=_re.IGNORECASE)
        if not m:
            m = _re.search(r"\bich\s+heisse?\s+([A-Za-zÄÖÜäöüß\-]{2,}(?:\s+[A-Za-zÄÖÜäöüß\-]{2,}){0,2})\b", t, flags=_re.IGNORECASE)
        if m:
            name = m.group(1).strip()
            chat_id = f"{user_id}_{avatar_id}"
            db.collection("avatarUserChats").document(chat_id).set({
                "user_name": name,
                "updatedAt": firestore.SERVER_TIMESTAMP if FIREBASE_AVAILABLE else int(time.time()*1000),
            }, merge=True)
    except Exception:
        pass


# --- Daily User Summaries (per user_id + avatar_id + day) ---

def _utc_midnight(dt: datetime) -> datetime:
    dt = dt.astimezone(timezone.utc)
    return datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)


def _yyyymmdd(dt: datetime) -> str:
    return dt.strftime("%Y%m%d")


def _has_daily_summary(user_id: str, avatar_id: str, yyyymmdd: str) -> bool:
    if not FIREBASE_AVAILABLE or not db:
        return False
    try:
        ref = db.collection("users").document(user_id).collection("avatars").document(avatar_id).collection("dailySummaries").document(yyyymmdd)
        snap = ref.get()
        return snap.exists
    except Exception:
        return False


def _store_daily_summary(user_id: str, avatar_id: str, yyyymmdd: str, summary: dict) -> None:
    if not FIREBASE_AVAILABLE or not db:
        return
    try:
        ref = db.collection("users").document(user_id).collection("avatars").document(avatar_id).collection("dailySummaries").document(yyyymmdd)
        ref.set({
            **summary,
            "created_at": int(time.time()*1000),
            "date": yyyymmdd,
        }, merge=True)
    except Exception:
        pass


def _build_day_summary_with_llm(messages: list[dict], lang_hint: str | None = None) -> dict | None:
    try:
        # Kontexte bauen (nur Text, kurze Zeilen)
        lines: list[str] = []
        for m in messages[:200]:  # Kappung
            sender = m.get("sender") or "?"
            txt = (m.get("content") or "").strip()
            if not txt:
                continue
            lines.append(f"{sender}: {txt}")
        convo = "\n".join(lines)
        prompt = (
            "Erstelle eine kompakte Tageszusammenfassung der Unterhaltung. "
            "Antworte NUR als JSON mit Feldern: "
            "{\"summary\": str (5-8 Sätze, nur Wichtiges), "
            " \"bullet_points\": [str (3-6 Kernaussagen)], "
            " \"sentiments\": [str (z.B. 'angespannt', 'versöhnt', 'fröhlich')], "
            " \"topics\": [str (Hauptthemen)], "
            " \"open_questions\": [str] }."
        )
        if lang_hint:
            prompt += f" Schreibe in Sprache: {lang_hint}."
        comp = client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": "Du bist ein genauer Tageszusammenfasser. Antworte nur mit JSON."},
                {"role": "user", "content": prompt + "\n\n" + convo},
            ],
            temperature=0.2,
            max_tokens=300,
            timeout=10,
        )
        raw = (comp.choices[0].message.content or "").strip()
        try:
            data = json.loads(raw)
        except Exception:
            start = raw.find("{")
            end = raw.rfind("}")
            data = json.loads(raw[start:end+1]) if (start != -1 and end != -1) else None
        if not isinstance(data, dict):
            return None
        # Sanitize
        data["summary"] = str(data.get("summary") or "").strip()
        for key in ("bullet_points", "sentiments", "topics", "open_questions"):
            val = data.get(key)
            if not isinstance(val, list):
                data[key] = []
            else:
                data[key] = [str(x).strip() for x in val if isinstance(x, (str, int, float))][:10]
        return data
    except Exception as _e:
        logger.warning(f"Daily summary LLM Fehler: {_e}")
        return None


def _maybe_generate_yesterday_summary(user_id: str, avatar_id: str, lang_hint: str | None = None) -> None:
    """Wenn gestern Chats stattfanden und noch keine Summary existiert, erstelle sie jetzt."""
    if not FIREBASE_AVAILABLE or not db:
        return
    try:
        now = datetime.now(timezone.utc)
        today_mid = _utc_midnight(now)
        yesterday_mid = today_mid - timedelta(days=1)
        yyyymmdd = _yyyymmdd(yesterday_mid)
        if _has_daily_summary(user_id, avatar_id, yyyymmdd):
            return
        # Nachrichten von gestern laden
        start_ms = int(yesterday_mid.timestamp()*1000)
        end_ms = int(today_mid.timestamp()*1000) - 1
        chat_id = f"{user_id}_{avatar_id}"
        q = db.collection("avatarUserChats").document(chat_id).collection("messages")\
            .where("timestamp", ">=", start_ms).where("timestamp", "<=", end_ms)\
            .order_by("timestamp")
        docs = q.get()
        messages = [d.to_dict() for d in docs]
        if not messages:
            return
        data = _build_day_summary_with_llm(messages, lang_hint)
        if not data or not data.get("summary"):
            return
        _store_daily_summary(user_id, avatar_id, yyyymmdd, data)
        # Optional: Auch in Pinecone ablegen
        try:
            text = data.get("summary")
            emb_list, real_dim = _create_embeddings_with_timeout([text], EMBEDDING_MODEL, timeout_sec=10)
            namespace = f"{user_id}_{avatar_id}"
            index_name = _pinecone_index_for(user_id, avatar_id)
            ensure_index_exists(pc=pc, index_name=index_name, dimension=real_dim, metric="cosine", cloud=PINECONE_CLOUD, region=PINECONE_REGION)
            vec = {
                "id": f"daily-{yyyymmdd}",
                "values": emb_list[0],
                "metadata": {
                    "type": "user_daily_summary",
                    "date": yyyymmdd,
                    "user_id": user_id,
                    "avatar_id": avatar_id,
                    "summary": text,
                    "sentiments": data.get("sentiments") or [],
                    "topics": data.get("topics") or [],
                    "created_at": int(time.time()*1000),
                },
            }
            upsert_vector(pc, index_name, namespace, vec)
        except Exception as _e:
            logger.warning(f"Pinecone daily summary Fehler: {_e}")
    except Exception as e:
        logger.warning(f"Daily summary Fehler: {e}")


def _anonymize_user_id(user_id: str) -> str:
    try:
        return hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:16]
    except Exception:
        return user_id


def _personalize_context_texts(texts: list[str], avatar_names) -> list[str]:
    """Ersetzt Avatar‑Namen im Kontext durch Ich‑Form (für Anzeige an das LLM).
    avatar_names kann String oder Liste sein (z. B. Vorname, Nachname, Spitzname, "Frau Nachname").
    """
    # Namen sammeln
    names: set[str] = set()
    try:
        if isinstance(avatar_names, str) and avatar_names.strip():
            names.add(avatar_names.strip())
            parts = avatar_names.replace("-", " ").split()
            names.update(p.strip() for p in parts if p.strip())
        elif isinstance(avatar_names, (list, tuple, set)):
            for n in avatar_names:
                if isinstance(n, str) and n.strip():
                    names.add(n.strip())
                    parts = n.replace("-", " ").split()
                    names.update(p.strip() for p in parts if p.strip())
    except Exception:
        pass
    tokens = {t for t in names if len(t) >= 2}
    ordered_tokens = sorted(tokens, key=len, reverse=True)
    out: list[str] = []
    for original in texts:
        prefix = ""
        core = original
        if original.startswith("- "):
            prefix = "- "
            core = original[2:]
        modified = core
        for name in ordered_tokens:
            pattern = re.compile(rf"\b{re.escape(name)}\b", flags=re.IGNORECASE)
            modified = pattern.sub("Ich", modified)
        modified = re.sub(r"\bIch hat\b", "Ich habe", modified, flags=re.IGNORECASE)
        modified = re.sub(r"\bIch ist\b", "Ich bin", modified, flags=re.IGNORECASE)
        modified = re.sub(r"\bIch war\b", "Ich war", modified, flags=re.IGNORECASE)
        out.append(prefix + modified)
    return out


def _rewrite_avatar_pronouns(text: str, avatar_names) -> str:
    """Konservative Nachbearbeitung der Model‑Antwort:
    - Ersetze Namen des Avatars durch Ich‑Form
    - Korrigiere häufige Grammatikfälle (Ich hat→Ich habe, von Ich→von mir, ...)
    """
    try:
        names: set[str] = set()
        if isinstance(avatar_names, str) and avatar_names.strip():
            names.add(avatar_names.strip())
            parts = avatar_names.replace("-", " ").split()
            names.update(p.strip() for p in parts if p.strip())
        elif isinstance(avatar_names, (list, tuple, set)):
            for n in avatar_names:
                if isinstance(n, str) and n.strip():
                    names.add(n.strip())
                    parts = n.replace("-", " ").split()
                    names.update(p.strip() for p in parts if p.strip())
        if not names:
            return text
        tokens = {t for t in names if len(t) >= 2}
        # Zusätzliche höfliche Formen (Frau/Herr Nachname)
        try:
            for n in list(tokens):
                if " " in n:
                    last = n.split()[-1]
                    if len(last) >= 2:
                        tokens.add(f"Frau {last}")
                        tokens.add(f"Herr {last}")
        except Exception:
            pass
        ordered = sorted(tokens, key=len, reverse=True)
        out = text
        for name in ordered:
            pattern = re.compile(rf"\b{re.escape(name)}\b", flags=re.IGNORECASE)
            out = pattern.sub("Ich", out)
        # Grammatik-Fixes
        out = re.sub(r"\bIch hat\b", "Ich habe", out, flags=re.IGNORECASE)
        out = re.sub(r"\bIch ist\b", "Ich bin", out, flags=re.IGNORECASE)
        out = re.sub(r"\bvon\s+Ich\b", "von mir", out, flags=re.IGNORECASE)
        out = re.sub(r"\bbei\s+Ich\b", "bei mir", out, flags=re.IGNORECASE)
        out = re.sub(r"\bfür\s+Ich\b", "für mich", out, flags=re.IGNORECASE)
        out = re.sub(r"\bmit\s+Ich\b", "mit mir", out, flags=re.IGNORECASE)
        out = re.sub(r"\büber\s+Ich\b", "über mich", out, flags=re.IGNORECASE)
        return out
    except Exception:
        return text


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
        every_n = max(1, int(os.getenv("ROLLING_SUMMARY_EVERY_N", "1")))
        default_window = max(5, every_n)
        window_n = max(1, int(os.getenv("ROLLING_SUMMARY_WINDOW", str(default_window))))

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
            timeout=10,
        )
        summary = (comp.choices[0].message.content or "").strip()
        if not summary:
            # ohne Summary kein Eintrag
            st["recent_texts"] = recent
            _save_ns_state(namespace, st)
            return

        try:
            delete_by_filter(
                pc=pc,
                index_name=index_name,
                namespace=namespace,
                flt={"type": {"$eq": "meta_summary"}},
            )
        except Exception:
            pass

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
            "isUser": sender == "user",  # Konsistent mit Frontend!
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


def _store_chat_fact(
    user_id: str,
    avatar_id: str,
    source_message_id: str,
    fact_text: str,
    confidence: float,
    scope: str = "user",
) -> Dict[str, Any] | None:
    if not FIREBASE_AVAILABLE or not db:
        return None
    try:
        info = _cache_user_snapshot(user_id)
        chat_id = f"{user_id}_{avatar_id}"
        fact_id = f"fact-{int(time.time()*1000)}-{uuid.uuid4().hex[:6]}"
        # Robuster Hash über normalisierte Fakt-Form (verhindert erneutes Speichern ähnlicher Behauptungen)
        norm = _normalize_fact_text_for_hash(fact_text)
        fact_hash = hashlib.sha256(norm.encode("utf-8")).hexdigest()

        try:
            # Dublettenregel: existiert derselbe Hash bereits in pending/approved/rejected → nicht erneut speichern
            existing = db.collection("avatarFactsQueue") \
                .where("avatar_id", "==", avatar_id) \
                .where("fact_hash", "==", fact_hash) \
                .limit(50).get()
            if existing:
                return None
        except Exception as _e:
            # Bei Index-Fehler: zusätzlich Fallback: einfache Textsuche in den letzten ~500 Einträgen des Avatars
            if _is_index_missing_error(_e):
                try:
                    raw = db.collection("avatarFactsQueue").where("avatar_id", "==", avatar_id).limit(500).get()
                    for d in raw:
                        data2 = d.to_dict() or {}
                        if data2.get("fact_hash") == fact_hash:
                            return None
                        # Zusatz: falls früher ohne Normalisierung gespeichert wurde
                        old_hash = hashlib.sha256((data2.get("fact_text") or "").strip().lower().encode("utf-8")).hexdigest()
                        if old_hash == fact_hash:
                            return None
                except Exception:
                    pass

        ts = int(time.time()*1000)
        doc = {
            "fact_id": fact_id,
            "user_id": user_id,
            "avatar_id": avatar_id,
            "source_chat_id": chat_id,
            "source_message_id": source_message_id,
            "fact_text": fact_text.strip(),
            "confidence": float(confidence),
            "scope": scope,
            "created_at": ts,
            "updated_at": ts,
            "status": "pending",
            "last_reviewer": None,
            "history": [
                {
                    "action": "captured",
                    "at": ts,
                    "by": _anonymize_user_id(user_id),
                }
            ],
            "author_email": info.get("email"),
            "author_display_name": info.get("display_name"),
            "author_hash": _anonymize_user_id(user_id),
            "fact_hash": fact_hash,
            # optionale Klassifikation – wird beim Extrahieren gefüllt
            "claim_type": None,
            "polarity": None,
            "certainty": None,
            "subject": None,
            "extracted_from": "user",
        }
        db.collection("avatarFactsQueue").document(fact_id).set(doc)
        return {
            "fact_id": fact_id,
            "fact_text": fact_text.strip(),
            "confidence": float(confidence),
            "scope": scope,
            "source_message_id": source_message_id,
            "status": "pending",
        }
    except Exception as e:
        logger.warning(f"Chat-Fact Speicherfehler: {e}")
        return None


def _extract_chat_facts(
    user_id: str,
    avatar_id: str,
    source_message_id: str,
    user_text: str | None,
    avatar_text: str | None,
) -> list[dict[str, Any]]:
    facts: list[dict[str, Any]] = []
    convo_avatar = (avatar_text or "").strip()
    convo_user = (user_text or "").strip()
    if not convo_avatar and not convo_user:
        return facts

    try:
        # Nur Nutzertext analysieren – Avatar-Antworten sind keine Faktenquelle
        conversation = "Nutzer: " + (convo_user or "[leer]")
        prompt = (
            "Analysiere ausschließlich den Nutzertext (Avatar-Antworten ignorieren). "
            "Extrahiere maximal zwei neue, überprüfbare Fakten. "
            "Priorität: (1) Fakten ÜBER DEN AVATAR, (2) sonst ÜBER DEN NUTZER. "
            "Antworte NUR als JSON-Array. Eintrag: {\\\"fact_text\\\": str, \\\"confidence\\\": float 0..1, \\\"scope\\\": 'avatar'|'user', \\\"claim_type\\\": 'statement'|'assumption'|'question'|'joke'|'quote', \\\"polarity\\\": 'affirmative'|'negative', \\\"certainty\\\": float 0..1, \\\"subject\\\": 'avatar'|'user'}. "
            "Hinweise: Annahmen (vermutet, wohl, vielleicht), Zitate (\"...\" sagte X), Fragen (?), Humor markieren."
        )
        messages = [
            {
                "role": "system",
                "content": "Du bist ein wissensbasierter Extraktor. Konzentriere dich ausschließlich auf Fakten aus dem Nutzertext.",
            },
            {
                "role": "user",
                "content": prompt + "\n\nNutzertext:\n" + conversation,
            },
        ]
        comp = client.chat.completions.create(
            model=GPT_MODEL,
            messages=messages,
            temperature=0,
            max_tokens=180,
            timeout=8,
        )
        raw = (comp.choices[0].message.content or "").strip()
        data = None
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            try:
                start = raw.find("[")
                end = raw.rfind("]")
                if start != -1 and end != -1:
                    data = json.loads(raw[start : end + 1])
            except Exception:
                data = None
        if not isinstance(data, list):
            return facts
        for entry in data:
            if not isinstance(entry, dict):
                continue
            text = str(entry.get("fact_text", "")).strip()
            if not text:
                continue
            conf = entry.get("confidence", 0.6)
            try:
                conf = float(conf)
            except Exception:
                conf = 0.6
            conf = max(0.0, min(1.0, conf))
            scope = str(entry.get("scope", "avatar")).strip().lower() or "avatar"
            if scope not in ("avatar", "user"):
                scope = "avatar"
            claim_type = str(entry.get("claim_type") or "statement").strip().lower()
            polarity = str(entry.get("polarity") or "affirmative").strip().lower()
            certainty = entry.get("certainty")
            try:
                certainty = float(certainty) if certainty is not None else None
            except Exception:
                certainty = None
            subject = str(entry.get("subject") or scope).strip().lower()
            facts.append(
                {
                    "fact_text": text,
                    "confidence": conf,
                    "scope": scope,
                    "source_message_id": source_message_id,
                    "claim_type": claim_type,
                    "polarity": polarity,
                    "certainty": certainty,
                    "subject": subject,
                    "extracted_from": "user",
                }
            )
        if facts:
            logger.info(
                f"CHAT_FACT_EXTRACTED uid='{user_id}' avatar='{avatar_id}' count={len(facts)}"
            )
    except Exception as e:
        logger.warning(f"CHAT_FACT_EXTRACT error: {e}")
    # Heuristischer Fallback: einfache Muster im Nutzertext
    if not facts and convo_user:
        try:
            ut = convo_user
            # Beziehung: "war X Jahre mit dir verheiratet"
            m = re.search(r"\bwar\s+(\d{1,3})\s*jahre[n]?\s+mit\s+dir\s+verheiratet\b", ut, flags=re.IGNORECASE)
            if m:
                yrs = m.group(1)
                facts.append({
                    "fact_text": f"Der Nutzer war {yrs} Jahre mit dem Avatar verheiratet.",
                    "confidence": 0.8,
                    "scope": "avatar",
                    "source_message_id": source_message_id,
                    "claim_type": "statement",
                    "polarity": "affirmative",
                    "certainty": 0.8,
                    "subject": "avatar",
                    "extracted_from": "user",
                })
            # Vergleich: "mein Penis ist (20) cm länger als deiner"
            m = re.search(r"\bmein\s+penis\s+ist\s+(?:ca\.?\s*)?(\d{1,3})\s*cm\s*länger\s+als\s+dein(?:er)?\b", ut, flags=re.IGNORECASE)
            if m:
                cm = m.group(1)
                facts.append({
                    "fact_text": f"Der Nutzer behauptet, sein Penis sei {cm} cm länger als der des Avatars.",
                    "confidence": 0.6,
                    "scope": "avatar",
                    "source_message_id": source_message_id,
                    "claim_type": "statement",
                    "polarity": "affirmative",
                    "certainty": 0.6,
                    "subject": "avatar",
                    "extracted_from": "user",
                })
            elif re.search(r"\bmein\s+penis\s+ist\s+.*länger\s+als\s+dein(?:er)?\b", ut, flags=re.IGNORECASE):
                facts.append({
                    "fact_text": "Der Nutzer behauptet, sein Penis sei länger als der des Avatars.",
                    "confidence": 0.5,
                    "scope": "avatar",
                    "source_message_id": source_message_id,
                    "claim_type": "assumption",
                    "polarity": "affirmative",
                    "certainty": 0.5,
                    "subject": "avatar",
                    "extracted_from": "user",
                })

            # Generisch: "ich bin ..." → Nutzer-Eigenschaft
            m = re.search(r"\bich bin ([^.?!]{3,80})", ut, flags=re.IGNORECASE)
            if m:
                txt = f"Ich bin {m.group(1).strip()}"
                facts.append({
                    "fact_text": txt,
                    "confidence": 0.55,
                    "scope": "user",
                    "source_message_id": source_message_id,
                    "claim_type": "statement",
                    "polarity": "affirmative",
                    "certainty": 0.55,
                    "subject": "user",
                    "extracted_from": "user",
                })
            m = re.search(r"\bich habe (\d{1,3})\s+(hunde|katzen|kinder)\b", ut, flags=re.IGNORECASE)
            if m:
                num, what = m.group(1), m.group(2)
                txt = f"Ich habe {num} {what}"
                facts.append({
                    "fact_text": txt,
                    "confidence": 0.6,
                    "scope": "user",
                    "source_message_id": source_message_id,
                    "claim_type": "statement",
                    "polarity": "affirmative",
                    "certainty": 0.6,
                    "subject": "user",
                    "extracted_from": "user",
                })
        except Exception:
            pass
    return facts


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
    mode = os.getenv("PINECONE_INDEX_MODE", "per_avatar").lower()
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
    mode = os.getenv("PINECONE_INDEX_MODE", "per_avatar").lower()
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


@app.get("/metrics/latency")
def latency_metrics() -> Dict[str, Any]:
    """Einfaches Latenz-Dashboard (Rolling-Window) pro Pfad.
    Liefert count, min, p50, p95, p99, max in Millisekunden.
    """
    out: Dict[str, Any] = {}
    try:
        for path, vals in _LAT_HIST.items():
            if not vals:
                continue
            svals = sorted(vals)
            out[path] = {
                "count": len(svals),
                "min": int(svals[0]),
                "p50": int(_percentile(svals, 50)),
                "p95": int(_percentile(svals, 95)),
                "p99": int(_percentile(svals, 99)),
                "max": int(svals[-1]),
            }
    except Exception as e:
        logger.warning(f"Latency-Metrics Fehler: {e}")
    return out


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
    primary_index = _pinecone_index_for(payload.user_id, payload.avatar_id)
    base_index = os.getenv("PINECONE_INDEX", "avatars-index")
    enable_fallback = os.getenv("PINECONE_QUERY_FALLBACK_BASE", "1") == "1"
    try:
        logger.info(
            f"MEMORY_QUERY uid='{payload.user_id}' avatar='{payload.avatar_id}' ns='{namespace}' idx='{primary_index}' base='{base_index}' top_k={payload.top_k}"
        )
        # 1) Embedding mit hartem Timeout erzeugen (einmal für alle Versuche)
        emb_list, real_dim = _create_embeddings_with_timeout([payload.query], EMBEDDING_MODEL, timeout_sec=10)
        vec = emb_list[0]

        def _run_query(index_name: str) -> list[dict]:
            # Query ausführen – bei fehlendem Index einmal automatisch anlegen und erneut versuchen
            try:
                res = _query_with_timeout(index_name=index_name, namespace=namespace, vec=vec, top_k=payload.top_k, timeout_sec=10)
            except Exception as e:
                try:
                    # Häufig: 404 Not Found → Index fehlt (per_avatar). Dann auto-create und retry.
                    ensure_index_exists(
                        pc=pc,
                        index_name=index_name,
                        dimension=EMBEDDING_DIM,
                        metric="cosine",
                        cloud=PINECONE_CLOUD,
                        region=PINECONE_REGION,
                    )
                    res = _query_with_timeout(index_name=index_name, namespace=namespace, vec=vec, top_k=payload.top_k, timeout_sec=10)
                except Exception:
                    # Letzter Fallback: kein Kontext
                    logger.warning(f"PINECONE query failed for index='{index_name}': {e}")
                    return []
            matches = res.get("matches", []) if isinstance(res, dict) else getattr(res, "matches", [])
            out: list[dict] = []
            for m in matches:
                if isinstance(m, dict):
                    out.append({
                        "id": m.get("id"),
                        "score": m.get("score"),
                        "metadata": m.get("metadata"),
                    })
                else:
                    out.append({
                        "id": getattr(m, "id", None),
                        "score": getattr(m, "score", None),
                        "metadata": getattr(m, "metadata", None),
                    })
            return out

        # 2) Primär: per‑Avatar Index
        results = _run_query(primary_index)
        if not results and enable_fallback and base_index != primary_index:
            try:
                logger.info(f"PINECONE query fallback: primary='{primary_index}' empty → trying base='{base_index}' ns='{namespace}'")
                results = _run_query(base_index)
            except Exception as _e:
                logger.warning(f"PINECONE fallback query error: {_e}")

        # 3) Antwort
        return QueryResponse(namespace=namespace, results=results)
    except Exception as e:
        # Nicht mehr fehlschlagen lassen – liefere einfach leeren Kontext
        logger.warning(f"Pinecone-Query-Fehler (toleriert): {e}")
        return QueryResponse(namespace=f"{payload.user_id}_{payload.avatar_id}", results=[])


class ChatRequest(BaseModel):
    user_id: str
    avatar_id: str
    message: str
    top_k: int = 5
    voice_id: str | None = None
    avatar_name: str | None = None
    target_language: str | None = None  # z. B. 'de', 'en', 'fr'


class ChatResponse(BaseModel):
    answer: str
    used_context: List[Dict[str, Any]]
    tts_audio_b64: str | None = None
    chat_id: str | None = None  # Für Chat-Verlauf-Tracking
    fact_candidates: List[Dict[str, Any]] | None = None

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
        # Voice-State zentral speichern (Firestore), falls verfügbar
        try:
            if FIREBASE_AVAILABLE and db:
                doc_ref = db.collection("users").document(payload.user_id).collection("avatars").document(payload.avatar_id)
                voice_state = {
                    "elevenVoiceId": voice_id,
                    "name": name,
                }
                # Labels in Voice-State übernehmen
                if payload.dialect:
                    voice_state["dialect"] = str(payload.dialect)
                if payload.tempo is not None:
                    try:
                        voice_state["tempo"] = float(payload.tempo)
                    except Exception:
                        pass
                if payload.stability is not None:
                    try:
                        voice_state["stability"] = float(payload.stability)
                    except Exception:
                        pass
                if payload.similarity is not None:
                    try:
                        voice_state["similarity"] = float(payload.similarity)
                    except Exception:
                        pass
                doc_ref.set({
                    "training": {"voice": voice_state},
                    "updatedAt": firestore.SERVER_TIMESTAMP if FIREBASE_AVAILABLE else int(time.time()*1000),
                }, merge=True)
        except Exception as _e:
            logger.warning(f"Voice-State Persist Fehler: {_e}")

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


# Voice-State zentrale Ablage/Abfrage
class VoiceState(BaseModel):
    voice_id: str | None = None
    name: str | None = None
    stability: float | None = None
    similarity: float | None = None
    tempo: float | None = None
    dialect: str | None = None

class VoiceStateGetRequest(BaseModel):
    user_id: str
    avatar_id: str

class VoiceStateSetRequest(BaseModel):
    user_id: str
    avatar_id: str
    voice: VoiceState


def _read_voice_state(user_id: str, avatar_id: str) -> Dict[str, Any]:
    if not FIREBASE_AVAILABLE or not db:
        return {}
    try:
        doc = db.collection("users").document(user_id).collection("avatars").document(avatar_id).get()
        data = doc.to_dict() or {}
        training = (data.get("training") or {}) if isinstance(data, dict) else {}
        voice = (training.get("voice") or {}) if isinstance(training, dict) else {}
        # Normalisiere Schlüssel
        mapped = {
            "voice_id": voice.get("elevenVoiceId") or voice.get("voice_id"),
            "name": voice.get("name"),
            "stability": voice.get("stability"),
            "similarity": voice.get("similarity"),
            "tempo": voice.get("tempo"),
            "dialect": voice.get("dialect"),
        }
        # Entferne leere Felder
        return {k: v for k, v in mapped.items() if v is not None}
    except Exception as e:
        logger.warning(f"Voice-State Read Fehler: {e}")
        return {}


def _write_voice_state(user_id: str, avatar_id: str, voice: Dict[str, Any]) -> bool:
    if not FIREBASE_AVAILABLE or not db:
        return False
    try:
        # Eingehende Keys normalisieren → Firestore Format
        vs: Dict[str, Any] = {}
        if voice.get("voice_id"):
            vs["elevenVoiceId"] = str(voice["voice_id"]).strip()
        for fld in ("name", "dialect"):
            if voice.get(fld) is not None:
                vs[fld] = str(voice.get(fld))
        for fld in ("stability", "similarity", "tempo"):
            if voice.get(fld) is not None:
                try:
                    vs[fld] = float(voice.get(fld))
                except Exception:
                    pass
        db.collection("users").document(user_id).collection("avatars").document(avatar_id).set({
            "training": {"voice": vs},
            "updatedAt": firestore.SERVER_TIMESTAMP if FIREBASE_AVAILABLE else int(time.time()*1000),
        }, merge=True)
        return True
    except Exception as e:
        logger.warning(f"Voice-State Write Fehler: {e}")
        return False


@app.post("/avatar/voice/state/get")
def get_voice_state(payload: VoiceStateGetRequest) -> Dict[str, Any]:
    try:
        state = _read_voice_state(payload.user_id, payload.avatar_id)
        return {"voice": state}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice-State Get Fehler: {e}")


@app.post("/avatar/voice/state/set")
def set_voice_state(payload: VoiceStateSetRequest) -> Dict[str, Any]:
    try:
        ok = _write_voice_state(payload.user_id, payload.avatar_id, payload.voice.model_dump())
        if not ok:
            raise HTTPException(status_code=500, detail="Voice-State speichern fehlgeschlagen (kein Firestore)")
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Voice-State Set Fehler: {e}")

@app.post("/avatar/chat", response_model=ChatResponse)
def chat_with_avatar(payload: ChatRequest, request: Request) -> ChatResponse:
    # 0) Sprache klassifizieren: klare Fremdsprache vs. gemischt (unter Berücksichtigung der Nutzer-Sprache)
    def _classify_language(text: str, user_lang_hint: str | None) -> dict:
        try:
            prompt = (
                "Ermittle Hauptsprache des folgenden Textes. Antworte NUR als kompaktes JSON:"
                " {\"lang\":\"<iso-639-1>\",\"is_mixed\":true|false}.\n"
                f"User-Sprache: {user_lang_hint or 'unbekannt'}.\n"
                "Definition is_mixed: true NUR wenn >50% der Tokens in der User-Sprache sind,"
                " aber es klar erkennbare Fremdsprach-Teile gibt. Andernfalls false."
                "\nText:\n" + (text or "")
            )
            comp = client.chat.completions.create(
                model=GPT_MODEL,
                messages=[
                    {"role": "system", "content": "Du bist ein präziser Sprachdetektor. Antworte nur mit JSON."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0,
                max_tokens=60,
                timeout=8,
            )
            raw = (comp.choices[0].message.content or "").strip()
            data = json.loads(raw)
            lang = str(data.get("lang", "")).lower()[:5]
            is_mixed = bool(data.get("is_mixed", False))
            return {"lang": lang, "is_mixed": is_mixed}
        except Exception:
            # Fallback: Heuristik für nicht-lateinische Schriften
            txt = (text or "")
            tl = (user_lang_hint or "").lower().strip()
            if any("\u3040" <= ch <= "\u30ff" for ch in txt):
                return {"lang": "ja", "is_mixed": False}
            if any("\u0400" <= ch <= "\u04FF" for ch in txt):
                return {"lang": "ru", "is_mixed": False}
            if any("\u0600" <= ch <= "\u06FF" for ch in txt):
                return {"lang": "ar", "is_mixed": False}
            # Einfache Indizien für Spanisch
            if any(c in txt for c in "áéíóúñ¿¡") or any(w in txt.lower() for w in ["hola", "gracias", "buenos", "estoy", "porque", "qué", "como", "hablas"]):
                return {"lang": "es", "is_mixed": (tl == "es")}
            return {"lang": None, "is_mixed": False}
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
    # 1) Nutzername ggf. erkennen/speichern
    try:
        _maybe_update_user_name(payload.user_id, payload.avatar_id, payload.message)
    except Exception:
        pass
    # 2) Daily Summary (gestern) ggf. generieren (asynchron, blockiert Chat nicht)
    def _run_daily_summary():
        try:
            _maybe_generate_yesterday_summary(payload.user_id, payload.avatar_id, payload.target_language)
        except Exception:
            pass
    threading.Thread(target=_run_daily_summary, daemon=True).start()
    
    # 3) RAG Query + Sprach-Klassifizierung PARALLEL ausführen (spart 1-2s)
    try:
        client_ip = "?"
        try:
            client_ip = request.client.host if request and request.client else "?"
        except Exception:
            client_ip = "?"
        logger.info(
            f"CHAT_RAG_CALL uid='{payload.user_id}' avatar='{payload.avatar_id}' top_k={payload.top_k} msg_len={len(payload.message or '')} ip='{client_ip}' message='{(payload.message or '').strip()[:200]}'"
        )
    except Exception:
        pass
    
    _tk = max(10, min(int(payload.top_k or 5), 20))
    
    # Parallel: RAG Query + Sprach-Klassifizierung
    def _run_rag_query():
        return memory_query(QueryRequest(
            user_id=payload.user_id,
            avatar_id=payload.avatar_id,
            query=payload.message,
            top_k=_tk,
        ))
    
    def _run_language_classification():
        return _classify_language(payload.message, payload.target_language)
    
    with ThreadPoolExecutor(max_workers=2) as executor:
        rag_future = executor.submit(_run_rag_query)
        lang_future = executor.submit(_run_language_classification)
        qres = rag_future.result()
        cls_result = lang_future.result()
    context_items = qres.results
    context_texts = []
    for it in context_items:
        md = it.get("metadata") or {}
        t = md.get("text")
        if t:
            context_texts.append(f"- {t}")
    effective_avatar_name = (payload.avatar_name or "").strip()
    if not effective_avatar_name:
        _nm = _read_avatar_name(payload.user_id, payload.avatar_id)
        if _nm:
            effective_avatar_name = _nm
    if context_texts:
        # bereite Namensvarianten vor (Vorname, Nachname, Spitzname, Frau <Nachname>)
        name_variants = []
        if effective_avatar_name:
            name_variants.append(effective_avatar_name)
        av_doc_name = _read_avatar_name(payload.user_id, payload.avatar_id)
        if av_doc_name and av_doc_name not in name_variants:
            name_variants.append(av_doc_name)
        try:
            # Höflichkeitsform aus Nachname ableiten (nur "Frau <Nachname>")
            last = None
            if name_variants:
                parts = name_variants[0].split()
                if len(parts) >= 2:
                    last = parts[-1]
            if last:
                name_variants.append(f"Frau {last}")
        except Exception:
            pass
        context_texts = _personalize_context_texts(context_texts, name_variants)
    context_block = "\n".join(context_texts) if context_texts else ""

    # PINECONE KONTEXT IMMER NUTZEN - keine Heuristik mehr
    # champion_q = re.search(r"weltmeister", msg, flags=re.IGNORECASE)
    # if champion_q:
    #     context_block = ""

    # 4) Prompt bauen (kurz & menschlich) + Ziel-Sprache (Logik: klare Fremdsprache > user-lang; Mischsätze -> user-lang)
    system = GPT_SYSTEM_PROMPT
    if effective_avatar_name:
        system = system + f" Dein Name ist {effective_avatar_name}."
    # Ohne Kontext: erlaube allgemeines Wissen statt "weiß ich nicht"
    if not context_block:
        system = (
            "Du bist der Avatar (Ich-Form, duzen). "
            "Korrigiere Tippfehler automatisch. "
            "Keine Meta-Hinweise zu Quellen/Kontext. "
            "Antworte kurz (1–2 Sätze) mit deinem allgemeinen Wissen. "
            "Bei sehr allgemeinem Prompt stelle genau EINE kurze Rückfrage. "
            "Antwortsprache = Sprache der Nutzerfrage; wenn unklar, Deutsch."
        )
    # Ziel-Sprache entscheiden
    reply_lang = None
    # Schneller Hard-Hit: Arabisch sofort erkennen (Unicode-Bereiche)
    _txt_all = payload.message or ""
    try:
        if any('\u0600' <= ch <= '\u06FF' for ch in _txt_all) or \
           any('\u0750' <= ch <= '\u077F' for ch in _txt_all) or \
           any('\u08A0' <= ch <= '\u08FF' for ch in _txt_all):
            reply_lang = 'ar'
    except Exception:
        pass

    try:
        # Nutze bereits parallel berechnetes Ergebnis
        cls = {"lang": reply_lang, "is_mixed": False} if reply_lang == 'ar' else cls_result
        user_lang = (payload.target_language or "").strip().lower()
        detected = (cls.get("lang") or "").strip().lower()
        is_mixed = bool(cls.get("is_mixed"))
        # Spezifische Korrektur für Spanisch: Satzzeichen/Diakritika erzwingen klares 'es'
        try:
            _txt = (payload.message or "")
            _has_span_punct = ("¿" in _txt) or ("¡" in _txt)
            _has_span_diac = any(ch in _txt for ch in "áéíóúñÁÉÍÓÚÑ")
            _has_span_words = any(w in _txt.lower() for w in [
                "hola", "gracias", "buenos", "buenas", "estoy", "porque", "por qué", "qué", "cómo", "hablas",
                "tiempo", "aquí", "genial", "muy", "mucho", "tú", "usted"
            ])
            if detected == "es" or _has_span_punct or _has_span_diac or _has_span_words:
                detected = "es"
                is_mixed = False if user_lang != "es" else is_mixed
        except Exception:
            pass
        # Entscheide: klare Fremdsprache > User-Sprache; Mischsätze -> User-Sprache
        if user_lang and detected and detected != user_lang and not is_mixed:
            reply_lang = detected
        elif user_lang:
            reply_lang = user_lang
    except Exception:
        reply_lang = (payload.target_language or "").strip().lower() or None
    # Debug-Log für Sprachentscheidung
    try:
        logger.info(
            f"CHAT_LANG_DECISION user_lang='{(payload.target_language or '').strip().lower()}' "
            f"detected='{(cls.get('lang') if 'cls' in locals() else None)}' "
            f"is_mixed='{(cls.get('is_mixed') if 'cls' in locals() else None)}' "
            f"reply_lang='{reply_lang}'"
        )
    except Exception:
        pass
    if reply_lang:
        system += f" Antworte stets in der Sprache '{reply_lang}'. Übersetze Inhalte falls nötig."
    user_msg = payload.message
    # Nutzername (wenn bekannt) als Gesprächskontext hinzunehmen, damit Avatar den Nutzer richtig adressiert
    try:
        known_user_name = _read_known_user_name(payload.user_id, payload.avatar_id)
        if known_user_name:
            system += f" Der Nutzer heißt {known_user_name}. Sprich ihn, wenn sinnvoll, mit seinem Namen an."
    except Exception:
        pass
    # Avatar-Rolle → Leitplanken
    try:
        role = _read_avatar_role(payload.user_id, payload.avatar_id) or ""
        r = role.lower()
        if r:
            if r == "explicit":
                system += (
                    " Du darfst auf einvernehmliche, erwachsene Sexualthemen eingehen,"
                    " bleib respektvoll, nicht beleidigend, keine illegalen Themen oder Minderjährigen,"
                    " keine detaillierten Handlungsanleitungen."
                )
            elif r in ("live_coach", "love_coach"):
                system += " Sprich als Coach: empathisch, konkret, kurze Schritte, eine klare Empfehlung."
            elif r in ("trauer",):
                system += " Sprich besonders einfühlsam und validierend (Trauerbegleitung)."
            elif r in ("verkaeufer", "berater"):
                system += " Fokussiere auf Bedarfsermittlung und klare Nutzenargumente."
            elif r in ("freund",):
                system += " Sprich locker und freundlich, wie ein guter Freund."
            elif r in ("lehrer_coach",):
                system += " Erkläre verständlich in kleinen Schritten; max. 1-2 Punkte."
            elif r in ("pfarrer",):
                system += " Antworte seelsorgerlich, diskret und ohne Wertung."
            elif r in ("psychiater", "seelsorger"):
                system += (
                    " Sei unterstützend; keine Diagnosen, keine medizinischen Ratschläge,"
                    " ermutige ggf. professionelle Hilfe."
                )
            elif r in ("medizinisch",):
                system += (
                    " Du gibst allgemeine medizinische Informationen, aber keine Diagnose/Behandlungsempfehlung;"
                    " verweise bei Risiko auf Ärztin/Arzt."
                )
    except Exception:
        pass
    if context_block:
        name_hint = (payload.avatar_name or "").strip()
        if not name_hint and effective_avatar_name:
            name_hint = effective_avatar_name
        name_clause = f" (dein Name: {name_hint})" if name_hint else ""
        user_msg = (
            f"Kontext:\n{context_block}\n\nFrage: {payload.message}\n"
            "Nutze den obigen Kontext vorrangig. Wenn der Kontext die Antwort nicht eindeutig enthält, beantworte korrekt mit deinem allgemeinen Wissen. "
            "Alles, was im Kontext in der dritten Person über dich steht, musst du strikt in Ich-Form umschreiben"
            f"{name_clause}. Erwähne deinen eigenen Namen nicht in der dritten Person."
        )
        system += " Wenn der Kontext konkrete Zahlen/Daten nennt (z. B. Anzahl, Jahreszahlen), nenne diese explizit."
    # PINECONE KONTEXT IMMER NUTZEN
    # if champion_q:
    #     user_msg += "\nHinweis: Gemeint ist der aktuell amtierende Weltmeister (Herren, sofern nicht 'Frauen' erwähnt). Antworte knapp: Land + Jahr des Titels."

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
            timeout=12,
        )
        answer = comp.choices[0].message.content.strip()  # type: ignore
        # Nachbearbeitung: konsequent Ich‑Form erzwingen (ersetzt Avatar‑Name → Ich)
        name_variants2 = []
        if effective_avatar_name:
            name_variants2.append(effective_avatar_name)
        av_doc_name2 = _read_avatar_name(payload.user_id, payload.avatar_id)
        if av_doc_name2 and av_doc_name2 not in name_variants2:
            name_variants2.append(av_doc_name2)
        try:
            parts = (name_variants2[0].split() if name_variants2 else [])
            if len(parts) >= 2:
                last = parts[-1]
                name_variants2.append(f"Frau {last}")
        except Exception:
            pass
        answer = _rewrite_avatar_pronouns(answer, name_variants2)

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

        fact_candidates: list[Dict[str, Any]] = []
        chat_id = None
        try:
            # Frontend speichert Messages! Backend speichert NUR Facts/Pinecone
            chat_id = f"{payload.user_id}_{payload.avatar_id}"

            # Fakten-Extraktion asynchron (blockiert Chat nicht)
            if os.getenv("CHAT_FACT_SCANNER", "1") == "1":
                def _run_fact_extraction():
                    try:
                        extracted = _extract_chat_facts(
                            user_id=payload.user_id,
                            avatar_id=payload.avatar_id,
                            source_message_id=avatar_msg_id,
                            user_text=payload.message,
                            avatar_text=answer,
                        )
                        for fact in extracted:
                            if not _should_store_fact(fact):
                                logger.info("CHAT_FACT_SKIP text='%s'", fact.get('fact_text'))
                                continue
                            stored = _store_chat_fact(
                                user_id=payload.user_id,
                                avatar_id=payload.avatar_id,
                                source_message_id=fact.get("source_message_id") or avatar_msg_id,
                                fact_text=fact.get("fact_text", ""),
                                confidence=float(fact.get("confidence", 0.6)),
                                scope=str(fact.get("scope", "avatar")),
                            )
                            if stored:
                                logger.info(
                                    "CHAT_FACT_FOUND uid='%s' avatar='%s' fact_id='%s' text='%s' conf=%.2f",
                                    payload.user_id,
                                    payload.avatar_id,
                                    stored.get("fact_id"),
                                    stored.get("fact_text"),
                                    stored.get("confidence", 0.0),
                                )
                    except Exception as _fe:
                        logger.warning(f"CHAT_FACT_SCANNER Fehler: {_fe}")
                threading.Thread(target=_run_fact_extraction, daemon=True).start()

            # Chat-Storage in Pinecone asynchron (optional, blockiert nicht)
            if os.getenv("STORE_CHAT_IN_PINECONE", "0") == "1":
                def _run_pinecone_storage():
                    try:
                        _store_chat_in_pinecone(payload.user_id, payload.avatar_id, payload.message, answer)
                    except Exception as e:
                        logger.warning(f"Chat Pinecone Storage Fehler: {e}")
                threading.Thread(target=_run_pinecone_storage, daemon=True).start()

        except Exception as e:
            logger.warning(f"Chat-Storage Fehler: {e}")
            chat_id = None

        return ChatResponse(
            answer=answer,
            used_context=context_items,
            tts_audio_b64=tts_b64,
            chat_id=chat_id,
            fact_candidates=fact_candidates or None,
        )
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


# Avatar Info (z. B. Bild-URL) für Agent/Client
class AvatarInfoRequest(BaseModel):
    user_id: str
    avatar_id: str

class AvatarInfoResponse(BaseModel):
    avatar_image_url: str | None = None

@app.post("/avatar/info", response_model=AvatarInfoResponse)
def get_avatar_info(payload: AvatarInfoRequest) -> AvatarInfoResponse:
    try:
        if not FIREBASE_AVAILABLE or not db:
            return AvatarInfoResponse(avatar_image_url=None)
        doc = db.collection("users").document(payload.user_id).collection("avatars").document(payload.avatar_id).get()
        data = doc.to_dict() or {}
        url = None
        try:
            url = (data.get("avatarImageUrl") or data.get("avatar_image_url") or "")
            if isinstance(url, str):
                url = url.strip() or None
            else:
                url = None
        except Exception:
            url = None
        return AvatarInfoResponse(avatar_image_url=url)
    except Exception as e:
        logger.warning(f"Avatar Info Fehler: {e}")
        return AvatarInfoResponse(avatar_image_url=None)


def _read_avatar_name(user_id: str, avatar_id: str) -> str | None:
    if not FIREBASE_AVAILABLE or not db:
        return None
    try:
        doc = db.collection("users").document(user_id).collection("avatars").document(avatar_id).get()
        data = doc.to_dict() or {}
        first = (data.get("firstName") or "").strip()
        nick = (data.get("nickname") or "").strip()
        last = (data.get("lastName") or "").strip()
        if nick:
            return nick
        if first and last:
            return f"{first} {last}"
        if first:
            return first
        return None
    except Exception:
        return None


def _read_avatar_role(user_id: str, avatar_id: str) -> str | None:
    if not FIREBASE_AVAILABLE or not db:
        return None
    try:
        doc = db.collection("avatars").document(avatar_id).get()
        data = doc.to_dict() or {}
        role = data.get("role")
        if isinstance(role, str) and role.strip():
            return role.strip().lower()
        return None
    except Exception:
        return None


class FactListRequest(BaseModel):
    user_id: str
    avatar_id: str
    status: str = "pending"
    limit: int = 20
    cursor: Optional[int] = None


class FactHistoryEntry(BaseModel):
    action: str
    at: int
    by: Optional[str] = None
    note: Optional[str] = None


class FactItem(BaseModel):
    fact_id: str
    fact_text: str
    confidence: float
    scope: str
    status: str
    created_at: int
    updated_at: int
    author_email: Optional[str] = None
    author_display_name: Optional[str] = None
    author_hash: Optional[str] = None
    history: Optional[List[FactHistoryEntry]] = None
    # NEU: Klassifikation für robuste Review-Entscheidungen
    claim_type: Optional[str] = None   # statement | assumption | question | joke | quote
    polarity: Optional[str] = None     # affirmative | negative
    certainty: Optional[float] = None  # 0..1
    subject: Optional[str] = None      # avatar | user
    extracted_from: Optional[str] = None  # user | avatar
    source_message_id: Optional[str] = None


class FactListResponse(BaseModel):
    items: List[FactItem]
    has_more: bool
    next_cursor: Optional[int] = None


class FactUpdateRequest(BaseModel):
    user_id: str
    avatar_id: str
    fact_id: str
    new_status: str
    note: Optional[str] = None


class FactUpdateResponse(BaseModel):
    fact: FactItem


def _fact_doc_to_item(doc: Dict[str, Any]) -> FactItem:
    return FactItem(
        fact_id=str(doc.get("fact_id")),
        fact_text=str(doc.get("fact_text", "")),
        confidence=float(doc.get("confidence", 0.0)),
        scope=str(doc.get("scope", "avatar")),
        status=str(doc.get("status", "pending")),
        created_at=int(doc.get("created_at", 0)),
        updated_at=int(doc.get("updated_at", doc.get("created_at", 0))),
        author_email=doc.get("author_email"),
        author_display_name=doc.get("author_display_name"),
        author_hash=doc.get("author_hash"),
        history=[FactHistoryEntry(**entry) for entry in (doc.get("history") or []) if isinstance(entry, dict)],
        claim_type=doc.get("claim_type"),
        polarity=doc.get("polarity"),
        certainty=float(doc.get("certainty", 0.0)) if doc.get("certainty") is not None else None,
        subject=doc.get("subject"),
        extracted_from=doc.get("extracted_from"),
        source_message_id=doc.get("source_message_id"),
    )


# Fakten-Review: Liste
@app.post("/avatar/facts/list", response_model=FactListResponse)
def list_avatar_facts(payload: FactListRequest) -> FactListResponse:
    if not FIREBASE_AVAILABLE or not db:
        # Fallback: leere Liste statt Fehler, damit Frontend nicht crasht
        return FactListResponse(items=[], has_more=False, next_cursor=None)
    try:
        # Versuche Indexierte Query (schnell)
        try:
            query = (
                db.collection("avatarFactsQueue")
                .where("avatar_id", "==", payload.avatar_id)
                .where("status", "==", payload.status)
                .order_by("created_at", direction=firestore.Query.DESCENDING)
            )
            if payload.cursor:
                query = query.where("created_at", "<", payload.cursor)
            docs = query.limit(payload.limit + 1).get()
            def _to_items(docs_):
                items_: list[FactItem] = []
                for idx, d in enumerate(docs_):
                    if idx >= payload.limit:
                        break
                    data = d.to_dict() or {}
                    items_.append(_fact_doc_to_item(data))
                return items_
            items = _to_items(docs)
            has_more = len(docs) > payload.limit
            next_cursor = None
            if has_more:
                last_doc = docs[payload.limit - 1]
                last_data = last_doc.to_dict() or {}
                next_cursor = int(last_data.get("created_at", 0))
            return FactListResponse(items=items, has_more=has_more, next_cursor=next_cursor)
        except Exception as idx_err:
            # Fallback ohne Composite-Index: nur nach avatar_id filtern und lokal sortieren/filtern
            if _is_index_missing_error(idx_err):
                raw_docs = (
                    db.collection("avatarFactsQueue")
                    .where("avatar_id", "==", payload.avatar_id)
                    .limit(500)
                    .get()
                )
                rows = []
                for d in raw_docs:
                    data = d.to_dict() or {}
                    if str(data.get("status", "")).lower() != str(payload.status or "").lower():
                        continue
                    rows.append(data)
                rows.sort(key=lambda x: int(x.get("created_at", 0)), reverse=True)
                if payload.cursor:
                    rows = [r for r in rows if int(r.get("created_at", 0)) < int(payload.cursor)]
                slice_rows = rows[: payload.limit]
                items = [_fact_doc_to_item(r) for r in slice_rows]
                has_more = len(rows) > len(slice_rows)
                next_cursor = int(slice_rows[-1].get("created_at", 0)) if slice_rows else None
                logger.warning("Fact-List: unindexierter Fallback aktiv – bitte Composite-Index deployen")
                return FactListResponse(items=items, has_more=has_more, next_cursor=next_cursor)
            else:
                raise
    except Exception as e:
        # Wenn der Fehler sehr wahrscheinlich "Index fehlt" ist → leere Liste zurückgeben
        if _is_index_missing_error(e):
            logger.warning("Fact-List: fehlender Firestore-Index – liefere leere Liste")
            return FactListResponse(items=[], has_more=False, next_cursor=None)
        logger.exception("Fact-List Fehler")
        raise HTTPException(status_code=500, detail=f"Fact-List Fehler: {e}")


# Optionaler Alias als GET (zur leichteren Diagnose im Browser)
@app.get("/avatar/facts/list")
def list_avatar_facts_get(user_id: str, avatar_id: str, status: str = "pending", limit: int = 20, cursor: Optional[int] = None) -> FactListResponse:
    return list_avatar_facts(FactListRequest(user_id=user_id, avatar_id=avatar_id, status=status, limit=limit, cursor=cursor))


# Fakten-Review: Status ändern
@app.post("/avatar/facts/update", response_model=FactUpdateResponse)
def update_avatar_fact(payload: FactUpdateRequest) -> FactUpdateResponse:
    if not FIREBASE_AVAILABLE or not db:
        raise HTTPException(status_code=500, detail="Firestore nicht verfügbar")
    try:
        fact_ref = db.collection("avatarFactsQueue").document(payload.fact_id)
        snap = fact_ref.get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Fact nicht gefunden")

        data = snap.to_dict() or {}
        if data.get("user_id") != payload.user_id or data.get("avatar_id") != payload.avatar_id:
            raise HTTPException(status_code=403, detail="Zugriff verweigert")

        ts = int(time.time() * 1000)
        history = data.get("history") or []
        if not isinstance(history, list):
            history = []
        history.append({
            "action": payload.new_status,
            "at": ts,
            "by": _anonymize_user_id(payload.user_id),
            "note": payload.note,
        })

        updates = {
            "status": payload.new_status,
            "updated_at": ts,
            "history": history,
        }
        # Aktionen mit Pinecone
        try:
            if payload.new_status == "approved":
                # In Pinecone unter Namespace des Avatars speichern (kein Text-File, spezieller Typ)
                namespace = f"{payload.user_id}_{payload.avatar_id}"
                index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
                ensure_index_exists(
                    pc=pc,
                    index_name=index_name,
                    dimension=EMBEDDING_DIM,
                    metric="cosine",
                    cloud=PINECONE_CLOUD,
                    region=PINECONE_REGION,
                )
                emb_list, real_dim = _create_embeddings_with_timeout([data.get("fact_text", "")], EMBEDDING_MODEL, timeout_sec=10)
                vec_id = f"fact-{payload.fact_id}"
                vec = {
                    "id": vec_id,
                    "values": emb_list[0],
                    "metadata": {
                        "type": "approved_fact",
                        "fact_id": payload.fact_id,
                        "user_id": payload.user_id,
                        "avatar_id": payload.avatar_id,
                        "text": data.get("fact_text", ""),
                        "created_at": ts,
                        "source": "fact_review",
                    },
                }
                upsert_vector(pc, index_name, namespace, vec)
                updates["vector_id"] = vec_id
            elif payload.new_status == "deleted":
                # Entferne den Vektor wieder, falls vorhanden
                namespace = f"{payload.user_id}_{payload.avatar_id}"
                index_name = _pinecone_index_for(payload.user_id, payload.avatar_id)
                try:
                    # Lösche per Filter auf type & fact_id
                    delete_by_filter(
                        pc=pc,
                        index_name=index_name,
                        namespace=namespace,
                        flt={"$and": [
                            {"type": {"$eq": "approved_fact"}},
                            {"fact_id": {"$eq": payload.fact_id}},
                        ]},
                    )
                except Exception:
                    pass
        except Exception as _px:
            logger.warning(f"Pinecone-Update beim Fact-Statuswechsel fehlgeschlagen: {_px}")

        fact_ref.update(updates)

        merged = {**data, "status": payload.new_status, "updated_at": ts, "history": history}
        if "vector_id" in updates:
            merged["vector_id"] = updates["vector_id"]
        return FactUpdateResponse(fact=_fact_doc_to_item(merged))
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Fact-Update Fehler")
        raise HTTPException(status_code=500, detail=f"Fact-Update Fehler: {e}")

