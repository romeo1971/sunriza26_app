#!/bin/bash
# Deploy all Modal Apps
# Run: bash deploy_all_modal.sh

set -e  # Exit on error

echo "🚀 Deploying all Modal Apps..."
echo ""

echo "1️⃣ BitHuman Worker (MAIN)"
echo "================================"
modal deploy modal_bithuman_worker.py
echo ""

echo "2️⃣ Lipsync Orchestrator"
echo "================================"
modal deploy orchestrator/modal_app.py
echo ""

echo "3️⃣ Sunriza Dynamics"
echo "================================"
modal deploy modal_dynamics.py
echo ""

echo "4️⃣ LivePortrait WebSocket"
echo "================================"
modal deploy modal_liveportrait_ws.py
echo ""

echo "✅ Alle Apps deployed!"
echo ""
echo "🔍 Check Secrets:"
echo "  curl https://romeo1971--bithuman-worker-check-secrets.modal.run | python3 -m json.tool"
echo "  curl https://romeo1971--lipsync-orchestrator-check-secrets.modal.run | python3 -m json.tool"





