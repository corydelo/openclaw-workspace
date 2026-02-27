#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
AGENT_DIR="$ROOT_DIR/agent"
ROOT_ENV="$ROOT_DIR/.env"
INFRA_ENV="$INFRA_DIR/.env"
AGENT_ENV="$AGENT_DIR/config/.env"
AGENT_ENV_EXAMPLE="$AGENT_DIR/config/.env.example"
INFRA_VENV="$INFRA_DIR/venv"
INFRA_PID_FILE="$ROOT_DIR/.infra.pid"
INFRA_LOG_FILE="$ROOT_DIR/.infra.log"

pid_is_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

is_oracle_infra_pid() {
  local pid="$1"
  local cmd
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ -n "$cmd" ]]; then
    [[ "$cmd" == *"uvicorn"* && "$cmd" == *"src.api.server:app"* ]]
    return $?
  fi
  # Fallback when process metadata is restricted: trust active listener on infra port.
  lsof -nP -a -p "$pid" -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1
}

discover_oracle_infra_pid() {
  local pid
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if pid_is_running "$pid" && is_oracle_infra_pid "$pid"; then
      echo "$pid"
      return 0
    fi
  done < <(lsof -tiTCP:8000 -sTCP:LISTEN 2>/dev/null || true)
  return 1
}

adopt_oracle_infra_pid_if_running() {
  local pid
  pid="$(discover_oracle_infra_pid || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid" >"$INFRA_PID_FILE"
    return 0
  fi
  return 1
}

compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return 0
  fi
  echo "ERROR: docker compose not found (need docker-compose or docker compose)." >&2
  exit 1
}

generate_oracle_key() {
  if command -v openssl >/dev/null 2>&1; then
    echo "llm_$(openssl rand -hex 24)"
  else
    echo "llm_$(date +%s)_$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
}

upsert_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp /tmp/bootstrap.XXXXXX)"
  awk -v k="$key" -v v="$value" '
    BEGIN { found=0 }
    $0 ~ ("^" k "=") { print k "=" v; found=1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$file" >"$tmp_file"
  cat "$tmp_file" > "$file"
  rm "$tmp_file"
}

ensure_root_env() {
  mkdir -p "$ROOT_DIR"
  if [[ ! -f "$ROOT_ENV" ]]; then
    touch "$ROOT_ENV"
  fi

  export TMPDIR="$PWD/.tmp"
  mkdir -p "$TMPDIR"
  # shellcheck disable=SC1090
  set -a && source "$ROOT_ENV" && set +a

  if [[ -z "${ORACLE_API_KEY:-}" ]]; then
    ORACLE_API_KEY="$(generate_oracle_key)"
    upsert_env "$ROOT_ENV" "ORACLE_API_KEY" "$ORACLE_API_KEY"
  fi
  if [[ -z "${LLM_ARCH_BASE_URL:-}" ]]; then
    LLM_ARCH_BASE_URL="http://127.0.0.1:8000"
    upsert_env "$ROOT_ENV" "LLM_ARCH_BASE_URL" "$LLM_ARCH_BASE_URL"
  fi
  if [[ -z "${WORKFLOW_APPROVAL_MODE:-}" ]]; then
    WORKFLOW_APPROVAL_MODE="on-risk"
    upsert_env "$ROOT_ENV" "WORKFLOW_APPROVAL_MODE" "$WORKFLOW_APPROVAL_MODE"
  fi
  if [[ -z "${WORKFLOW_TOKEN_BUDGET:-}" ]]; then
    WORKFLOW_TOKEN_BUDGET="6000"
    upsert_env "$ROOT_ENV" "WORKFLOW_TOKEN_BUDGET" "$WORKFLOW_TOKEN_BUDGET"
  fi
}

