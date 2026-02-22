#!/usr/bin/env bash
# start-infra.sh — Start Oracle infra with Venice burn-down routing
# Bypasses bootstrap.sh's .env sourcing (which may fail under Finder sandbox).
# Run from a regular Terminal.app to pick up full env context.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/infra"
LOG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.infra.log"

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
source /Users/corydelouche/Codex/openclaw-workspace/.env || true
source /Users/corydelouche/Codex/openclaw-workspace/infra/.env || true
set +a

nohup ./venv/bin/python3.14 -m uvicorn src.api.server:app \
    --host 127.0.0.1 --port 8000 \
    > "$LOG_FILE" 2>&1 &
INFRA_PID=$!
echo "$INFRA_PID" > /Users/corydelouche/Codex/openclaw-workspace/.infra.pid
echo "Started PID $INFRA_PID → log: $LOG_FILE"

# Wait for readiness
echo "Waiting for infra readiness..."
for i in $(seq 1 20); do
    if curl -fsS http://127.0.0.1:8000/docs > /dev/null 2>&1; then
        echo "✅ Infra ready at http://127.0.0.1:8000"
        echo ""
        echo "Venice burn status:"
        curl -sS http://127.0.0.1:8000/admin/status \
            -H "X-Admin-Token: jkNkK1Rlc3GJC+XrBZ/Bo2cxiFwtz87DdDVIsSdQN3g=" 2>/dev/null \
            | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('venice_burn', d), indent=2))" 2>/dev/null || true
        exit 0
    fi
    sleep 1
done
echo "❌ Infra did not come up in time — check: $LOG_FILE"
tail -20 "$LOG_FILE"
exit 1
