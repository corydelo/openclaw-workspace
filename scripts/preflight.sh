#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_PATH="${ROOT_DIR}/.code-factory.yaml"
SCHEMA_PATH="${ROOT_DIR}/.code-factory.schema.json"
REPORT_DIR="/tmp/openclaw-preflight"
REPORT_PATH="${REPORT_DIR}/preflight-$(date -u +%Y%m%dT%H%M%SZ).json"

mkdir -p "${REPORT_DIR}"

CMD=(
  python3 "${ROOT_DIR}/scripts/preflight_gate.py"
  --repo-root "${ROOT_DIR}"
  --contract "${CONTRACT_PATH}"
  --schema "${SCHEMA_PATH}"
  --report "${REPORT_PATH}"
)

for changed in "$@"; do
  CMD+=(--changed-file "$changed")
done

set +e
"${CMD[@]}"
EXIT_CODE=$?
set -e

printf '%s\n' "preflight_report:${REPORT_PATH}"

if [[ ${EXIT_CODE} -ne 0 ]]; then
  printf '%s\n' "preflight_status:failed"
else
  printf '%s\n' "preflight_status:passed"
fi

exit ${EXIT_CODE}