ensure_infra_env() {
  touch "$INFRA_ENV"
  upsert_env "$INFRA_ENV" "API_KEYS" "${ORACLE_API_KEY}"
  upsert_env "$INFRA_ENV" "API_AUTH_MODE" "${API_AUTH_MODE:-required}"
  upsert_env "$INFRA_ENV" "API_AUTH_ALLOW_EMPTY_KEYS" "${API_AUTH_ALLOW_EMPTY_KEYS:-false}"
  upsert_env "$INFRA_ENV" "WORKFLOW_APPROVAL_MODE" "${WORKFLOW_APPROVAL_MODE:-on-risk}"
  upsert_env "$INFRA_ENV" "WORKFLOW_TOKEN_BUDGET" "${WORKFLOW_TOKEN_BUDGET:-6000}"
  if ! grep -q "^CLOUD_ONLY=" "$INFRA_ENV"; then
    upsert_env "$INFRA_ENV" "CLOUD_ONLY" "true"
  fi

  # Optional Venice routing settings: if set in root env or shell, propagate
  # to infra/.env so router + provider share one source of truth.
  local venice_keys=(
    "VENICE_API_KEY"
    "VENICE_DIEM_STAKE"
    "VENICE_CHEAP_MODEL"
    "VENICE_BASE_MODEL"
    "VENICE_FRONTIER_MODEL"
    "VENICE_FRONTIER_REASONING_MODEL"
    "VENICE_FRONTIER_CODING_MODEL"
    "VENICE_API_BASE_URL"
    "VENICE_BURN_ENABLED"
    "VENICE_DAILY_TOKEN_BUDGET"
    "VENICE_BURN_RESERVE_TOKENS"
    "VENICE_RESET_HOUR_LOCAL"
    "VENICE_BURN_FORCE_PROFILE"
    "VENICE_BURN_FALLBACK_PROFILE"
    "VENICE_BURN_STATE_FILE"
  )
  local venice_key
  for venice_key in "${venice_keys[@]}"; do
    if [[ -n "${!venice_key:-}" ]]; then
      upsert_env "$INFRA_ENV" "$venice_key" "${!venice_key}"
    fi
  done
}

ensure_agent_env() {
  if [[ ! -f "$AGENT_ENV" ]]; then
    if [[ ! -f "$AGENT_ENV_EXAMPLE" ]]; then
      echo "ERROR: missing $AGENT_ENV_EXAMPLE" >&2
      exit 1
    fi
    cp "$AGENT_ENV_EXAMPLE" "$AGENT_ENV"
    echo "Created $AGENT_ENV from template"
  fi

  local gateway_token
  gateway_token="$(awk -F= '/^GATEWAY_TOKEN=/{print $2}' "$AGENT_ENV" | tail -n 1 || true)"
  if [[ -z "$gateway_token" || "$gateway_token" == "your_secure_random_token_here" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      gateway_token="$(openssl rand -hex 32)"
    else
      gateway_token="$(date +%s)_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    fi
    upsert_env "$AGENT_ENV" "GATEWAY_TOKEN" "$gateway_token"
  fi

  upsert_env "$AGENT_ENV" "ORACLE_API_KEY" "${ORACLE_API_KEY}"
  upsert_env "$AGENT_ENV" "ORACLE_BASE_URL" "${LLM_ARCH_BASE_URL}/v1"
  chmod 600 "$AGENT_ENV"
}

sync_submodules() {
  git -C "$ROOT_DIR" submodule sync --recursive
  local dirty_paths
  dirty_paths="$(submodule_dirty_paths)"
  if strict_submodule_pins_enabled; then
    if [[ -n "$dirty_paths" ]]; then
      echo "ERROR: STRICT_SUBMODULE_PINS is enabled and submodules are dirty:" >&2
      while IFS= read -r path; do
        [[ -n "$path" ]] && echo "  - $path" >&2
      done <<< "$dirty_paths"
      echo "Commit/stash submodule changes or disable STRICT_SUBMODULE_PINS for local dev." >&2
      exit 1
    fi
    git -C "$ROOT_DIR" submodule update --init --recursive
    return 0
  fi

  if [[ -n "$dirty_paths" ]]; then
    echo "Skipping submodule update due local changes in:" >&2
    while IFS= read -r path; do
      [[ -n "$path" ]] && echo "  - $path" >&2
    done <<< "$dirty_paths"
    return 0
  fi
  git -C "$ROOT_DIR" submodule update --init --recursive
}

submodule_dirty_paths() {
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ -n "$(git -C "$ROOT_DIR/$path" status --short 2>/dev/null || true)" ]]; then
      echo "$path"
    fi
  done < <(git -C "$ROOT_DIR" config --file .gitmodules --get-regexp path | awk '{print $2}')
}

