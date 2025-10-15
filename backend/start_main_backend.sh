#!/bin/bash
# Startet das Main FastAPI Backend (Port 8002)
# Endpoints: /generate-dynamics, /trim-video

# Aktuelles Verzeichnis des Skripts
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Aktiviere das Python Virtual Environment
source "$PROJECT_ROOT/venv/bin/activate"

# Setze Umgebungsvariablen für Produktion (optional)
# export LIVEPORTRAIT_PATH="/path/to/liveportrait/inference.py"

# Erstelle temporäres Verzeichnis
mkdir -p /tmp

# Starte den FastAPI Server
echo "🚀 Starte Main FastAPI Backend..."
echo "📡 Backend läuft auf: http://localhost:8002"
echo "📚 API Docs: http://localhost:8002/docs"
echo ""
echo "Endpoints:"
echo "  POST /generate-dynamics - Generiert Dynamics (LivePortrait)"
echo "  POST /trim-video - Trimmt Videos (ffmpeg)"
echo ""
echo "Drücke Ctrl+C zum Beenden"
echo ""

cd "$SCRIPT_DIR"
uvicorn main:app --host 0.0.0.0 --port 8002 --reload


