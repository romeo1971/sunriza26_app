# Laufende Aufgabenliste (Agent & App)

Stand: 26.09.2025

- [x] Implementiere ElevenLabs-TTS im chatAgent (Adapter, Env, Fallback)
- [x] Baue MCP-Pinecone-Tools in chatAgent (Phase A via Backend HTTP)
- [x] Dokumentiere Env/README für chatAgent (ELEVENLABS, BACKEND_BASE_URL, LIVEKIT)
- [ ] Nutze im Editor nur Backend-Endpunkte für TTS/Voice-Clone (kein Client-Key)
- [ ] Stabilisiere Backend Pinecone-APIs (Query/Insert) für Agent-Aufrufe
- [ ] Synchronisiere Voice-State (voice_id, stability, similarity) zentral speichern
- [ ] Observability: Latenzmetriken für TTS und Pinecone (p95) erfassen
- [ ] Integriere Firebase-Chat-Speicherung im chatAgent (Backend-Webhook oder Admin SDK)
- [ ] Baue MCP-Pinecone-Tools Phase B (direktes SDK, Parität zu Backend)
- [ ] Evaluiere/entscheide Pinecone-Assistant vs. einfache Tools (Scope, Latenz, Wartung)

## Nächster Schritt
- Strikter MCP‑Pfad: Chat über Backend `/avatar/chat` via Agent‑Tool; keine App‑Flow‑Änderungen.