truthy() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

strict_submodule_pins_enabled() {
  if truthy "${STRICT_SUBMODULE_PINS:-}"; then
    return 0
  fi
  if truthy "${CI:-}"; then
    return 0
  fi
  return 1
}

verify_submodule_pins() {
  if strict_submodule_pins_enabled; then
    local strict_bad
    strict_bad="$(git -C "$ROOT_DIR" submodule status --recursive | grep -E '^[+-U]' || true)"
    if [[ -n "$strict_bad" ]]; then
      echo "ERROR: STRICT_SUBMODULE_PINS failed; submodule pins do not match committed SHAs:" >&2
      echo "$strict_bad" >&2
      exit 1
    fi
    return 0
  fi

  local dirty_paths
  dirty_paths="$(submodule_dirty_paths)"
  if [[ -n "$dirty_paths" ]]; then
    echo "Skipping submodule pin verification due local changes in:" >&2
    while IFS= read -r path; do
      [[ -n "$path" ]] && echo "  - $path" >&2
    done <<< "$dirty_paths"
    return 0
  fi

  local bad
  bad="$(git -C "$ROOT_DIR" submodule status --recursive | grep -E '^[+-U]' || true)"
  if [[ -n "$bad" ]]; then
    echo "ERROR: submodules are not pinned to committed SHAs:" >&2
    echo "$bad" >&2
    exit 1
  fi
}

install_infra_deps() {
  if [[ ! -d "$INFRA_VENV" ]]; then
    python3 -m venv "$INFRA_VENV"
  fi
  "$INFRA_VENV/bin/python" -m pip install --upgrade pip >/dev/null
  "$INFRA_VENV/bin/pip" install -r "$INFRA_DIR/requirements.txt"
}

wait_for_infra() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl -fsS "http://127.0.0.1:8000/docs" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done
  return 1
}

start_infra() {
  if [[ -f "$INFRA_PID_FILE" ]]; then
    local existing_pid
    existing_pid="$(cat "$INFRA_PID_FILE" 2>/dev/null || true)"
    if pid_is_running "$existing_pid" && is_oracle_infra_pid "$existing_pid"; then
      echo "Infra already running (pid: $existing_pid)"
      return 0
    fi
    rm -f "$INFRA_PID_FILE"
  fi

  if adopt_oracle_infra_pid_if_running; then
    local adopted_pid
    adopted_pid="$(cat "$INFRA_PID_FILE")"
    echo "Adopted existing infra process (pid: $adopted_pid)"
    return 0
  fi

  local launched_pid
  (
    cd "$INFRA_DIR"
    # shellcheck disable=SC1090
    set -a && source "$INFRA_ENV" && set +a
    nohup "$INFRA_VENV/bin/uvicorn" src.api.server:app --host 127.0.0.1 --port 8000 >"$INFRA_LOG_FILE" 2>&1 &
    launched_pid="$!"
    echo "$launched_pid" >"$INFRA_PID_FILE"
    printf '%s\n' "$launched_pid"
  ) >"$ROOT_DIR/.infra.launch.out"

  launched_pid="$(tail -n 1 "$ROOT_DIR/.infra.launch.out" 2>/dev/null || true)"
  rm -f "$ROOT_DIR/.infra.launch.out"

  # Catch immediate bind/crash failure before readiness loop.
  sleep 1
  if ! pid_is_running "$launched_pid"; then
    echo "ERROR: infra process exited immediately (pid: $launched_pid)." >&2
    tail -n 80 "$INFRA_LOG_FILE" >&2 || true
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  if ! wait_for_infra; then
    echo "ERROR: infra did not become ready. Tail of $INFRA_LOG_FILE:" >&2
    tail -n 80 "$INFRA_LOG_FILE" >&2 || true
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  if ! pid_is_running "$launched_pid"; then
    # Another valid process may own :8000; adopt if it's Oracle, otherwise fail.
    if adopt_oracle_infra_pid_if_running; then
      local adopted_pid
      adopted_pid="$(cat "$INFRA_PID_FILE")"
      echo "Infra ready at http://127.0.0.1:8000 (adopted pid: $adopted_pid)"
      return 0
    fi
    echo "ERROR: infra became reachable but launched pid is not running." >&2
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  echo "Infra ready at http://127.0.0.1:8000"
}

