#!/usr/bin/env bash
set -euo pipefail

# Deploy: Flutter Web (Hosting) + Functions + Rules + Indexes + Storage + RTDB
# Usage:
#   ./scripts/firebase_deploy_all.sh -p PROJECT_ID

PROJECT=""
while getopts "p:h" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    h|*) echo "Usage: $0 -p PROJECT_ID"; exit 1 ;;
  esac
done

if ! command -v firebase >/dev/null 2>&1; then
  echo "ERROR: firebase CLI nicht gefunden. Install: npm i -g firebase-tools"
  exit 1
fi

echo "🔧 Baue Flutter Web..."
flutter build web --release

echo "📦 Functions: install + build..."
(cd functions && npm ci && npm run build)

DEPLOY_ARGS=(deploy --only hosting,functions,firestore:rules,firestore:indexes,storage,database)
if [[ -n "${PROJECT}" ]]; then
  DEPLOY_ARGS+=(--project "${PROJECT}")
fi

echo "🚀 Firebase Deploy..."
firebase "${DEPLOY_ARGS[@]}"

echo "✅ Fertig."



