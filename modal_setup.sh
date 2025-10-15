#!/bin/bash
# Modal.com Quick Setup für Sunriza26

set -e

echo "🚀 Modal.com Setup für Sunriza26 Dynamics"
echo ""

# 1. Modal installieren
echo "📦 Installiere Modal..."
pip install modal

# 2. Modal Auth
echo ""
echo "🔐 Modal Auth - Browser wird geöffnet..."
modal setup

# 3. Secret erstellen
echo ""
echo "🔑 Firebase Secret erstellen..."
echo "Bitte gehe zu: https://modal.com/secrets"
echo "1. Klicke 'New Secret'"
echo "2. Name: firebase-credentials"
echo "3. Type: Custom"
echo "4. Key: FIREBASE_CREDENTIALS"
echo "5. Value: Inhalt von service-account-key.json"
echo ""
read -p "Secret erstellt? (Enter drücken)"

# 4. Deploy
echo ""
echo "🚀 Deploye Service..."
modal deploy modal_dynamics.py

echo ""
echo "✅ FERTIG!"
echo ""
echo "Deine URLs:"
modal app show sunriza-dynamics

echo ""
echo "📖 Mehr Infos: cat MODAL_SETUP.md"

