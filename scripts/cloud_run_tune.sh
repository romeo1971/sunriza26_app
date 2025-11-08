#!/usr/bin/env bash
set -euo pipefail

# Kurz: Senkt Cloud Run Kosten durch konservative Limits.
# Nutzung:
#   ./scripts/cloud_run_tune.sh -s SERVICE -r REGION
# Optional:
#   ENV: MIN=0 MAX=2 CONC=100 MEM=512Mi CPU=0.5
#
# Beispiel:
#   MIN=0 MAX=2 CONC=100 MEM=512Mi CPU=0.5 ./scripts/cloud_run_tune.sh -s my-api -r europe-west1

usage() {
  echo "Usage: $0 -s SERVICE -r REGION"
  echo "Env (optional): MIN MAX CONC MEM CPU"
  exit 1
}

SERVICE=""
REGION=""
while getopts "s:r:h" opt; do
  case "$opt" in
    s) SERVICE="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    h|*) usage ;;
  esac
done

[[ -z "${SERVICE}" || -z "${REGION}" ]] && usage

MIN="${MIN:-0}"
MAX="${MAX:-2}"
CONC="${CONC:-100}"
MEM="${MEM:-512Mi}"
CPU="${CPU:-0.5}"

echo "Tuning Cloud Run service=${SERVICE}, region=${REGION}"
echo "→ min-instances=${MIN}, max-instances=${MAX}, concurrency=${CONC}, memory=${MEM}, cpu=${CPU}"

# 1) Haupt-Update (keine CPU immer an; defaults sparen Kosten)
gcloud run services update "${SERVICE}" --region="${REGION}" \
  --min-instances="${MIN}" --max-instances="${MAX}" \
  --concurrency="${CONC}" --memory="${MEM}" --cpu="${CPU}"

# 2) Auf letzte Revision routen (nur 1 aktiv)
gcloud run services update-traffic "${SERVICE}" --region="${REGION}" --to-latest >/dev/null

# 3) Ausgabe kompakt
gcloud run services describe "${SERVICE}" --region="${REGION}" \
  --format="value(metadata.name,spec.template.metadata.name,spec.template.spec.containers[0].resources,lifecycle.condition,trafficStatus)"

echo "OK"


