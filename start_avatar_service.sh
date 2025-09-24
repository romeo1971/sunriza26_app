#!/bin/bash
# BitHuman Avatar Service Starter
cd /Users/hhsw/Desktop/sunriza26
source venv/bin/activate

# BitHuman API-Key setzen
export BITHUMAN_API_SECRET="JVKA8KONIH7K2U4HcPFQdycLiy83BHCLSfTh41FIIgA5fyTRgUP8NYxzkdwU07AZD"
# Offizieller Paid Figure-Creation-Endpoint
export BITHUMAN_FIGURE_CREATE_URL="https://api.bithuman.ai/figure/create"

# Port freigeben falls belegt
PID=$(lsof -ti tcp:4202)
if [ -n "$PID" ]; then
    echo "🔄 Stoppe vorherigen Service (PID: $PID)"
    kill $PID
    sleep 2
fi

echo "🚀 Starte BitHuman Avatar Service..."
python backend/bithuman_service_clean.py
