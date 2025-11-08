#!/usr/bin/env bash
set -euo pipefail

# Drosselt ALLE Cloud Run Services ohne Platzhalter.
# Nutzung:
#   ./scripts/cloud_run_tune_all.sh
# Optional via Env:
#   MIN=0 MAX=2 CONC=100 MEM=512Mi CPU=0.5 ./scripts/cloud_run_tune_all.sh

MIN="${MIN:-0}"
MAX="${MAX:-2}"
CONC="${CONC:-100}"
MEM="${MEM:-512Mi}"
CPU="${CPU:-0.5}"

echo "Tuning ALL Cloud Run services: min=${MIN} max=${MAX} conc=${CONC} mem=${MEM} cpu=${CPU}"

gcloud run services list --platform=managed --format='value(NAME,REGION)' | while read -r SVC REG; do
  [[ -z "${SVC:-}" || -z "${REG:-}" ]] && continue
  echo "→ ${SVC} (${REG})"
  gcloud run services update "${SVC}" --region="${REG}" \
    --min-instances="${MIN}" --max-instances="${MAX}" \
    --concurrency="${CONC}" --memory="${MEM}" --cpu="${CPU}"
  gcloud run services update-traffic "${SVC}" --region="${REG}" --to-latest >/dev/null
done

echo "OK"


