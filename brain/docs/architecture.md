# Sunriza26 – Architekturentscheidungen & Integrationsleitfaden (26.09.2025)

## Kontext
- App: Flutter (`lib/…`) mit Avatar‑Details, ElevenLabs‑Service und LiveKit‑Integration (`avatar_chat_screen.dart`).
- Backend: FastAPI (`backend/app/main.py`) mit Pinecone (Insert/Query mit Timeouts), Chat‑Endpoint (`/avatar/chat`), ElevenLabs TTS & Voice‑Clone, LiveKit Token, Latenz‑Metriken `/metrics/latency`.
- Agent: Separates Repo `chatAgent` (LiveKit + MCP) liefert Voice‑/Streaming‑Funktionen, MCP‑Tools (HTTP zu Backend; optional SDK‑Query per Flag).

## Entscheidungen
1) ElevenLabs TTS
- Live‑Chat‑Audio kommt zentral aus Agent/Backend. Client vermeidet direkte Keys; Voices via Backend‑Proxy `/avatar/voices`.
- `/avatar/tts` bleibt als Fallback (Base64 MP3) für Client‑Wiedergabe und BitHuman‑Lipsync.

2) Pinecone Nutzung
- Autoritativer Pfad im Backend: Chunking, Namespace‑Strategie, Debug‑Upsert, Deletes.
- Agent nutzt MCP‑Tools:
  - Phase A: HTTP → `/avatar/memory/query|insert|delete/by-file` (stabil, wiederverwendet Logik).
  - Phase B: optional direktes SDK‑Query‑Tool (Flag `AGENT_PINECONE_SDK=1`), Parität bleibt im Backend.
- Kein Pinecone‑Assistant. Entscheidung: einfache Tools genügen (Latenz/Scope/Wartung).

3) Chat‑Invocation & Persistenz
- Textchat: `/avatar/chat` orchestriert RAG + Antwort + optionales TTS und speichert Chat zentral (Firestore) über Backend‑Pfad.
- Voice/Avatar‑Chat: LiveKit‑Session; Agent aktiv nur während Join→Leave.

4) Observability
- Middleware setzt `X-Response-Time-ms` und loggt Latenzen.
- Rolling‑Window Metriken pro Pfad unter `/metrics/latency` (count, min, p50, p95, p99, max).
- Pinecone‑Query & Embeddings laufen mit harten Timeouts.

5) Voice‑State
- Zentrale Voice‑Parameter (elevenVoiceId, stability, similarity, tempo, dialect) in Firestore unter `users/<uid>/avatars/<avatarId>.training.voice`.
- Endpoints: `/avatar/voice/create`, `/avatar/voice/state/get`, `/avatar/voice/state/set`.

## Relevante Endpoints (Backend FastAPI)
- `GET /health` – Liveness
- `GET /metrics/latency` – p50/p95/p99 je Pfad (Rolling Window)
- `GET /avatar/voices` – ElevenLabs‑Proxy (ohne Client‑Key)
- `POST /avatar/voice/create` – Stimme aus Audio erstellen/ersetzen (mit Cleanup)
- `POST /avatar/voice/state/get` – Voice‑State aus Firestore
- `POST /avatar/voice/state/set` – Voice‑State setzen
- `POST /avatar/tts` – TTS (Base64)
- `POST /avatar/memory/insert` – Pinecone Insert (Chunking + Upsert)
- `POST /avatar/memory/query` – Pinecone Query (Timeouts)
- `POST /avatar/memory/delete/by-file` – Delete nach Datei‑Metadaten
- `POST /avatar/chat` – RAG‑Antwort + optional TTS + zentrale Chat‑Persistenz
- `POST /livekit/token` – Token für Flutter LiveKit Join

## Flags & Umgebungsvariablen (Auszug)
- LiveKit: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- Pinecone: `PINECONE_API_KEY`, `PINECONE_INDEX`, `PINECONE_INDEX_MODE`, `PINECONE_CLOUD`, `PINECONE_REGION`
- OpenAI: `OPENAI_API_KEY`, `EMBEDDING_MODEL`
- ElevenLabs: `ELEVENLABS_API_KEY`, `ELEVEN_VOICE_ID`, `ELEVEN_TTS_MODEL`, `ELEVEN_STABILITY`, `ELEVEN_SIMILARITY`
- Agent (Repo chatAgent): `USE_ELEVENLABS_TTS`, `AGENT_PINECONE_SDK`
- App (Flutter): `LIVEKIT_ENABLED`, `MEMORY_API_BASE_URL`

## DoD Ausschnitte
- Chat über `/avatar/chat` speichert in Firestore; p95 < 250 ms für Pinecone‑Query; TTS‑Start < 2s.

