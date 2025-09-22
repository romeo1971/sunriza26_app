#!/bin/bash

# BitHuman Backend Start-Script
# Startet das offizielle BitHuman Backend

echo "🚀 Starte BitHuman Backend..."

# Projektwurzel setzen
PROJECT_ROOT="/Users/hhsw/Desktop/sunriza26"
cd "$PROJECT_ROOT"

# .env laden, falls vorhanden
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Virtual Environment aktivieren
source venv/bin/activate

# Absoluten IMX-Pfad setzen (falls Datei existiert)
IMX_FILE="$PROJECT_ROOT/avatars/relationship_confidence_coach_20250921_145206_822438.imx"
if [ -f "$IMX_FILE" ]; then
  export BITHUMAN_IMX_PATH="$IMX_FILE"
  echo "🧠 Verwende BITHUMAN_IMX_PATH=$BITHUMAN_IMX_PATH"
else
  echo "⚠️ IMX-Datei nicht gefunden: $IMX_FILE"
fi

# Backend starten
cd backend
python bithuman_service.py
