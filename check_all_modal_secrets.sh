#!/bin/bash
# Check all Modal Apps Secrets
# Run: bash check_all_modal_secrets.sh

echo "🔍 Checking all Modal Apps Secrets..."
echo ""

echo "1️⃣ BitHuman Worker"
echo "================================"
curl -s https://romeo1971--bithuman-worker-check-secrets.modal.run | python3 -m json.tool
echo ""
echo ""

echo "2️⃣ Lipsync Orchestrator"
echo "================================"
curl -s https://romeo1971--lipsync-orchestrator-check-secrets.modal.run | python3 -m json.tool
echo ""
echo ""

echo "3️⃣ Sunriza Dynamics"
echo "================================"
curl -s https://romeo1971--sunriza-dynamics-check-secrets.modal.run | python3 -m json.tool
echo ""
echo ""

echo "4️⃣ LivePortrait WebSocket"
echo "================================"
curl -s https://romeo1971--liveportrait-ws-check-secrets.modal.run | python3 -m json.tool
echo ""
echo ""

echo "✅ Alle Apps geprüft!"





