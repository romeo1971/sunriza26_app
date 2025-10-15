#!/bin/bash
# Startet das Avatar FastAPI Backend

# Aktuelles Verzeichnis des Skripts
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Aktiviere das Python Virtual Environment
source "$PROJECT_ROOT/venv/bin/activate"

# Installiere Dependencies falls nötig
echo "📦 Installiere Python Dependencies..."
pip install -r "$SCRIPT_DIR/requirements.txt"

# Erstelle avatars Verzeichnis
mkdir -p "$SCRIPT_DIR/avatars"

# Starte den FastAPI Server
echo "🚀 Starte Avatar FastAPI Backend..."
echo "📡 Backend läuft auf: http://localhost:8001"
echo "📚 API Docs: http://localhost:8001/docs"
echo ""
echo "Drücke Ctrl+C zum Beenden"
echo ""

uvicorn avatar_backend:app --host 0.0.0.0 --port 8001 --reload
