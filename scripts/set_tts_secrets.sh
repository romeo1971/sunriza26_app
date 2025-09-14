#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tts_apiKeys/eleven.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "eleven.env nicht gefunden: $ENV_FILE" >&2
  echo "Beispiel:\nELEVEN_API_KEY=...\nELEVEN_VOICE_ID=21m00Tcm4TlvDq8ikWAM\nELEVEN_TTS_MODEL=eleven_multilingual_v2" >&2
  exit 1
fi

# Shell-Export der Variablen
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ -z "${ELEVEN_API_KEY:-}" ]]; then
  echo "ELEVEN_API_KEY fehlt in $ENV_FILE" >&2
  exit 1
fi

printf %s "$ELEVEN_API_KEY" | firebase functions:secrets:set ELEVEN_API_KEY --data-file=-

if [[ -n "${ELEVEN_VOICE_ID:-}" ]]; then
  printf %s "$ELEVEN_VOICE_ID" | firebase functions:secrets:set ELEVEN_VOICE_ID --data-file=-
fi

if [[ -n "${ELEVEN_TTS_MODEL:-}" ]]; then
  printf %s "$ELEVEN_TTS_MODEL" | firebase functions:secrets:set ELEVEN_TTS_MODEL --data-file=-
fi

echo "Secrets gesetzt. Jetzt deployen:"
echo "firebase deploy --only functions:testTTS"
