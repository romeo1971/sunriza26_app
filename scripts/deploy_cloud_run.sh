#!/usr/bin/env bash
set -euo pipefail

# Usage:
#  ./scripts/deploy_cloud_run.sh <gcp_project> <region>
# Requires: gcloud auth login; gcloud config set project <id>

PROJECT_ID=${1:-}
REGION=${2:-europe-west3}

if [[ -z "$PROJECT_ID" ]]; then
  echo "Bitte GCP Project-ID angeben: ./scripts/deploy_cloud_run.sh <project> [region]" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

SERVICE_MEMORY=memory-backend
SERVICE_AVATAR=avatar-backend

echo "Bauen und Deployen (Cloud Run) für Projekt $PROJECT_ID in Region $REGION"

# Build & deploy memory backend
gcloud builds submit --project $PROJECT_ID --tag gcr.io/$PROJECT_ID/$SERVICE_MEMORY -q --config cloudbuild_memory.yaml .
gcloud run deploy $SERVICE_MEMORY \
  --image gcr.io/$PROJECT_ID/$SERVICE_MEMORY \
  --platform managed \
  --project $PROJECT_ID \
  --region $REGION \
  --allow-unauthenticated \
  --concurrency 40 \
  --min-instances 2 \
  --max-instances 100 \
  --timeout 300 \
  --set-env-vars ELEVENLABS_API_KEY=${ELEVENLABS_API_KEY:-} \
  --set-env-vars PINECONE_API_KEY=${PINECONE_API_KEY:-} \
  --set-env-vars PINECONE_INDEX=${PINECONE_INDEX:-sunriza} \
  --set-env-vars GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/key.json \
  --cpu 1 --memory 1Gi

URL_MEMORY=$(gcloud run services describe $SERVICE_MEMORY --region $REGION --format 'value(status.url)')
echo "Memory Backend URL: $URL_MEMORY"

# Build & deploy avatar backend
gcloud builds submit --project $PROJECT_ID --tag gcr.io/$PROJECT_ID/$SERVICE_AVATAR -q --config cloudbuild_avatar.yaml .
gcloud run deploy $SERVICE_AVATAR \
  --image gcr.io/$PROJECT_ID/$SERVICE_AVATAR \
  --platform managed \
  --project $PROJECT_ID \
  --region $REGION \
  --allow-unauthenticated \
  --concurrency 20 \
  --min-instances 1 \
  --max-instances 50 \
  --timeout 300 \
  --set-env-vars BITHUMAN_API_KEY=${BITHUMAN_API_KEY:-} \
  --cpu 1 --memory 1Gi

URL_AVATAR=$(gcloud run services describe $SERVICE_AVATAR --region $REGION --format 'value(status.url)')
echo "Avatar Backend URL: $URL_AVATAR"

echo "Trage folgende Keys in .env ein:"
echo "MEMORY_API_BASE_URL=$URL_MEMORY"
echo "BITHUMAN_BASE_URL=$URL_AVATAR"


