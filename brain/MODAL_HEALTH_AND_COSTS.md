## Modal Health-Checks, Kaltstart & Kosten

### Endpoints
- Orchestrator (CPU): `GET /health` → `https://romeo1971--lipsync-orchestrator-asgi.modal.run/health`
- MuseTalk (GPU): `GET /health` → `https://romeo1971--musetalk-lipsync-asgi.modal.run/health`
- LivePortrait WS (GPU): `GET /health` → `https://romeo1971--liveportrait-ws-asgi.modal.run/health`

### Beobachtung
- Aktuell sieht man im Modal-Dashboard automatisch alle ~2–3 Minuten `GET /health` Aufrufe (siehe Screenshot). Das sind externe Checks von Modal/Infra, keine App-internen Timer.
- Unsere App führt keine periodischen Pings an den Orchestrator aus (nur manuelle Tests/Docs). Kaltstartzeiten ~2–3s sind normal bei `min_containers=0`.

### Best Practices (Kosten senken)
- Beibehalten: `min_containers=0` und `scaledown_window` ≤ 60s.
- Keine eigenen Cron-Pings auf `/health` in der App oder externem Uptime-Monitor (würde Container wachhalten und Kosten erzeugen).
- Für kurze Texte (Begrüßung): HTTP-MP3 (`/tts/stream`) verwenden; PCM/WS nur bei aktivem Room (Flag `pcm: true`).
- WebSocket nach `done` schließen, damit Scale-to-zero greift.

### Optional: Schnellere Reaktionszeit ohne Dauerbetrieb
- „Warmup“ nur on-demand kurz vor erwarteter Nutzung: einmaliger `GET /health` oder ein leerer `HEAD` reicht. Nicht wiederholen.
- Akzeptieren: 2–3s Kaltstart sind günstiger als Container warm halten.

### Troubleshooting
- Wenn im Dashboard Health-Aufrufe sehr häufig sind (<60s):
  - Uptime-Monitor/Probe abschalten.
  - In App/CI nach `Timer.periodic`/`cron` suchen, die Modal-URLs pingen.
- Wenn Container nicht skaliert:
  - `min_containers` in der App-Definition prüfen (alle 0).
  - Offene WS-Verbindungen schließen (Client „stop“ senden).

### Referenzen
- App-Definition: `orchestrator/modal_app.py`
- ASGI: `orchestrator/py_asgi_app.py`
- Flutter WS-Client: `lib/services/lipsync/streaming_strategy.dart`

