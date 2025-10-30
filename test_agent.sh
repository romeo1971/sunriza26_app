#!/bin/bash
# BitHuman Agent Test Script
# ==========================

set -e

echo "🧪 BitHuman Agent Test Suite"
echo "=============================="
echo ""

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Modal URL (anpassen nach Deployment!)
MODAL_URL="${MODAL_URL:-https://romeo1971--bithuman-complete-agent-join.modal.run}"

echo "📍 Modal URL: $MODAL_URL"
echo ""

# Test 1: Health Check
echo "1️⃣ Health Check..."
if curl -sf "${MODAL_URL}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Health Check OK${NC}"
    curl -s "${MODAL_URL}/health" | python3 -m json.tool
else
    echo -e "${RED}❌ Health Check FAILED${NC}"
    exit 1
fi
echo ""

# Test 2: Agent Start (Test Room)
echo "2️⃣ Agent Start Test..."
RESPONSE=$(curl -sf -X POST "${MODAL_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "room": "test-room-'$(date +%s)'",
        "agent_id": "A91XMB7113"
    }' 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Agent Start Request OK${NC}"
    echo "$RESPONSE" | python3 -m json.tool
else
    echo -e "${RED}❌ Agent Start FAILED${NC}"
    echo "$RESPONSE"
    exit 1
fi
echo ""

# Test 3: Modal Secrets Check
echo "3️⃣ Modal Secrets Check..."
echo -e "${YELLOW}⚠️ Prüfe manuell in Modal Dashboard:${NC}"
echo "   modal secret list"
echo ""
echo "   Erwartete Secrets:"
echo "   - livekit-cloud"
echo "   - bithuman-api"
echo "   - openai-api"
echo "   - elevenlabs-api"
echo "   - pinecone-api"
echo "   - firebase-admin"
echo ""

# Test 4: Firebase Connection (lokal)
echo "4️⃣ Firebase Connection Test..."
if [ -f "backend/.env" ]; then
    source backend/.env
    if [ -n "$FIREBASE_CREDENTIALS_PATH" ] && [ -f "$FIREBASE_CREDENTIALS_PATH" ]; then
        echo -e "${GREEN}✅ Firebase Credentials gefunden${NC}"
    else
        echo -e "${YELLOW}⚠️ Firebase Credentials nicht gefunden (OK wenn Modal Secret existiert)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ backend/.env nicht gefunden${NC}"
fi
echo ""

# Test 5: Pinecone Connection (lokal)
echo "5️⃣ Pinecone Connection Test..."
if [ -n "$PINECONE_API_KEY" ]; then
    echo -e "${GREEN}✅ Pinecone API Key gefunden${NC}"
    echo "   Index: ${PINECONE_INDEX_NAME:-sunriza-knowledge}"
else
    echo -e "${YELLOW}⚠️ Pinecone API Key nicht gefunden (OK wenn Modal Secret existiert)${NC}"
fi
echo ""

# Test 6: ElevenLabs Connection
echo "6️⃣ ElevenLabs Connection Test..."
if [ -n "$ELEVENLABS_API_KEY" ]; then
    VOICES=$(curl -sf "https://api.elevenlabs.io/v1/voices" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ElevenLabs API OK${NC}"
        echo "$VOICES" | python3 -c "import sys, json; data=json.load(sys.stdin); print(f\"   Voices: {len(data.get('voices', []))}\")"
    else
        echo -e "${YELLOW}⚠️ ElevenLabs API Check fehlgeschlagen (OK wenn Modal Secret existiert)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ ElevenLabs API Key nicht gefunden (OK wenn Modal Secret existiert)${NC}"
fi
echo ""

# Zusammenfassung
echo "=============================="
echo "🎯 Test Summary"
echo "=============================="
echo -e "${GREEN}✅ Health Check: OK${NC}"
echo -e "${GREEN}✅ Agent Start: OK${NC}"
echo ""
echo "📝 Next Steps:"
echo "   1. Prüfe Modal Logs: modal app logs bithuman-complete-agent"
echo "   2. Teste in Flutter App"
echo "   3. Checke Avatar in LiveKit Dashboard"
echo ""
echo "🚀 Ready to go!"

