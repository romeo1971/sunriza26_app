# Laufende Aufgabenliste (Agent & App)

Stand: 26.09.2025

- [x] Implementiere ElevenLabs-TTS im chatAgent (Adapter, Env, Fallback)
- [x] Baue MCP-Pinecone-Tools in chatAgent (Phase A via Backend HTTP)
- [x] Dokumentiere Env/README für chatAgent (ELEVENLABS, BACKEND_BASE_URL, LIVEKIT)
 - [x] Nutze im Editor nur Backend-Endpunkte für TTS/Voice-Clone (kein Client-Key)
 - [x] Stabilisiere Backend Pinecone-APIs (Query/Insert) für Agent-Aufrufe
 - [x] Synchronisiere Voice-State (voice_id, stability, similarity) zentral speichern
 - [x] Observability: Latenzmetriken für TTS und Pinecone (p95) erfassen
 - [~] Firebase-Chat-Speicherung im chatAgent entfällt – Speicherung erfolgt zentral im Backend `/avatar/chat`
- [ ] Baue MCP-Pinecone-Tools Phase B (direktes SDK, Parität zu Backend)
- [~] Pinecone-Assistant Evaluierung entfällt – Entscheidung: wir bleiben bei Tools (kein Assistant)

## Nächster Schritt
- Strikter MCP‑Pfad: Chat über Backend `/avatar/chat` via Agent‑Tool; keine App‑Flow‑Änderungen.
