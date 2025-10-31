#!/bin/bash
# update_secrets.sh - Zentrale Secret-Verwaltung für Modal Apps
# Verwendung: ./update_secrets.sh

set -e  # Bei Fehler abbrechen

echo "🔑 Modal Secrets aktualisieren..."
echo ""

# 1. ElevenLabs API Key
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  ElevenLabs API Key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Neuer ElevenLabs API Key (oder Enter zum Überspringen): " ELEVEN_KEY
if [ -n "$ELEVEN_KEY" ]; then
  echo "   → Lösche altes Secret..."
  modal secret delete lipsync-eleven 2>/dev/null || true
  echo "   → Erstelle neues Secret..."
  modal secret create lipsync-eleven ELEVENLABS_API_KEY="$ELEVEN_KEY"
  echo "   ✅ lipsync-eleven aktualisiert"
else
  echo "   ⏭️  Übersprungen"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Apps neu deployen (mit aktualisierten Secrets)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 2. Orchestrator (lipsync + ElevenLabs Proxy)
echo "📦 Deploye: lipsync-orchestrator..."
modal deploy orchestrator/modal_app.py

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ FERTIG! Alle Secrets + Apps aktualisiert"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

