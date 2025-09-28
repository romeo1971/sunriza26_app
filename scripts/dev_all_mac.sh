#!/usr/bin/env bash
# Startet Backend, Agent und Flutter-App in separaten Terminal-Tabs (macOS)
# Killt vorher ggf. laufende Prozesse

set -e

echo "KILLALL …"
pkill -f "uvicorn.*backend.app.main" || true
lsof -ti tcp:8000 | xargs -r kill -9 || true
pkill -f "basic-mcp/agent.py" || true
pkill -f "flutter_tools" || true
pkill -f "dart .*flutter" || true

# Pfade
BACKEND_DIR="/Users/hhsw/Desktop/sunriza/sunriza26"
AGENT_DIR="/Users/hhsw/Desktop/sunriza/chatAgent/basic-mcp"

# Befehle
BACKEND_CMD="cd $BACKEND_DIR; uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload"
AGENT_CMD="cd $AGENT_DIR; python3 agent.py console"
APP_CMD="cd $BACKEND_DIR; flutter run"

echo "Starte Terminal-Tabs …"
osascript <<APPLESCRIPT
tell application "Terminal"
  activate

  do script "${BACKEND_CMD}"
  delay 1

  tell application "System Events" to keystroke "t" using command down
  do script "${AGENT_CMD}" in front window
  delay 1

  tell application "System Events" to keystroke "t" using command down
  do script "${APP_CMD}" in front window
end tell
APPLESCRIPT

echo "Fertig. Tabs offen: Backend, Agent, Flutter."


