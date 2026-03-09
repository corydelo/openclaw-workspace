#!/usr/bin/env bash
# start-infra.sh — Start Oracle infra with canonical env + runtime paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/infra"
LOG_FILE="${ROOT_DIR}/.infra.log"
PID_FILE="${ROOT_DIR}/.infra.pid"

# Kill any existing infra on port 8000
if lsof -tiTCP:8000 -sTCP:LISTEN > /dev/null 2>&1; then
    echo "Stopping existing infra on :8000..."
    lsof -tiTCP:8000 -sTCP:LISTEN | xargs kill -TERM 2>/dev/null || true
    sleep 2
fi

echo "Starting Oracle infra with Venice burn-down routing..."
cd "$INFRA_DIR"

set -a
# shellcheck disable=SC1091
[ -f "${ROOT_DIR}/.env" ] && source "${ROOT_DIR}/.env"
# shellcheck disable=SC1091
[ -f "${INFRA_DIR}/.env" ] && source "${INFRA_DIR}/.env"
set +a

if [[ -z "${OPENCLAW_DATA_DIR:-}" ]]; then
    OPENCLAW_DATA_DIR="${ROOT_DIR}/.openclaw_data"
fi
mkdir -p "$OPENCLAW_DATA_DIR"
export OPENCLAW_DATA_DIR

PY_BIN="./venv/bin/python"
if [[ ! -x "$PY_BIN" ]]; then
    PY_BIN="./.venv/bin/python"
fi
if [[ ! -x "$PY_BIN" ]]; then
    echo "❌ Could not find infra python at ./venv/bin/python or ./.venv/bin/python"
    exit 1
fi

INFRA_PID="$(
    INFRA_PY_BIN="$PY_BIN" INFRA_WORKDIR="$INFRA_DIR" INFRA_LOG_FILE="$LOG_FILE" python3 - <<'PY'
import os
import subprocess

cmd = [
    os.environ["INFRA_PY_BIN"],
    "-m",
    "uvicorn",
    "src.api.server:app",
    "--host",
    "127.0.0.1",
    "--port",
    "8000",
]

with open(os.environ["INFRA_LOG_FILE"], "ab", buffering=0) as log_handle:
    proc = subprocess.Popen(
        cmd,
        cwd=os.environ["INFRA_WORKDIR"],
        env=os.environ.copy(),
        stdin=subprocess.DEVNULL,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )

print(proc.pid)
PY
)"
echo "$INFRA_PID" > "$PID_FILE"
echo "Started PID $INFRA_PID → log: $LOG_FILE"

# Wait for readiness
echo "Waiting for infra readiness..."
for _ in $(seq 1 20); do
    if curl -fsS http://127.0.0.1:8000/docs > /dev/null 2>&1; then
        echo "✅ Infra ready at http://127.0.0.1:8000"
        exit 0
    fi
    sleep 1
done
echo "❌ Infra did not come up in time — check: $LOG_FILE"
tail -20 "$LOG_FILE"
exit 1
