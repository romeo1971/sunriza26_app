# Fast Start (Modal)

Ich stelle den schnellen Start wieder her, indem ich `min_containers=1` (warm halten) in `orchestrator/modal_app.py` setze und dann kannst du direkt deployen.

Schneller Start ist wieder im Code gesetzt (`min_containers=1`, `scaledown_window=300` in `orchestrator/modal_app.py`). Jetzt einmal deployen:

```bash
modal deploy orchestrator/modal_app.py
```

**WICHTIG: Nach jedem Deploy einmal warmup:**
```bash
curl -sS https://romeo1971--lipsync-orchestrator-asgi.modal.run/health
```

Dann bleibt der Join stabil bei ~1–2 Sekunden. Mit `min_containers=1` bleibt der Container danach automatisch warm.