stop_infra() {
  local pid=""
  if [[ -f "$INFRA_PID_FILE" ]]; then
    pid="$(cat "$INFRA_PID_FILE" 2>/dev/null || true)"
    if ! (pid_is_running "$pid" && is_oracle_infra_pid "$pid"); then
      pid=""
      rm -f "$INFRA_PID_FILE"
    fi
  fi

  if [[ -z "$pid" ]]; then
    pid="$(discover_oracle_infra_pid || true)"
    if [[ -n "$pid" ]]; then
      echo "$pid" >"$INFRA_PID_FILE"
    fi
  fi

  if [[ -z "$pid" ]]; then
    echo "Infra not running"
    return 0
  fi

  if pid_is_running "$pid"; then
    kill "$pid"
    for _ in {1..10}; do
      if ! pid_is_running "$pid"; then
        break
      fi
      sleep 1
    done
    if pid_is_running "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    echo "Stopped infra (pid: $pid)"
  fi
  rm -f "$INFRA_PID_FILE"
}

start_agent() {
  local compose
  compose="$(compose_cmd)"
  (
    cd "$AGENT_DIR/docker"
    # shellcheck disable=SC2086
    $compose --env-file ../config/.env -f docker-compose.yml up -d --remove-orphans
  )
}

stop_agent() {
  local compose
  compose="$(compose_cmd)"
  (
    cd "$AGENT_DIR/docker"
    # shellcheck disable=SC2086
    $compose --env-file ../config/.env -f docker-compose.yml down --remove-orphans
  )
}

run_contract_test() {
  (
    cd "$ROOT_DIR"
    python3 contract-tests/contract_test_openai_compat.py
  )
}

run_e2e_smoke() {
  (
    cd "$ROOT_DIR"
    python3 e2e/smoke_e2e.py
  )
}

run_smoke() {
  prepare
  start_agent
  start_infra
  run_contract_test
  run_e2e_smoke
}

prepare() {
  ensure_root_env
  ensure_infra_env
  ensure_agent_env
  sync_submodules
  verify_submodule_pins
  install_infra_deps
}

up_all() {
  prepare
  start_agent
  start_infra
  run_contract_test
}

down_all() {
  stop_agent
  stop_infra
}

cmd="${1:-up}"
case "$cmd" in
  prepare) prepare ;;
  infra-up) prepare; start_infra ;;
  infra-down) stop_infra ;;
  agent-up) prepare; start_agent ;;
  agent-down) stop_agent ;;
  contract-test) ensure_root_env; ensure_infra_env; install_infra_deps; start_infra; run_contract_test ;;
  smoke) run_smoke ;;
  up) up_all ;;
  down) down_all ;;
  *)
    echo "Usage: $0 {prepare|infra-up|infra-down|agent-up|agent-down|contract-test|smoke|up|down}" >&2
    exit 1
    ;;
esac
